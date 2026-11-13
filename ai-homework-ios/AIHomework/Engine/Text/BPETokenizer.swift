import Foundation

/// Байтовый BPE-токенизатор в формате `tokenizer.json` (Hugging Face Tokenizers):
/// его используют GPT-2, Qwen, Llama 3 и многие другие модели.
///
/// Нужен для запуска пользовательских языковых моделей Core ML без сторонних библиотек.
struct BPETokenizer: Sendable {
    enum TokenizerError: Error, Equatable {
        case invalidFile
        case unsupportedModel(String)
    }

    private let vocabulary: [String: Int]
    private let reverseVocabulary: [Int: String]
    private let mergeRanks: [String: Int]
    /// Служебные токены (`<|im_start|>`, `</s>`) — от длинных к коротким.
    private let addedTokens: [(content: String, id: Int)]
    private let specialIDs: Set<Int>
    private let splitPattern: String

    /// Разбиение на «слова» перед BPE, как в GPT-2.
    private static let defaultPattern = "'s|'t|'re|'ve|'m|'ll|'d| ?\\p{L}+| ?\\p{N}+| ?[^\\s\\p{L}\\p{N}]+|\\s+(?!\\S)|\\s+"

    /// Соответствие «байт ↔ печатный символ» из GPT-2.
    private static let byteEncoder: [UInt8: Character] = {
        var printable: [Int] = Array(33...126) + Array(161...172) + Array(174...255)
        var mapped = printable
        var extra = 0
        for byte in 0..<256 where !printable.contains(byte) {
            printable.append(byte)
            mapped.append(256 + extra)
            extra += 1
        }
        var result: [UInt8: Character] = [:]
        for (byte, scalarValue) in zip(printable, mapped) {
            if let scalar = Unicode.Scalar(scalarValue) {
                result[UInt8(byte)] = Character(scalar)
            }
        }
        return result
    }()

    private static let byteDecoder: [Character: UInt8] = {
        var result: [Character: UInt8] = [:]
        for (byte, character) in byteEncoder { result[character] = byte }
        return result
    }()

    var vocabularySize: Int { reverseVocabulary.count }

    func tokenID(for token: String) -> Int? {
        vocabulary[token] ?? addedTokens.first { $0.content == token }?.id
    }

    init(json data: Data) throws {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let model = root["model"] as? [String: Any]
        else { throw TokenizerError.invalidFile }
        if let type = model["type"] as? String, type != "BPE" {
            throw TokenizerError.unsupportedModel(type)
        }
        guard let rawVocabulary = model["vocab"] as? [String: Any] else { throw TokenizerError.invalidFile }

        var vocabulary: [String: Int] = [:]
        vocabulary.reserveCapacity(rawVocabulary.count)
        for (token, value) in rawVocabulary {
            if let id = value as? Int { vocabulary[token] = id }
        }

        // Слияния бывают записаны как «a b» или как ["a", "b"].
        var ranks: [String: Int] = [:]
        if let merges = model["merges"] as? [Any] {
            ranks.reserveCapacity(merges.count)
            for (rank, entry) in merges.enumerated() {
                if let text = entry as? String {
                    ranks[text] = rank
                } else if let pair = entry as? [String], pair.count == 2 {
                    ranks[pair[0] + " " + pair[1]] = rank
                }
            }
        }

        var added: [(content: String, id: Int)] = []
        var special = Set<Int>()
        if let list = root["added_tokens"] as? [[String: Any]] {
            for entry in list {
                guard let content = entry["content"] as? String, let id = entry["id"] as? Int else { continue }
                added.append((content, id))
                if (entry["special"] as? Bool) ?? true { special.insert(id) }
            }
        }
        added.sort { $0.content.count > $1.content.count }

        var reverse: [Int: String] = [:]
        reverse.reserveCapacity(vocabulary.count + added.count)
        for (token, id) in vocabulary { reverse[id] = token }
        for token in added where reverse[token.id] == nil { reverse[token.id] = token.content }

        self.vocabulary = vocabulary
        reverseVocabulary = reverse
        mergeRanks = ranks
        addedTokens = added
        specialIDs = special
        splitPattern = BPETokenizer.findSplitPattern(root["pre_tokenizer"]) ?? BPETokenizer.defaultPattern
    }

