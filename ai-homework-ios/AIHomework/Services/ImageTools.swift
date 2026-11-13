import UIKit

/// Обёртка для передачи значения между изоляциями, когда его потокобезопасность
/// гарантируется способом использования (объект больше нигде не меняется).
struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

/// Подготовка изображений: нормализация ориентации, уменьшение, обрезка, миниатюры.
/// Все операции безопасно выполняются вне главного потока.
enum ImageTools {
    /// Приводит ориентацию к `.up` и ограничивает длинную сторону — для OCR этого достаточно,
    /// а память и время обработки сокращаются в разы.
    static func normalized(_ image: UIImage, maxDimension: CGFloat = 2600) -> UIImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        if scale == 1, image.imageOrientation == .up, image.scale == 1 {
            return image
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: target))
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// Обрезка по прямоугольнику в нормированных координатах (0…1, начало — левый верхний угол).
    static func crop(_ image: UIImage, to normalizedRect: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let rect = CGRect(
            x: normalizedRect.minX * width, y: normalizedRect.minY * height,
            width: normalizedRect.width * width, height: normalizedRect.height * height
        ).integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard rect.width >= 8, rect.height >= 8, let cropped = cgImage.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped, scale: 1, orientation: .up)
    }

    static func jpegData(_ image: UIImage, maxDimension: CGFloat, quality: CGFloat) -> Data? {
        normalized(image, maxDimension: maxDimension).jpegData(compressionQuality: quality)
    }

    /// Небольшая миниатюра для списков истории.
    static func thumbnailData(_ image: UIImage) -> Data? {
        jpegData(image, maxDimension: 360, quality: 0.7)
    }
}
