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
    ///
    /// Отмена задачи прерывает распознавание (`VNRequest.cancel()`) и бросает `CancellationError`.
    static func recognize(_ image: UncheckedSendable<CGImage>) async throws -> OCRResult {
        let first = try await perform(image, languageCorrection: true)
        guard !first.lines.isEmpty else { throw OCRError.noText }
        if mathDensity(first.text) >= 0.18 {
            try Task.checkCancellation()
            do {
                let second = try await perform(image, languageCorrection: false)
                if !second.lines.isEmpty {
                    var result = second
                    result.usedMathPass = true
                    return result
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Второй проход не удался — остаётся результат первого.
            }
        }
        return first
    }

    // MARK: - Нужна ли проверка текста

    /// Ниже этой средней уверенности распознанный текст показывается на проверку перед решением.
    static let reviewConfidenceThreshold = 0.6

    /// Показывать ли распознанный текст на проверку, прежде чем решать.
    /// Решение владельца: только при низкой уверенности или подозрительных символах, иначе решаем сразу.
    static func needsReview(_ result: OCRResult) -> Bool {
        result.averageConfidence < reviewConfidenceThreshold || hasSuspiciousSymbols(result.text)
    }

    /// Признаки типичных ошибок распознавания формул:
    /// знак `×` (часто это прочитанная буква x) и смешение кириллицы с латиницей рядом с цифрами
    /// и знаками действий в одной строке (`2x + 3у = 7`, где «у» — русская).
    static func hasSuspiciousSymbols(_ text: String) -> Bool {
        if text.contains("×") { return true }
        let mathNeighbors: Set<Character> = ["=", "+", "-", "−", "–", "^", "/", "*", "·", "<", ">", "²", "³"]
        func isMath(_ character: Character?) -> Bool {
            guard let character else { return false }
            return character.isNumber || mathNeighbors.contains(character)
        }
        for line in text.split(whereSeparator: \.isNewline) {
            let characters = Array(line)
            var hasLatin = false
            var hasCyrillic = false
            for index in characters.indices where characters[index].isLetter {
                let previous = index > characters.startIndex ? characters[index - 1] : nil
                let next = index + 1 < characters.endIndex ? characters[index + 1] : nil
                guard isMath(previous) || isMath(next), let scalar = characters[index].unicodeScalars.first else { continue }
                switch scalar.value {
                case 0x41...0x5A, 0x61...0x7A: hasLatin = true
                case 0x0400...0x04FF: hasCyrillic = true
                default: break
                }
            }
            if hasLatin, hasCyrillic { return true }
        }
        return false
    }

    /// Доля цифр и математических знаков среди непробельных символов.
    static func mathDensity(_ text: String) -> Double {
        let symbols = text.filter { !$0.isWhitespace }
        guard !symbols.isEmpty else { return 0 }
        let math = symbols.filter { $0.isNumber || "+-−–=*/^()<>√·×÷:%²³".contains($0) }
        return Double(math.count) / Double(symbols.count)
    }

    private static func perform(_ boxed: UncheckedSendable<CGImage>, languageCorrection: Bool) async throws -> OCRResult {
        try Task.checkCancellation()
        let cancellation = RequestCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.usesLanguageCorrection = languageCorrection
                    request.recognitionLanguages = ["ru-RU", "en-US"]
                    request.minimumTextHeight = 0.008
                    guard cancellation.attach(request) else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    let handler = VNImageRequestHandler(cgImage: boxed.value, orientation: .up, options: [:])
                    do {
                        try handler.perform([request])
                        if cancellation.isCancelled {
                            continuation.resume(throwing: CancellationError())
                        } else {
                            let observations = request.results ?? []
                            continuation.resume(returning: assemble(observations))
                        }
                    } catch {
                        if cancellation.isCancelled {
                            continuation.resume(throwing: CancellationError())
                        } else {
                            continuation.resume(throwing: OCRError.failed(error.localizedDescription))
                        }
                    }
                }
            }
        } onCancel: {
            cancellation.cancel()
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

/// Связь отмены задачи с запросом Vision, который выполняется в другой очереди.
private final class RequestCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var request: VNRequest?
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    /// Запоминает запрос; `false` — задача уже отменена и запускать его не нужно.
    func attach(_ request: VNRequest) -> Bool {
        lock.withLock {
            self.request = request
            return !cancelled
        }
    }

    func cancel() {
        let pending: VNRequest? = lock.withLock {
            cancelled = true
            return request
        }
        pending?.cancel()
    }
}
