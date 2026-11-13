import SwiftUI
import VisionKit

/// С чего начинается решение.
enum SolveInput {
    case image(UIImage)
    case text(String, subject: Subject? = nil)
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

/// Корневое состояние приложения: сервисы, навигация и активный сценарий решения.
@MainActor
@Observable
final class AppModel {
    let settings: AppSettings
    let modelStore: CoreMLModelStore
    let coordinator: SolveCoordinator

    /// Активный сценарий решения (показывается поверх главного экрана).
    var activeFlow: SolveViewModel?
    var path: [AppRoute] = []
    var isSettingsPresented = false
    var isPhotoPickerPresented = false
    var capture: CaptureSource?
    var alertMessage: String?

    var l: L10n { settings.l }

    init() {
        let settings = AppSettings()
        let modelStore = CoreMLModelStore()
        self.settings = settings
        self.modelStore = modelStore
        coordinator = SolveCoordinator(settings: settings, modelStore: modelStore)
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

    // MARK: - Input sources

    static var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func openCamera() {
        Haptics.press()
        if AppModel.isCameraAvailable {
            capture = .camera
        } else {
            alertMessage = l(
                "Камера недоступна на этом устройстве. Выберите фотографию задания из галереи.",
                "The camera is not available on this device. Choose a photo of the task from your library.")
            isPhotoPickerPresented = true
        }
    }

    func openScanner() {
        Haptics.press()
        if VNDocumentCameraViewController.isSupported {
            capture = .scanner
        } else {
            openCamera()
        }
    }

    func openPhotos() {
        Haptics.tap()
        isPhotoPickerPresented = true
    }

    func pasteFromClipboard() {
        Haptics.tap()
        let pasteboard = UIPasteboard.general
        if pasteboard.hasImages, let image = pasteboard.image {
            startSolve(.image(image))
        } else if pasteboard.hasStrings, let text = pasteboard.string, !text.trimmed.isEmpty {
            startSolve(.text(text))
        } else {
            Haptics.warning()
            alertMessage = l(
                "В буфере обмена нет изображения или текста. Скопируйте скриншот или текст задания и попробуйте снова.",
                "The clipboard has no image or text. Copy a screenshot or the task text and try again.")
        }
    }

    func typeTask(subject: Subject? = nil) {
        startSolve(.text("", subject: subject))
    }

    // MARK: - Quick actions (Action Button, Shortcuts, Controls)

    /// Забирает отложенное быстрое действие, если интент его оставил.
    func handlePendingQuickAction() {
        guard let action = QuickActionInbox.consume() else { return }
        perform(action)
    }

    func perform(_ action: QuickAction) {
        // Убираем всё, что открыто, чтобы действие сработало с любого экрана.
        let hadPresentation = activeFlow != nil || isSettingsPresented || capture != nil || isPhotoPickerPresented
        if activeFlow != nil { closeFlow() }
        isSettingsPresented = false
        capture = nil
        isPhotoPickerPresented = false
        path = []

        let run: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            switch action {
            case .camera: self.openCamera()
            case .scan: self.openScanner()
            case .photos: self.openPhotos()
            case .clipboard: self.pasteFromClipboard()
            case .type: self.typeTask()
            }
        }
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
