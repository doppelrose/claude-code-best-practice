import SwiftUI
import UIKit
import VisionKit

/// Системная камера.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage) -> Void
        let onCancel: () -> Void

        init(onImage: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onImage = onImage
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            } else {
                onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}

/// Сканер документов VisionKit: находит лист, выравнивает перспективу и повышает контраст —
/// идеально для страниц учебника и тетради.
///
/// Страницы не склеиваются: скан целиком передаётся в `onScan`, а страницы уменьшаются по одной
/// вне главного потока (`AppModel.startSolve(scan:)`), и пользователь выбирает нужную.
struct DocumentScanner: UIViewControllerRepresentable {
    let onScan: (VNDocumentCameraScan) -> Void
    let onCancel: () -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onCancel: onCancel, onError: onError)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject {
        let onScan: (VNDocumentCameraScan) -> Void
        let onCancel: () -> Void
        let onError: (String) -> Void

        init(
            onScan: @escaping (VNDocumentCameraScan) -> Void, onCancel: @escaping () -> Void,
            onError: @escaping (String) -> Void
        ) {
            self.onScan = onScan
            self.onCancel = onCancel
            self.onError = onError
        }
    }
}

extension DocumentScanner.Coordinator: @preconcurrency VNDocumentCameraViewControllerDelegate {
    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
        guard scan.pageCount > 0 else {
            onCancel()
            return
        }
        onScan(scan)
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        onCancel()
    }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
        onError(error.localizedDescription)
    }
}

// MARK: - Camera access

/// Нет доступа к камере: объясняем, как его включить, и предлагаем галерею.
struct CameraAccessDeniedView: View {
    let l: L10n
    let onOpenSettings: () -> Void
    let onChoosePhoto: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Spacer()
                GlassIconButton(systemImage: "xmark", accessibilityLabel: l("Закрыть", "Close"), action: onClose)
            }
            CardIcon(systemImage: "camera.fill")
            Text(l("Нет доступа к камере", "No camera access"))
                .font(.headlineTitle)
                .foregroundStyle(Palette.ink)
            Text(
                l(
                    "Чтобы фотографировать задания, разрешите AI Homework доступ к камере: Настройки → AI Homework → Камера. Можно также выбрать готовое фото из галереи.",
                    "To photograph tasks, allow AI Homework to use the camera: Settings → AI Homework → Camera. You can also choose an existing photo from your library."))
                .font(.callout)
                .foregroundStyle(Palette.inkSubtle)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            PrimaryButton(title: l("Открыть Настройки", "Open Settings"), systemImage: "gearshape", action: onOpenSettings)
            GlassButton(title: l("Выбрать из галереи", "Choose from library"), systemImage: "photo.on.rectangle", action: onChoosePhoto)
        }
        .padding(Theme.screenPadding)
        .background(Palette.canvas.ignoresSafeArea())
    }
}
