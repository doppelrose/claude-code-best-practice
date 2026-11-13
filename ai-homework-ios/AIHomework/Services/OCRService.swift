import CoreGraphics
import Foundation
import Vision

/// Строка распознанного текста.
struct RecognizedLine: Sendable, Hashable, Identifiable {
    var id = UUID()
    var text: String
    var confidence: Float
    /// Рамка в нормированных координатах изображения (начало — левый верхний угол).
    var boundingBox: CGRect
}

/// Результат распознавания.
struct OCRResult: Sendable {
    var text: String
    var lines: [RecognizedLine]
    /// Средняя уверенность распознавания, 0…1.
    var averageConfidence: Double
    /// Использовался ли проход без языковой коррекции (для формул).
    var usedMathPass: Bool
}

enum OCRError: Error, Sendable {
    case noText
    case failed(String)

    func message(_ l: L10n) -> String {
        switch self {
        case .noText:
            return l(
                "На изображении не найден текст. Попробуйте сфотографировать задание ближе и при хорошем освещении.",
                "No text was found in the image. Try taking the photo closer and in good light.")
        case .failed(let detail):
            return l("Не удалось распознать текст: \(detail)", "Text recognition failed: \(detail)")
        }
    }
}

/// Распознавание текста средствами Apple Vision — полностью на устройстве.
enum OCRService {
    /// Распознаёт текст на изображении.
    ///
    /// Сначала выполняется обычный проход с языковой коррекцией. Если текст похож на формулы,
    /// выполняется второй проход без коррекции: «исправление» слов портит математическую запись
    /// (например, превращает `x` в русское «х», а `2x+5` — в «слово»).
    static func recognize(_ image: UncheckedSendable<CGImage>) async throws -> OCRResult {
        let first = try await perform(image, languageCorrection: true)
        guard !first.lines.isEmpty else { throw OCRError.noText }
        if mathDensity(first.text) >= 0.18 {
            if let second = try? await perform(image, languageCorrection: false), !second.lines.isEmpty {
                var result = second
                result.usedMathPass = true
                return result
            }
        }
        return first
    }

    /// Доля цифр и математических знаков среди непробельных символов.
    static func mathDensity(_ text: String) -> Double {
        let symbols = text.filter { !$0.isWhitespace }
        guard !symbols.isEmpty else { return 0 }
        let math = symbols.filter { $0.isNumber || "+-−–=*/^()<>√·×÷:%²³".contains($0) }
        return Double(math.count) / Double(symbols.count)
    }

    private static func perform(_ boxed: UncheckedSendable<CGImage>, languageCorrection: Bool) async throws -> OCRResult {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = languageCorrection
                request.recognitionLanguages = ["ru-RU", "en-US"]
                request.minimumTextHeight = 0.008
                let handler = VNImageRequestHandler(cgImage: boxed.value, orientation: .up, options: [:])
                do {
                    try handler.perform([request])
                    let observations = request.results ?? []
                    continuation.resume(returning: assemble(observations))
                } catch {
                    continuation.resume(throwing: OCRError.failed(error.localizedDescription))
                }
            }
        }
    }

    /// Собирает строки в естественном порядке чтения: сверху вниз, слева направо.
    private static func assemble(_ observations: [VNRecognizedTextObservation]) -> OCRResult {
        var lines: [RecognizedLine] = []
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            // Vision отсчитывает координаты от левого нижнего угла.
            let box = observation.boundingBox
            let flipped = CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
            lines.append(RecognizedLine(text: text, confidence: candidate.confidence, boundingBox: flipped))
        }

        // Группируем фрагменты, лежащие на одной строке.
        let sorted = lines.sorted { $0.boundingBox.midY < $1.boundingBox.midY }
        var rows: [[RecognizedLine]] = []
        for line in sorted {
            if let last = rows.last, let reference = last.first,
                abs(reference.boundingBox.midY - line.boundingBox.midY) < max(reference.boundingBox.height, line.boundingBox.height) * 0.55
            {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        let ordered = rows.map { $0.sorted { $0.boundingBox.minX < $1.boundingBox.minX } }
        let text = ordered.map { row in row.map { $0.text }.joined(separator: " ") }.joined(separator: "\n")
        let flat = ordered.flatMap { $0 }
        let average = flat.isEmpty ? 0 : Double(flat.reduce(0) { $0 + $1.confidence }) / Double(flat.count)
        return OCRResult(text: text, lines: flat, averageConfidence: average, usedMathPass: false)
    }
}
