import AVFoundation
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

/// С чего начинается решение.
enum SolveInput {
    /// Изображение, уже уменьшенное до рабочего размера (`ImageTools.workingDimension`).
    case image(UIImage)
    /// Несколько страниц сканера (JPEG рабочего размера): пользователь выбирает нужную.
    /// `first` — уже раскодированная первая страница.
    case pages([Data], first: UIImage)
    /// Текст. `autoSolve == false` — сначала экран проверки (например, текст из буфера обмена).
    case text(String, subject: Subject? = nil, autoSolve: Bool = true)
    /// Задание из истории: «Решить заново» или «Изменить и решить».
    case restored(RestoredProblem)
}

/// Задание из истории, открытое заново. Результат обновляет ту же запись, а не создаёт копию.
struct RestoredProblem {
    var recordID: UUID
    /// Условие; пустое, если задание решалось только по картинке.
    var text: String
    var subject: Subject
    /// Сохранённый фрагмент изображения (JPEG), если фото хранятся в истории.
    var imageData: Data?
    /// `true` — сразу решать («Решить заново»), `false` — экран проверки («Изменить и решить»).
    var autoSolve: Bool
}

/// Экраны, на которые можно перейти из главного.
enum AppRoute: Hashable {
    case history
    case subject(Subject)
    case problem(UUID)
}

/// Полноэкранная съёмка.
enum CaptureSource: String, Identifiable {
    case camera
    case scanner

    var id: String { rawValue }
}

/// Действие, которое ждёт ответа пользователя: идёт решение, а пришло быстрое действие.
struct PendingInterruption: Identifiable {
    let id = UUID()
    let run: @MainActor () -> Void
}

/// Корневое состояние приложения: сервисы, навигация и активный сценарий решения.
@MainActor
@Observable
final class AppModel {
    let settings: AppSettings
    let coordinator: SolveCoordinator

    /// Активный сценарий решения (показывается поверх главного экрана).
    var activeFlow: SolveViewModel?
    var path: [AppRoute] = []
    var isSettingsPresented = false
    var isPhotoPickerPresented = false
    var capture: CaptureSource?
    var alertMessage: String?
    /// Нет доступа к камере — показываем объяснение и путь в Настройки.
    var isCameraAccessDeniedPresented = false
    /// После закрытия листа «Нет доступа к камере» открыть галерею.
    var opensPhotosAfterCameraSheet = false
    /// Изображение уменьшается в фоне перед показом.
    private(set) var isPreparingImage = false
    /// Быстрое действие пришло во время решения — спрашиваем, прерывать ли его.
    var pendingInterruption: PendingInterruption?
    /// Хранилище истории не открылось: работаем во временном, записи не сохранятся после перезапуска.
    var isHistoryTemporary = false

    /// Больше страниц сканера не берём: их всё равно нужно выбирать по одной.
    static let maxScanPages = 10

    var l: L10n { settings.l }

    init() {
        let settings = AppSettings()
        self.settings = settings
        coordinator = SolveCoordinator(settings: settings)
    }

    // MARK: - Solving

    func startSolve(_ input: SolveInput) {
        Haptics.press()
        let flow = SolveViewModel(input: input, settings: settings, coordinator: coordinator)
        withAnimation(Theme.spring) {
            activeFlow = flow
        }
    }

    func closeFlow() {
        activeFlow?.cancel()
        withAnimation(Theme.spring) {
            activeFlow = nil
        }
    }

    // MARK: - Image preparation

    /// Файл изображения (галерея, буфер, скриншот): декодируется сразу в уменьшенном виде, вне главного потока.
    func startSolve(imageData data: Data) {
        guard data.count <= ImageTools.maxInputBytes else {
            Haptics.warning()
            alertMessage = l("Изображение слишком большое.", "The image is too large.")
            return
        }
        prepareImage { ImageTools.downsampled(data) }
    }

