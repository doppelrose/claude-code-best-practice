import SwiftData
import SwiftUI
import UIKit

/// Состояние сценария «фото → распознавание → проверка → решение → результат».
@MainActor
@Observable
final class SolveViewModel: Identifiable {
    enum Stage: Equatable {
        /// Показываем фото, пользователь может обвести нужную часть.
        case selecting
        case recognizing
        /// Распознанный текст можно исправить, предмет — поменять.
        case review
        case solving
        case result
    }

    let id = UUID()
    private(set) var stage: Stage

    // Изображение
    private(set) var image: UIImage?
    /// Выделенная область в нормированных координатах изображения.
    var selection: CGRect?
    /// Фрагмент, который реально распознавался (после обрезки).
    private(set) var recognizedImage: UIImage?
    private(set) var recognizedLines: [RecognizedLine] = []
    private(set) var ocrConfidence: Double?
    private(set) var usedMathPass = false
    /// Страницы сканера (JPEG рабочего размера); пусто, если изображение одно.
    private(set) var pages: [Data] = []
    private(set) var pageIndex = 0
    /// Выбранная страница скана ещё раскодируется.
    private(set) var isLoadingPage = false
    /// Почему распознанный текст показан на проверку, а не отправлен на решение сразу.
    private(set) var reviewHint: String?

    // Условие
    var text: String
    private(set) var subject: Subject = .other
    private(set) var subjectGuess: SubjectGuess?
    /// Текст, по которому определён `subjectGuess`: если условие изменилось, предмет определяется заново.
    private var subjectGuessText: String?
    private(set) var isSubjectManual = false

    // Результат
    private(set) var solution: Solution?
    private(set) var analysis: TextAnalysis?
    /// Ответа нет из-за связи с нейросетью — на экране результата «Повторить», а не «Настроить нейросеть».
    private(set) var connectionIssue: String?
    /// Текущий этап решения — диспетчер, точный решатель или нейросеть.
    private(set) var solvingPhase: SolvePhase?
    var errorMessage: String?
    /// Ошибка записи в историю — экран показывает её тостом и сбрасывает.
    var historyError: String?

    // Запись истории. Храним идентификатор, а не сам объект: запись могут удалить, пока экран открыт.
    private var recordID: UUID?
    private(set) var recordCreatedAt: Date?
    private(set) var isFavorite = false
    /// Текст условия, с которым сохранена запись.
    private var recordProblemText: String?
    /// Правка условия относится к той же записи: исправление OCR того же фрагмента или запись из истории.
    private var editsBelongToRecord = false
    /// Сохранённый фрагмент из истории, который ещё нужно раскодировать.
    private var restoredImageData: Data?

    private let settings: AppSettings
    private let coordinator: SolveCoordinator
    private var workTask: Task<Void, Never>?
    private var detectionTask: Task<Void, Never>?
    private var autoRecognizeTask: Task<Void, Never>?
    private var preparationTask: Task<Void, Never>?
    private var shouldAutoSolve = false
    /// Сценарий закрыт: никакая отложенная работа уже не запускается и ничего не сохраняет.
    private(set) var isClosed = false
    /// Контекст SwiftData — нужен, чтобы сразу после распознавания решить и сохранить задание.
    private var modelContext: ModelContext?
    /// Фоновое время у системы: запрос к нейросети не обрывается, если свернуть приложение.
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var wasBackgroundedWhileSolving = false

    var l: L10n { settings.l }
    var hasImage: Bool { image != nil }
    var hasPages: Bool { pages.count > 1 }
    /// Есть запись в истории (её можно добавить в избранное).
    var hasRecord: Bool { recordID != nil }
    /// Идёт распознавание или решение — прерывать молча нельзя.
    var isBusy: Bool { stage == .recognizing || stage == .solving }

    init(input: SolveInput, settings: AppSettings, coordinator: SolveCoordinator) {
        self.settings = settings
        self.coordinator = coordinator
        switch input {
        case .image(let picked):
            image = picked
            text = ""
            stage = .selecting
        case .pages(let scanned, let first):
            pages = scanned
            image = first
            text = ""
            stage = .selecting
        case .text(let value, let presetSubject, let autoSolve):
            text = value
            // Условие уже введено пользователем — сразу решаем (см. `startAutoSolveIfNeeded`).
            let solvesNow = autoSolve && !value.trimmed.isEmpty
            stage = solvesNow ? .solving : .review
            shouldAutoSolve = solvesNow
            if let presetSubject {
                subject = presetSubject
                isSubjectManual = true
            }
        case .restored(let restored):
            text = restored.text
            subject = restored.subject
            isSubjectManual = true
            recordID = restored.recordID
            recordProblemText = restored.text
            editsBelongToRecord = true
            restoredImageData = restored.imageData
            let solvesNow = restored.autoSolve && (!restored.text.trimmed.isEmpty || restored.imageData != nil)
            stage = solvesNow ? .solving : .review
            shouldAutoSolve = solvesNow
        }
    }

