import SwiftData
import SwiftUI

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

    // Условие
    var text: String
    private(set) var subject: Subject = .other
    private(set) var subjectGuess: SubjectGuess?
    private(set) var isSubjectManual = false

    // Результат
    private(set) var solution: Solution?
    private(set) var analysis: TextAnalysis?
    private(set) var record: SolvedProblem?
    var errorMessage: String?

    private let settings: AppSettings
    private let coordinator: SolveCoordinator
    private var workTask: Task<Void, Never>?
    private var detectionTask: Task<Void, Never>?
    private var shouldAutoSolve = false

    var l: L10n { settings.l }
    var hasImage: Bool { image != nil }
    var isFavorite: Bool { record?.isFavorite ?? false }

    init(input: SolveInput, settings: AppSettings, coordinator: SolveCoordinator) {
        self.settings = settings
        self.coordinator = coordinator
        switch input {
        case .image(let picked):
            image = picked
            text = ""
            stage = .selecting
        case .text(let value, let presetSubject):
            text = value
            // Условие уже введено пользователем — сразу решаем (см. `consumeAutoSolve`).
            stage = value.trimmed.isEmpty ? .review : .solving
            shouldAutoSolve = !value.trimmed.isEmpty
            if let presetSubject {
                subject = presetSubject
                isSubjectManual = true
            }
        }
    }

    /// Нужно ли запустить решение сразу после появления экрана (для введённого текста).
    func consumeAutoSolve() -> Bool {
        defer { shouldAutoSolve = false }
        return shouldAutoSolve
    }

    /// Вызывается при появлении экрана.
    func onAppear() {
        if let image, image.imageOrientation != .up || max(image.size.width, image.size.height) > 2600 {
            // Нормализуем ориентацию и размер один раз.
            let boxed = UncheckedSendable(image)
            Task {
                let normalized = await Task.detached(priority: .userInitiated) {
                    UncheckedSendable(ImageTools.normalized(boxed.value))
                }.value
                self.image = normalized.value
            }
        }
        if stage == .review, !text.trimmed.isEmpty, !isSubjectManual {
            scheduleSubjectDetection(immediately: true)
        }
    }

    func cancel() {
        workTask?.cancel()
        detectionTask?.cancel()
    }

    private func setStage(_ newStage: Stage) {
        withAnimation(Theme.spring) {
            stage = newStage
        }
    }

    // MARK: - Recognition

    /// Распознаёт текст на всём изображении или в выделенной области.
    func recognize(useSelection: Bool) {
        guard let image else { return }
        errorMessage = nil
        Haptics.press()
        setStage(.recognizing)
        let region = useSelection ? selection : nil
        let boxed = UncheckedSendable(image)

        workTask?.cancel()
        workTask = Task {
            let started = Date()
            let prepared = await Task.detached(priority: .userInitiated) { () -> UncheckedSendable<UIImage> in
                let base = ImageTools.normalized(boxed.value)
                if let region, let cropped = ImageTools.crop(base, to: region) {
                    return UncheckedSendable(cropped)
                }
                return UncheckedSendable(base)
            }.value
            recognizedImage = prepared.value

            guard let cgImage = prepared.value.cgImage else {
                fail(OCRError.failed("no bitmap").message(l))
                return
            }
            do {
                let result = try await OCRService.recognize(UncheckedSendable(cgImage))
                guard !Task.isCancelled else { return }
                // Анимация сканирования не должна мелькать, если распознавание заняло доли секунды.
                let elapsed = Date().timeIntervalSince(started)
                if elapsed < 0.9 { try? await Task.sleep(for: .milliseconds(Int((0.9 - elapsed) * 1000))) }
                guard !Task.isCancelled else { return }

                text = result.text
                recognizedLines = result.lines
                ocrConfidence = result.averageConfidence
                usedMathPass = result.usedMathPass
                isSubjectManual = false
                let guess = await coordinator.detectSubject(result.text)
                guard !Task.isCancelled else { return }
                subjectGuess = guess
                subject = guess.subject
                Haptics.success()
                setStage(.review)
            } catch let error as OCRError {
                fail(error.message(l))
            } catch {
                fail(OCRError.failed(error.localizedDescription).message(l))
            }
        }
    }

    private func fail(_ message: String) {
        guard !Task.isCancelled else { return }
        Haptics.error()
        errorMessage = message
        setStage(image == nil ? .review : .selecting)
    }

    /// Пользователь решил ввести условие вручную.
    func enterManually() {
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
                subject = guess.subject
            }
        }
    }

    // MARK: - Solving

    var canSolve: Bool {
        !text.trimmed.isEmpty
    }

    func solve(context: ModelContext) {
        guard canSolve else { return }
        errorMessage = nil
        Haptics.press()
        setStage(.solving)
        let problem = text.trimmed
        let needsDetection = !isSubjectManual && subjectGuess == nil
        detectionTask?.cancel()

        workTask?.cancel()
        workTask = Task {
            let started = Date()
            if needsDetection {
                // Текст введён вручную — предмет ещё не определялся.
                let guess = await coordinator.detectSubject(problem)
                guard !Task.isCancelled else { return }
                subjectGuess = guess
                subject = guess.subject
            }
            let chosenSubject = subject
            let outcome = await coordinator.solve(text: problem, subject: chosenSubject)
            guard !Task.isCancelled else { return }
            let elapsed = Date().timeIntervalSince(started)
            if elapsed < 0.8 { try? await Task.sleep(for: .milliseconds(Int((0.8 - elapsed) * 1000))) }
            guard !Task.isCancelled else { return }

            solution = outcome.solution
            analysis = outcome.analysis
            await save(problem: problem, solution: outcome.solution, context: context)
            if outcome.solution.isSolved {
                Haptics.success()
            } else {
                Haptics.warning()
            }
            setStage(.result)
        }
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
        setStage(.selecting)
    }

    // MARK: - History

    private func save(problem: String, solution: Solution, context: ModelContext) async {
        if let record {
            record.problemText = problem
            record.update(with: solution)
            try? context.save()
            return
        }
        var imageData: Data?
        var thumbnailData: Data?
        if settings.data.keepPhotosInHistory, let source = recognizedImage ?? image {
            let boxed = UncheckedSendable(source)
            let encoded = await Task.detached(priority: .utility) {
                (ImageTools.jpegData(boxed.value, maxDimension: 1600, quality: 0.8), ImageTools.thumbnailData(boxed.value))
            }.value
            imageData = encoded.0
            thumbnailData = encoded.1
        }
        let newRecord = SolvedProblem(
            problemText: problem, solution: solution, language: settings.language, imageData: imageData, thumbnailData: thumbnailData)
        context.insert(newRecord)
        try? context.save()
        record = newRecord
    }

    func toggleFavorite(context: ModelContext) {
        guard let record else { return }
        Haptics.selection()
        withAnimation(Theme.bouncy) {
            record.isFavorite.toggle()
        }
        try? context.save()
    }
}
