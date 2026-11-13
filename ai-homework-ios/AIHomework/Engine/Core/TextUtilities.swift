import Foundation

/// Небольшие обёртки над `NSRegularExpression` (работают и на iOS, и на Linux).
enum Rx {
    /// Все совпадения: для каждого — массив групп (нулевая — совпадение целиком, пустая строка — если группа не участвовала).
    static func matches(_ pattern: String, in text: String, caseInsensitive: Bool = true) -> [[String]] {
        ranges(pattern, in: text, caseInsensitive: caseInsensitive).map { match in
            match.map { range in range.map { String(text[$0]) } ?? "" }
        }
    }

    static func first(_ pattern: String, in text: String, caseInsensitive: Bool = true) -> [String]? {
        matches(pattern, in: text, caseInsensitive: caseInsensitive).first
    }

    static func contains(_ pattern: String, in text: String, caseInsensitive: Bool = true) -> Bool {
        !ranges(pattern, in: text, caseInsensitive: caseInsensitive).isEmpty
    }

    /// Совпадения с диапазонами групп в исходной строке.
    static func ranges(_ pattern: String, in text: String, caseInsensitive: Bool = true) -> [[Range<String.Index>?]] {
        let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: nsRange).map { result in
            (0..<result.numberOfRanges).map { index in
                Range(result.range(at: index), in: text)
            }
        }
    }

    static func replace(_ pattern: String, in text: String, with template: String, caseInsensitive: Bool = true) -> String {
        let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return text }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: nsRange, withTemplate: template)
    }
}

extension String {
    /// Есть ли в строке хотя бы одна из подстрок (обычно — основ слов).
    func containsAny(_ needles: [String]) -> Bool {
        needles.contains { self.contains($0) }
    }

    var hasCyrillic: Bool {
        unicodeScalars.contains { $0.value >= 0x400 && $0.value <= 0x4FF }
    }

    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Character {
    var isCyrillic: Bool {
        unicodeScalars.allSatisfy { $0.value >= 0x400 && $0.value <= 0x4FF }
    }

    var isLatinLetter: Bool {
        isLetter && isASCII
    }
}