    /// Уже раскодированное изображение (камера): уменьшаем и выпрямляем вне главного потока.
    func startSolve(preparing image: UIImage) {
        let boxed = UncheckedSendable(image)
        prepareImage { ImageTools.normalized(boxed.value, maxDimension: ImageTools.workingDimension) }
    }

    private func prepareImage(_ work: @escaping @Sendable () -> UIImage?) {
        isPreparingImage = true
        Task {
            let prepared = await Task.detached(priority: .userInitiated) {
                UncheckedSendable(work())
            }.value
            isPreparingImage = false
            if let image = prepared.value {
                startSolve(.image(image))
            } else {
                Haptics.error()
                alertMessage = l("Не удалось открыть изображение.", "Could not open the image.")
            }
        }
    }

    /// Страницы сканера уменьшаются и сжимаются по одной, вне главного потока:
    /// полноразмерные страницы не склеиваются и не держатся в памяти все сразу.
    func startSolve(scan: VNDocumentCameraScan) {
        let total = scan.pageCount
        let count = min(total, AppModel.maxScanPages)
        guard count > 0 else { return }
        let boxed = UncheckedSendable(scan)
        isPreparingImage = true
        Task {
            var pages: [Data] = []
            for index in 0..<count {
                let page = UncheckedSendable(boxed.value.imageOfPage(at: index))
                let data = await Task.detached(priority: .userInitiated) {
                    ImageTools.jpegData(page.value, maxDimension: ImageTools.workingDimension, quality: 0.9)
                }.value
                if let data { pages.append(data) }
            }
            let first: UIImage?
            if let firstPage = pages.first {
                first = await Task.detached(priority: .userInitiated) {
                    UncheckedSendable(ImageTools.downsampled(firstPage))
                }.value.value
            } else {
                first = nil
            }
            isPreparingImage = false
            guard let first else {
                Haptics.error()
                alertMessage = l("Не удалось обработать скан.", "Could not process the scan.")
                return
            }
            startSolve(pages.count > 1 ? .pages(pages, first: first) : .image(first))
            if total > count {
                alertMessage = l(
                    "Взяты первые \(count) страниц из \(total). Остальные отсканируйте отдельно.",
                    "Using the first \(count) of \(total) pages. Scan the rest separately.")
            }
        }
    }

    // MARK: - Input sources

    static var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func openCamera() {
        Haptics.press()
        if AppModel.isCameraAvailable {
            presentCapture(.camera)
        } else {
            alertMessage = l(
                "Камера недоступна на этом устройстве. Выберите фотографию задания из галереи.",
                "The camera is not available on this device. Choose a photo of the task from your library.")
            isPhotoPickerPresented = true
        }
    }

    func openScanner() {
        if VNDocumentCameraViewController.isSupported {
            Haptics.press()
            presentCapture(.scanner)
        } else {
            openCamera()
        }
    }