    func attach(_ context: ModelContext) {
        modelContext = context
        if let recordID, recordCreatedAt == nil, let record = HistoryStore.record(id: recordID, in: context) {
            recordCreatedAt = record.createdAt
            isFavorite = record.isFavorite
        }
    }

    /// Вызывается при появлении экрана.
    func onAppear() {
        guard !isClosed else { return }
        if let data = restoredImageData {
            // Фрагмент из истории: раскодируем вне главного потока, затем (если нужно) решаем.
            restoredImageData = nil
            preparationTask = Task {
                let decoded = await Task.detached(priority: .userInitiated) {
                    UncheckedSendable(ImageTools.downsampled(data))
                }.value
                guard !Task.isCancelled, !isClosed else { return }
                if let restoredImage = decoded.value {
                    image = restoredImage
                    recognizedImage = restoredImage
                }
                startAutoSolveIfNeeded()
            }
        } else {
            if let image, image.imageOrientation != .up || image.scale != 1
                || max(image.size.width, image.size.height) > ImageTools.workingDimension
            {
                // Обычно изображение уже подготовлено (AppModel); это страховка для других источников.
                let boxed = UncheckedSendable(image)
                preparationTask = Task {
                    let normalized = await Task.detached(priority: .userInitiated) {
                        UncheckedSendable(ImageTools.normalized(boxed.value, maxDimension: ImageTools.workingDimension))
                    }.value
                    guard !Task.isCancelled, !isClosed else { return }
                    self.image = normalized.value
                }
            }
            startAutoSolveIfNeeded()
        }
        if stage == .review, !text.trimmed.isEmpty, !isSubjectManual {
            scheduleSubjectDetection(immediately: true)
        }
    }

    private func startAutoSolveIfNeeded() {
        guard shouldAutoSolve else { return }
        shouldAutoSolve = false
        if canSolve, let modelContext {
            solve(context: modelContext)
        } else {
            setStage(.review)
        }
    }

    /// Сценарий закрыт: отменяем всё, включая отложенный запуск распознавания.
    func cancel() {
        isClosed = true
        workTask?.cancel()
        detectionTask?.cancel()
        autoRecognizeTask?.cancel()
        preparationTask?.cancel()
        endBackgroundTask(backgroundTaskID)
    }

    /// Приложение свернули или вернули — запоминаем, если это случилось во время решения.
    func scenePhaseChanged(_ phase: ScenePhase) {
        if phase == .background, stage == .solving {
            wasBackgroundedWhileSolving = true
        }
    }

    private func setStage(_ newStage: Stage) {
        withAnimation(Theme.spring) {
            stage = newStage
        }
    }

    // MARK: - Pages

    /// Выбор страницы скана: страница раскодируется в фоне, выделение сбрасывается.
    func selectPage(_ index: Int) {
        guard !isClosed, pages.indices.contains(index), index != pageIndex, stage == .selecting else { return }
        Haptics.selection()
        autoRecognizeTask?.cancel()
        pageIndex = index
        selection = nil
        errorMessage = nil
        isLoadingPage = true
        let data = pages[index]
        preparationTask?.cancel()
        preparationTask = Task {
            let decoded = await Task.detached(priority: .userInitiated) {
                UncheckedSendable(ImageTools.downsampled(data))
            }.value
            guard !Task.isCancelled, !isClosed, pageIndex == index else { return }
            isLoadingPage = false
            if let page = decoded.value {
                image = page
            } else {
                errorMessage = l("Не удалось открыть эту страницу.", "Could not open this page.")
            }
        }
    }

    // MARK: - Recognition