    /// Регулярное выражение из `pre_tokenizer` (у Qwen и Llama 3 оно своё).
    private static func findSplitPattern(_ node: Any?) -> String? {
        guard let dictionary = node as? [String: Any] else { return nil }
        if dictionary["type"] as? String == "Split", let pattern = dictionary["pattern"] as? [String: Any],
            let regex = pattern["Regex"] as? String, (try? NSRegularExpression(pattern: regex)) != nil
        {
            return regex
        }
        if let children = dictionary["pretokenizers"] as? [Any] {
            for child in children {
                if let found = findSplitPattern(child) { return found }
            }
        }
        return nil
    }

    // MARK: - Encoding

    func encode(_ text: String) -> [Int] {
        var result: [Int] = []
        for segment in splitOnAddedTokens(text) {
            if let id = segment.id {
                result.append(id)
                continue
            }
            for word in Rx.matches(splitPattern, in: segment.text, caseInsensitive: false) {
                result.append(contentsOf: encodeWord(word[0]))
            }
        }
        return result
    }

    private func splitOnAddedTokens(_ text: String) -> [(text: String, id: Int?)] {
        guard !addedTokens.isEmpty else { return [(text, nil)] }
        var segments: [(text: String, id: Int?)] = []
        var buffer = ""
        var index = text.startIndex
        while index < text.endIndex {
            var matched = false
            if text[index] == "<" || text[index] == "[" {
                for token in addedTokens where text[index...].hasPrefix(token.content) {
                    if !buffer.isEmpty {
                        segments.append((buffer, nil))
                        buffer = ""
                    }
                    segments.append((token.content, token.id))
                    index = text.index(index, offsetBy: token.content.count)
                    matched = true
                    break
                }
            }
            if !matched {
                buffer.append(text[index])
                index = text.index(after: index)
            }
        }
        if !buffer.isEmpty { segments.append((buffer, nil)) }
        return segments
    }

    private func encodeWord(_ word: String) -> [Int] {
        var symbols: [String] = word.utf8.compactMap { byte in BPETokenizer.byteEncoder[byte].map { String($0) } }
        guard !symbols.isEmpty else { return [] }

        // Повторяем: находим пару с наименьшим рангом и сливаем все её вхождения.
        while symbols.count > 1 {
            var bestRank = Int.max
            var bestIndex = -1
            for i in 0..<(symbols.count - 1) {
                if let rank = mergeRanks[symbols[i] + " " + symbols[i + 1]], rank < bestRank {
                    bestRank = rank
                    bestIndex = i
                }
            }
            guard bestIndex >= 0 else { break }
            let first = symbols[bestIndex]
            let second = symbols[bestIndex + 1]
            var merged: [String] = []
            merged.reserveCapacity(symbols.count)
            var i = 0
            while i < symbols.count {
                if i < symbols.count - 1, symbols[i] == first, symbols[i + 1] == second {
                    merged.append(first + second)
                    i += 2
                } else {
                    merged.append(symbols[i])
                    i += 1
                }
            }
            symbols = merged
        }

        var ids: [Int] = []
        for symbol in symbols {
            if let id = vocabulary[symbol] {
                ids.append(id)
            } else {
                // Неизвестная последовательность — раскладываем на отдельные символы словаря.
                for character in symbol {
                    if let id = vocabulary[String(character)] { ids.append(id) }
                }
            }
        }
        return ids
    }

    // MARK: - Decoding

    func decode(_ ids: [Int], skipSpecialTokens: Bool = true) -> String {
        var bytes: [UInt8] = []
        for id in ids {
            guard let token = reverseVocabulary[id] else { continue }
            if specialIDs.contains(id) {
                if !skipSpecialTokens { bytes.append(contentsOf: Array(token.utf8)) }
                continue
            }
            for character in token {
                if let byte = BPETokenizer.byteDecoder[character] {
                    bytes.append(byte)
                } else {
                    bytes.append(contentsOf: Array(String(character).utf8))
                }
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    func isSpecial(_ id: Int) -> Bool {
        specialIDs.contains(id)
    }
}
