import CoreML
import Foundation

/// Запуск пользовательской языковой модели Core ML на устройстве.
///
/// Контракт модели (описан в README):
/// - вход `input_ids` (или `inputIds`) — Int32, форма `[1, N]`; необязательный `attention_mask`;
/// - выход `logits` — форма `[1, N, V]` или `[1, V]`;
/// - рядом лежит `tokenizer.json` (байтовый BPE) и, по желанию, `manifest.json`.
///
/// Модель вызывается заново на каждом токене (без кэша ключей/значений): это медленнее,
/// чем специализированные рантаймы, зато работает с обычными экспортами и не требует библиотек.
actor CoreMLTextGenerator {
    static let inputNames = ["input_ids", "inputIds"]
    private static let maskNames = ["attention_mask", "attentionMask"]
    private static let outputNames = ["logits", "token_scores", "output_logits"]
    private static let defaultStopTokens = ["<|endoftext|>", "<|im_end|>", "</s>", "<|eot_id|>", "<eos>", "<end_of_turn>", "<|end|>"]

    private let model: MLModel
    private let tokenizer: BPETokenizer
    private let manifest: ModelManifest
    private let inputName: String
    private let maskName: String?
    private let outputName: String
    /// Фиксированная длина входа, если модель экспортирована без гибкой формы.
    private let fixedLength: Int?
    private let maxLength: Int
    private let stopIDs: Set<Int>

    init(folder: URL) throws {
        let tokenizerURL = folder.appendingPathComponent(CoreMLModelStore.tokenizerFileName)
        guard let tokenizerData = try? Data(contentsOf: tokenizerURL) else {
            throw LanguageModelError.unavailable("tokenizer.json is missing")
        }
        do {
            tokenizer = try BPETokenizer(json: tokenizerData)
        } catch {
            throw LanguageModelError.unavailable("tokenizer.json is not a supported byte-level BPE tokenizer")
        }
        if let data = try? Data(contentsOf: folder.appendingPathComponent(CoreMLModelStore.manifestFileName)),
            let decoded = try? JSONDecoder().decode(ModelManifest.self, from: data)
        {
            manifest = decoded
        } else {
            manifest = ModelManifest()
        }

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        do {
            model = try MLModel(contentsOf: folder.appendingPathComponent(CoreMLModelStore.modelFileName), configuration: configuration)
        } catch {
            throw LanguageModelError.unavailable(error.localizedDescription)
        }

        let description = model.modelDescription
        let inputs = description.inputDescriptionsByName
        guard let input = CoreMLTextGenerator.inputNames.first(where: { inputs[$0] != nil }) else {
            throw LanguageModelError.unavailable("the model has no input_ids input")
        }
        inputName = input
        maskName = CoreMLTextGenerator.maskNames.first { inputs[$0] != nil }
        let outputs = description.outputDescriptionsByName
        guard let output = CoreMLTextGenerator.outputNames.first(where: { outputs[$0] != nil })
            ?? outputs.first(where: { $0.value.type == .multiArray })?.key
        else {
            throw LanguageModelError.unavailable("the model has no logits output")
        }
        outputName = output

        // Допустимая длина последовательности.
        var fixed: Int?
        var maximum = manifest.contextLength ?? 512
        if let constraint = inputs[input]?.multiArrayConstraint {
            let declared = constraint.shape.last?.intValue ?? 0
            switch constraint.shapeConstraint.type {
            case .range:
                if let range = constraint.shapeConstraint.sizeRangeForDimension.last?.rangeValue {
                    let upper = range.location + range.length
                    if upper > 0, upper < 1_000_000 { maximum = min(maximum, upper) }
                }
            case .enumerated:
                let lengths = constraint.shapeConstraint.enumeratedShapes.compactMap { $0.last?.intValue }
                if let largest = lengths.max() {
                    fixed = largest
                    maximum = largest
                }
            default:
                if declared > 1 {
                    fixed = declared
                    maximum = declared
                }
            }
        }
        fixedLength = fixed
        maxLength = max(maximum, 8)

        var stops = Set<Int>()
        for token in manifest.stopTokens ?? CoreMLTextGenerator.defaultStopTokens {
            if let id = tokenizer.tokenID(for: token) { stops.insert(id) }
        }
        stopIDs = stops
    }

    func generate(instructions: String, prompt: String, maxTokens: Int) throws -> String {
        let template = manifest.promptTemplate ?? "{system}\n\n{prompt}\n\n"
        let text = template.replacingOccurrences(of: "{system}", with: instructions).replacingOccurrences(of: "{prompt}", with: prompt)
        var tokens = tokenizer.encode(text)
        guard !tokens.isEmpty else { throw LanguageModelError.generationFailed("empty prompt") }

        let budget = max(8, min(maxTokens, maxLength / 2))
        if tokens.count > maxLength - budget {
            // Контекст не помещается — оставляем конец запроса (там само задание).
            tokens = Array(tokens.suffix(max(1, maxLength - budget)))
        }

        var generated: [Int] = []
        let temperature = manifest.temperature ?? 0.3
        for _ in 0..<budget {
            if Task.isCancelled { throw LanguageModelError.cancelled }
            guard tokens.count < maxLength else { break }
            let logits = try nextTokenLogits(tokens)
            let next = CoreMLTextGenerator.sample(logits, temperature: temperature)
            if stopIDs.contains(next) { break }
            tokens.append(next)
            generated.append(next)
        }
        let result = tokenizer.decode(generated).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw LanguageModelError.generationFailed("the model produced no text") }
        return result
    }

    private func nextTokenLogits(_ tokens: [Int]) throws -> [Float] {
        let length = fixedLength ?? tokens.count
        let shape = [NSNumber(value: 1), NSNumber(value: length)]
        do {
            let ids = try MLMultiArray(shape: shape, dataType: .int32)
            let mask = try MLMultiArray(shape: shape, dataType: .int32)
            for index in 0..<length {
                let isReal = index < tokens.count
                ids[index] = NSNumber(value: Int32(isReal ? tokens[index] : 0))
                mask[index] = NSNumber(value: Int32(isReal ? 1 : 0))
            }
            var features: [String: MLFeatureValue] = [inputName: MLFeatureValue(multiArray: ids)]
            if let maskName { features[maskName] = MLFeatureValue(multiArray: mask) }
            let output = try model.prediction(from: try MLDictionaryFeatureProvider(dictionary: features))
            guard let logits = output.featureValue(for: outputName)?.multiArrayValue else {
                throw LanguageModelError.generationFailed("no logits in the model output")
            }
            return try CoreMLTextGenerator.row(of: logits, position: min(tokens.count, length) - 1)
        } catch let error as LanguageModelError {
            throw error
        } catch {
            throw LanguageModelError.generationFailed(error.localizedDescription)
        }
    }

    /// Строка логитов для заданной позиции последовательности.
    private static func row(of logits: MLMultiArray, position: Int) throws -> [Float] {
        let shape = logits.shape.map { $0.intValue }
        guard let vocabulary = shape.last, vocabulary > 0 else {
            throw LanguageModelError.generationFailed("unexpected logits shape")
        }
        // [1, N, V] → позиция N; [1, V] → единственная строка.
        let sequenceLength = shape.count >= 3 ? shape[shape.count - 2] : 1
        let rowIndex = sequenceLength > 1 ? min(position, sequenceLength - 1) : 0
        let offset = rowIndex * vocabulary
        guard offset + vocabulary <= logits.count else {
            throw LanguageModelError.generationFailed("unexpected logits shape")
        }
        if logits.dataType == .float32 {
            return logits.withUnsafeBufferPointer(ofType: Float.self) { buffer in
                Array(buffer[offset..<(offset + vocabulary)])
            }
        }
        return (0..<vocabulary).map { logits[offset + $0].floatValue }
    }

    /// Выбор следующего токена: top-k с температурой; при нулевой температуре — максимум.
    private static func sample(_ logits: [Float], temperature: Double, topK: Int = 40) -> Int {
        guard let best = logits.indices.max(by: { logits[$0] < logits[$1] }) else { return 0 }
        guard temperature > 0.01 else { return best }
        let candidates = logits.indices.sorted { logits[$0] > logits[$1] }.prefix(topK)
        let maximum = Double(logits[best])
        let weights = candidates.map { exp((Double(logits[$0]) - maximum) / temperature) }
        let total = weights.reduce(0, +)
        guard total.isFinite, total > 0 else { return best }
        var threshold = Double.random(in: 0..<total)
        for (index, weight) in zip(candidates, weights) {
            threshold -= weight
            if threshold <= 0 { return index }
        }
        return best
    }
}