    /// Пользователь обвёл область: короткая пауза, чтобы было видно рамку, затем распознаём.
    /// Касание маркера, новое выделение или закрытие сценария отменяют запуск.
    func selectionFinished() {
        guard !isClosed else { return }
        autoRecognizeTask?.cancel()
        autoRecognizeTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, !isClosed, stage == .selecting, selection != nil else { return }
            recognize(useSelection: true)
        }
    }

    /// Пользователь поправляет рамку — автоматический запуск больше не нужен.
    func selectionAdjustmentBegan() {
        autoRecognizeTask?.cancel()
    }

    /// Распознаёт текст на всём изображении или в выделенной области.
    func recognize(useSelection: Bool) {
        guard !isClosed, !isLoadingPage, let image else { return }
        autoRecognizeTask?.cancel()
        errorMessage = nil
        reviewHint = nil
        // Новый фрагмент — новое задание: результат сохранится новой записью, прежняя останется в истории.
        detachRecord()
        Haptics.press()
        setStage(.recognizing)
        let region = useSelection ? selection : nil
        let boxed = UncheckedSendable(image)

        workTask?.cancel()
        workTask = Task {
            let started = Date()
            // Обрезаем из изображения рабочего размера (до 3000 px), поэтому мелкая формула не теряет разрешение.
            let prepared = await Task.detached(priority: .userInitiated) { () -> UncheckedSendable<UIImage?> in
                let base = ImageTools.normalized(boxed.value, maxDimension: ImageTools.workingDimension)
                guard let region else { return UncheckedSendable<UIImage?>(base) }
                return UncheckedSendable<UIImage?>(ImageTools.crop(base, to: region))
            }.value
            guard !Task.isCancelled, !isClosed else { return }
            guard let fragment = prepared.value else {
                // Слишком маленькую область не подменяем молча всем изображением.
                fail(
                    l(
                        "Выделенная область слишком мала — обведите задание побольше.",
                        "The selected area is too small — circle a larger part of the task."))
                return
            }
            recognizedImage = fragment

            guard let cgImage = fragment.cgImage else {
                fail(OCRError.failed("no bitmap").message(l))
                return
            }
            do {
                let result = try await OCRService.recognize(UncheckedSendable(cgImage))
                guard !Task.isCancelled, !isClosed else { return }
                // Анимация сканирования не должна мелькать, если распознавание заняло доли секунды.
                let elapsed = Date().timeIntervalSince(started)
                if elapsed < 0.3 { try? await Task.sleep(for: .milliseconds(Int((0.3 - elapsed) * 1000))) }
                guard !Task.isCancelled, !isClosed else { return }

                text = result.text
                recognizedLines = result.lines
                ocrConfidence = result.averageConfidence
                usedMathPass = result.usedMathPass
                isSubjectManual = false
                let guess = await coordinator.detectSubject(result.text)
                guard !Task.isCancelled, !isClosed else { return }
                subjectGuess = guess
                subjectGuessText = result.text.trimmed
                subject = guess.subject
                if OCRService.needsReview(result) {
                    // Сомнительное распознавание — сначала показываем текст, а не тратим запрос на неверное условие.
                    Haptics.success()
                    reviewHint = reviewReason(for: result)
                    setStage(.review)
                } else if let modelContext {
                    // Распознано уверенно — решаем сразу; исправить текст можно потом («Изменить»).
                    solve(context: modelContext)
                } else {
                    setStage(.review)
                }
            } catch {
                guard !Task.isCancelled, !isClosed else { return }
                // Текста не нашлось (чертёж, рукопись). Сразу не отправляем: изображение уходит в нейросеть
                // только если это разрешено в настройках. Открываем проверку — можно ввести условие
                // или нажать «Решить», чтобы нейросеть прочитала картинку.
                if coordinator.canSolveImagesRemotely {
                    text = ""
                    recognizedLines = []
                    ocrConfidence = nil
                    subjectGuess = nil
                    subjectGuessText = nil
                    subject = isSubjectManual ? subject : .other
                    Haptics.warning()
                    reviewHint = l(
                        "Текст на изображении не найден. Введите условие вручную или нажмите «Решить» — тогда фрагмент прочитает нейросеть, если отправка изображений включена в настройках.",
                        "No text was found in the image. Type the task, or tap “Solve” to let the AI model read the fragment if sending images is enabled in Settings.")
                    setStage(.review)
                    return
                }
                if let ocrError = error as? OCRError {
                    fail(ocrError.message(l))
                } else {
                    fail(OCRError.failed(error.localizedDescription).message(l))
                }
            }
        }
    }

    private func reviewReason(for result: OCRResult) -> String {
        if OCRService.hasSuspiciousSymbols(result.text) {
            return l(
                "Проверьте формулу: похоже, часть символов прочитана неверно (например, «×» вместо x или русские буквы вместо латинских).",
                "Check the formula: some symbols may be misread (for example “×” instead of x, or Cyrillic letters instead of Latin ones).")
        }
        return l(
            "Текст распознан неуверенно — проверьте и исправьте его перед решением.",
            "The text was recognized with low confidence — check and fix it before solving.")
    }

    private func fail(_ message: String) {
        guard !Task.isCancelled else { return }
        Haptics.error()
        errorMessage = message
        setStage(image == nil ? .review : .selecting)
    }

    /// Пользователь решил ввести условие вручную.
    func enterManually() {
        autoRecognizeTask?.cancel()
        errorMessage = nil
        setStage(.review)
    }

    // MARK: - Subject

    func chooseSubject(_ newSubject: Subject) {
        Haptics.selection()
        withAnimation(Theme.bouncy) {
            subject = newSubject
            isSubjectManual = true
        }
    }

    /// Возвращает автоматическое определение предмета.
    func resetSubjectToAutomatic() {
        isSubjectManual = false
        scheduleSubjectDetection(immediately: true)
    }

    /// Текст изменился — переопределяем предмет (с небольшой задержкой, пока пользователь печатает).
    func textDidChange() {
        guard !isSubjectManual else { return }
        scheduleSubjectDetection(immediately: false)
    }

    private func scheduleSubjectDetection(immediately: Bool) {
        detectionTask?.cancel()
        let current = text
        detectionTask = Task {
            if !immediately { try? await Task.sleep(for: .milliseconds(450)) }
            guard !Task.isCancelled else { return }
            let guess = await coordinator.detectSubject(current)
            guard !Task.isCancelled, !isSubjectManual else { return }
            withAnimation(Theme.bouncy) {
                subjectGuess = guess
                subjectGuessText = current.trimmed
                subject = guess.subject
            }
        }
    }

    // MARK: - Solving

    var canSolve: Bool {
        !text.trimmed.isEmpty || (imageForSolving != nil && coordinator.canSolveImagesRemotely)
    }

    /// Фрагмент, который увидит нейросеть: выделенная область или всё фото.
    private var imageForSolving: UIImage? {
        recognizedImage ?? image
    }

    func solve(context: ModelContext) {
        guard !isClosed, canSolve else { return }
        autoRecognizeTask?.cancel()
        errorMessage = nil
        reviewHint = nil
        connectionIssue = nil
        Haptics.press()
        solvingPhase = nil
        setStage(.solving)
        let problem = text.trimmed
        let solvingImage = imageForSolving
        // Предмет определяем заново, если его ещё не было или условие изменили после определения.
        let needsDetection = !isSubjectManual && !problem.isEmpty && (subjectGuess == nil || subjectGuessText != problem)
        detectionTask?.cancel()
        wasBackgroundedWhileSolving = false
        let backgroundID = beginBackgroundTask()

        workTask?.cancel()
        workTask = Task {
            defer { endBackgroundTask(backgroundID) }
            let started = Date()
            if needsDetection {
                let guess = await coordinator.detectSubject(problem)
                guard !Task.isCancelled, !isClosed else { return }
                subjectGuess = guess
                subjectGuessText = problem
                subject = guess.subject
            }
            let chosenSubject = subject
            let outcome = await coordinator.solve(
                text: problem, subject: chosenSubject, subjectLocked: isSubjectManual, image: solvingImage
            ) { [weak self] phase in
                guard let self, !Task.isCancelled else { return }
                withAnimation(Theme.gentle) { self.solvingPhase = phase }
            }
            guard !Task.isCancelled, !isClosed else { return }
            if !isSubjectManual { subject = outcome.subject }
            let elapsed = Date().timeIntervalSince(started)
            if elapsed < 0.3 { try? await Task.sleep(for: .milliseconds(Int((0.3 - elapsed) * 1000))) }
            guard !Task.isCancelled, !isClosed else { return }

            solution = outcome.solution
            analysis = outcome.analysis
            connectionIssue = connectionProblem(in: outcome.solution)
            // Задание без текста, оставшееся без ответа (например, отправка изображений выключена),
            // в историю не пишем: в записи не было бы ни условия, ни решения.
            if !problem.isEmpty || outcome.solution.isSolved {
                let savedText = problem.isEmpty ? HistoryPlaceholder.imageOnlyTitle(l) : problem
                await save(problem: savedText, solution: outcome.solution, context: context)
            }
            guard !Task.isCancelled, !isClosed else { return }
            if outcome.solution.isSolved {
                Haptics.success()
            } else {
                Haptics.warning()
            }
            setStage(.result)
        }
    }

    /// «Остановить» на стадии «Решаю»: возвращаемся к условию (или к выделению), фото и текст остаются.
    func stopSolving() {
        guard stage == .solving else { return }
        workTask?.cancel()
        workTask = nil
        endBackgroundTask(backgroundTaskID)
        solvingPhase = nil
        shouldAutoSolve = false
        Haptics.tap()
        if text.trimmed.isEmpty, image != nil {
            setStage(.selecting)
        } else {
            setStage(.review)
        }
    }

    /// Причина «ответа нет», если дело в связи с нейросетью, а не в самом задании.
    private func connectionProblem(in solution: Solution) -> String? {
        guard !solution.isSolved else { return nil }
        let markers = [RemoteAPIError.offline("").message(l), RemoteAPIError.timedOut.message(l)]
        if let note = solution.notes.first(where: { note in markers.contains { note.contains($0) } }) {
            return note
        }
        if wasBackgroundedWhileSolving, coordinator.canSolveImagesRemotely {
            return l(
                "Приложение было свёрнуто во время решения, и связь с нейросетью могла прерваться.",
                "The app was in the background while solving, and the connection to the AI model may have been interrupted.")
        }
        return nil
    }

    /// Вернуться к редактированию условия.
    func editProblem() {
        Haptics.tap()
        setStage(.review)
    }

    /// Вернуться к выбору области на фото.
    func reselectRegion() {
        guard image != nil else { return }
        Haptics.tap()
        errorMessage = nil
        setStage(.selecting)
    }

    // MARK: - Background time

    private func beginBackgroundTask() -> UIBackgroundTaskIdentifier {
        endBackgroundTask(backgroundTaskID)
        let identifier = UIApplication.shared.beginBackgroundTask(withName: "solve-task") { [weak self] in
            // Система вызывает обработчик на главном потоке, когда фоновое время заканчивается.
            MainActor.assumeIsolated {
                self?.backgroundTimeExpired()
            }
        }
        backgroundTaskID = identifier
        return identifier
    }

    private func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) {
        guard identifier != .invalid, identifier == backgroundTaskID else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        backgroundTaskID = .invalid
    }

    private func backgroundTimeExpired() {
        endBackgroundTask(backgroundTaskID)
    }

    // MARK: - History

    /// Следующее сохранение создаст новую запись (новый фрагмент — новое задание).
    private func detachRecord() {
        recordID = nil
        recordCreatedAt = nil
        recordProblemText = nil
        editsBelongToRecord = false
        isFavorite = false
    }

    /// Запись, которую нужно обновить, а не создавать новую:
    /// «Заново» с тем же условием, исправление текста того же фрагмента, задание из истории.
    private func recordToUpdate(for problem: String, in context: ModelContext) -> SolvedProblem? {
        guard let recordID, editsBelongToRecord || problem == recordProblemText else { return nil }
        // Запись могли удалить (например, из настроек) — тогда сохраним новую.
        return HistoryStore.record(id: recordID, in: context)
    }

    private func save(problem: String, solution: Solution, context: ModelContext) async {
        if let existing = recordToUpdate(for: problem, in: context) {
            existing.problemText = problem
            existing.update(with: solution)
            recordProblemText = problem
            reportSave(HistoryStore.save(context))
            return
        }
        var imageData: Data?
        var thumbnailData: Data?
        let source = recognizedImage ?? image
        // Фото сохраняется только при включённой настройке «Сохранять фото в истории».
        if settings.data.keepPhotosInHistory, let source {
            let boxed = UncheckedSendable(source)
            let encoded = await Task.detached(priority: .utility) {
                (ImageTools.jpegData(boxed.value, maxDimension: 1600, quality: 0.8), ImageTools.thumbnailData(boxed.value))
            }.value
            imageData = encoded.0
            thumbnailData = encoded.1
        }
        // Пока кодировалось фото, сценарий могли закрыть — отменённое задание в историю не пишем.
        guard !isClosed else { return }
        let newRecord = SolvedProblem(
            problemText: problem, solution: solution, language: settings.language, imageData: imageData, thumbnailData: thumbnailData)
        context.insert(newRecord)
        recordID = newRecord.id
        recordCreatedAt = newRecord.createdAt
        recordProblemText = problem
        isFavorite = false
        // Задание с фрагментом изображения: правка текста — исправление распознавания того же задания.
        editsBelongToRecord = source != nil
        reportSave(HistoryStore.save(context))
    }

    private func reportSave(_ succeeded: Bool) {
        if !succeeded {
            historyError = HistoryStore.saveFailedMessage(l)
        }
    }

    func toggleFavorite(context: ModelContext) {
        guard let recordID, let record = HistoryStore.record(id: recordID, in: context) else { return }
        Haptics.selection()
        withAnimation(Theme.bouncy) {
            record.isFavorite.toggle()
            isFavorite = record.isFavorite
        }
        reportSave(HistoryStore.save(context))
    }
}
