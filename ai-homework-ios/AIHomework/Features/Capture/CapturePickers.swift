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
struct DocumentScanner: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject {
        let onImage: (UIImage) -> Void
        let onCancel: () -> Void

        init(onImage: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onImage = onImage
            self.onCancel = onCancel
        }
    }
}

extension DocumentScanner.Coordinator: @preconcurrency VNDocumentCameraViewControllerDelegate {
    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
        guard scan.pageCount > 0 else {
            onCancel()
            return
        }
        // Несколько страниц склеиваем по вертикали, чтобы задание не потерялось.
        let pages = (0..<min(scan.pageCount, 4)).map { scan.imageOfPage(at: $0) }
        onImage(DocumentScanner.stack(pages))
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        onCancel()
    }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
        onCancel()
    }
}

extension DocumentScanner {
    static func stack(_ pages: [UIImage]) -> UIImage {
        guard pages.count > 1 else { return pages.first ?? UIImage() }
        let width = pages.map { $0.size.width }.max() ?? 1
        let scaled = pages.map { page -> (UIImage, CGSize) in
            let factor = width / max(page.size.width, 1)
            return (page, CGSize(width: width, height: page.size.height * factor))
        }
        let height = scaled.reduce(0) { $0 + $1.1.height }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { _ in
            var y: CGFloat = 0
            for (page, size) in scaled {
                page.draw(in: CGRect(x: 0, y: y, width: size.width, height: size.height))
                y += size.height
            }
        }
    }
}