/// Загруженные модели держим в памяти: повторная загрузка занимает секунды.
actor CoreMLGeneratorCache {
    static let shared = CoreMLGeneratorCache()
    private var generators: [String: CoreMLTextGenerator] = [:]

    func generator(for modelID: String) throws -> CoreMLTextGenerator {
        if let cached = generators[modelID] { return cached }
        let generator = try CoreMLTextGenerator(folder: CoreMLModelStore.folder(forID: modelID))
        // Одновременно в памяти — только одна модель.
        generators = [modelID: generator]
        return generator
    }

    func evict(_ modelID: String) {
        generators[modelID] = nil
    }
}

/// Провайдер для пользовательской модели Core ML.
struct CoreMLModelProvider: LanguageModelProvider {
    let model: InstalledModel
    let engine = SolutionEngine.coreML

    func displayName(_ l: L10n) -> String {
        model.name
    }

    func availability(_ l: L10n) async -> ModelAvailability {
        switch model.kind {
        case .textGenerator where model.hasTokenizer:
            return ModelAvailability(
                isAvailable: true,
                title: l("Готова к работе", "Ready"),
                detail: l(
                    "Пользовательская модель Core ML. Качество и скорость ответов зависят от самой модели.",
                    "A user-supplied Core ML model. Answer quality and speed depend on the model itself."))
        case .textGenerator:
            return ModelAvailability(
                isAvailable: false,
                title: l("Нет токенизатора", "Tokenizer missing"),
                detail: l(
                    "Рядом с моделью должен лежать файл tokenizer.json. Импортируйте папку, в которой есть и модель, и токенизатор.",
                    "A tokenizer.json file must be next to the model. Import a folder that contains both the model and the tokenizer."))
        case .subjectClassifier:
            return ModelAvailability(
                isAvailable: false,
                title: l("Классификатор предметов", "Subject classifier"),
                detail: l(
                    "Эта модель определяет предмет задания, но не генерирует ответы.",
                    "This model detects the subject of a task but does not generate answers."))
        case .unsupported:
            return ModelAvailability(
                isAvailable: false,
                title: l("Формат не поддерживается", "Unsupported format"),
                detail: l(
                    "У модели нет входа input_ids и выхода logits (или это модель с состоянием). Приложение не может использовать её для решения заданий.",
                    "The model has no input_ids input and logits output (or it is a stateful model). The app cannot use it to solve tasks."))
        }
    }

    func generate(instructions: String, prompt: String, maxTokens: Int) async throws -> String {
        let generator: CoreMLTextGenerator
        do {
            generator = try await CoreMLGeneratorCache.shared.generator(for: model.id)
        } catch let error as LanguageModelError {
            throw error
        } catch {
            throw LanguageModelError.unavailable(error.localizedDescription)
        }
        return try await generator.generate(instructions: instructions, prompt: prompt, maxTokens: maxTokens)
    }
}