    /// Камера и сканер открываются только с разрешением; при отказе — объяснение и путь в Настройки.
    private func presentCapture(_ source: CaptureSource) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            capture = source
        case .notDetermined:
            Task {
                if await AVCaptureDevice.requestAccess(for: .video) {
                    capture = source
                } else {
                    isCameraAccessDeniedPresented = true
                }
            }
        default:
            // .denied — пользователь отказал; .restricted — ограничено Экранным временем или профилем.
            Haptics.warning()
            isCameraAccessDeniedPresented = true
        }
    }

    func openCameraSettings() {
        isCameraAccessDeniedPresented = false
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// «Выбрать из галереи» на листе отказа: галерея откроется после закрытия листа.
    func choosePhotoInsteadOfCamera() {
        opensPhotosAfterCameraSheet = true
        isCameraAccessDeniedPresented = false
    }

    func cameraSheetDidDismiss() {
        guard opensPhotosAfterCameraSheet else { return }
        opensPhotosAfterCameraSheet = false
        openPhotos()
    }

    func openPhotos() {
        Haptics.tap()
        isPhotoPickerPresented = true
    }

    func pasteFromClipboard() {
        Haptics.tap()
        let pasteboard = UIPasteboard.general
        if pasteboard.hasImages {
            if let data = AppModel.imageData(from: pasteboard) {
                startSolve(imageData: data)
            } else if let image = pasteboard.image {
                startSolve(preparing: image)
            } else {
                Haptics.warning()
                alertMessage = l("Не удалось прочитать изображение из буфера обмена.", "Could not read the image from the clipboard.")
            }
        } else if pasteboard.hasStrings, let text = pasteboard.string, !text.trimmed.isEmpty {
            // В буфере может оказаться пароль или код из SMS — сначала показываем текст, без автоотправки.
            startSolve(.text(text, autoSolve: false))
        } else {
            Haptics.warning()
            alertMessage = l(
                "В буфере обмена нет изображения или текста. Скопируйте скриншот или текст задания и попробуйте снова.",
                "The clipboard has no image or text. Copy a screenshot or the task text and try again.")
        }
    }

    /// Файл изображения из буфера — без полного декодирования на главном потоке.
    private static func imageData(from pasteboard: UIPasteboard) -> Data? {
        for type in pasteboard.types {
            guard let uti = UTType(type), uti.conforms(to: .image) else { continue }
            if let data = pasteboard.data(forPasteboardType: type), !data.isEmpty {
                return data
            }
        }
        return nil
    }

    func typeTask(subject: Subject? = nil) {
        startSolve(.text("", subject: subject))
    }

    // MARK: - Quick actions (Action Button, Shortcuts, Controls)

    /// Забирает отложенное быстрое действие, если интент его оставил.
    func handlePendingQuickAction() {
        if let screenshot = ScreenshotInbox.consume() {
            // Скриншот новее любого отложенного действия — оно больше не нужно.
            _ = QuickActionInbox.consume()
            dismissPresentations { [weak self] in
                self?.startSolve(imageData: screenshot)
            }
            return
        }
        guard let action = QuickActionInbox.consume() else { return }
        perform(action)
    }

    func perform(_ action: QuickAction) {
        // Убираем всё, что открыто, чтобы действие сработало с любого экрана.
        dismissPresentations { [weak self] in
            guard let self else { return }
            switch action {
            case .camera: self.openCamera()
            case .scan: self.openScanner()
            case .photos: self.openPhotos()
            case .clipboard: self.pasteFromClipboard()
            case .type: self.typeTask()
            }
        }
    }

    /// Ответ на вопрос «Прервать текущее решение?».
    func resolveInterruption(startNew: Bool) {
        guard let pending = pendingInterruption else { return }
        pendingInterruption = nil
        if startNew { pending.run() }
    }

    /// Закрывает всё открытое и выполняет действие, когда окна успели закрыться.
    /// Идущее решение молча не отменяется: сначала спрашиваем пользователя.
    private func dismissPresentations(then run: @escaping @MainActor () -> Void) {
        if let flow = activeFlow, flow.isBusy {
            pendingInterruption = PendingInterruption { [weak self] in
                self?.dismissPresentationsNow(then: run)
            }
            return
        }
        dismissPresentationsNow(then: run)
    }

    private func dismissPresentationsNow(then run: @escaping @MainActor () -> Void) {
        let hadPresentation = activeFlow != nil || isSettingsPresented || capture != nil || isPhotoPickerPresented
            || isCameraAccessDeniedPresented
        if activeFlow != nil { closeFlow() }
        isSettingsPresented = false
        capture = nil
        isPhotoPickerPresented = false
        isCameraAccessDeniedPresented = false
        opensPhotosAfterCameraSheet = false
        path = []
        if hadPresentation {
            // Даём закрыться текущему окну, иначе новое не покажется.
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                run()
            }
        } else {
            run()
        }
    }
}
