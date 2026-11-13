import Foundation

/// Выделяет математические фрагменты из текста задания: «Решите уравнение: 2х + 5 = 11.» → `2x + 5 = 11`.
///
/// Распознанный камерой текст — это смесь слов и формул, причём OCR часто подменяет
/// латинские переменные похожими кириллическими буквами. Экстрактор отделяет слова от формул
/// и приводит формулы к виду, понятному парсеру.
enum MathTextExtractor {
    private static let functionNames = [
        "arcsin", "arccos", "arctg", "arcctg", "arctan", "arccot", "asin", "acos", "atan",
        "sqrt", "cbrt", "sin", "cos", "tan", "ctg", "cot", "tg", "ln", "lg", "log", "abs", "exp", "pi",
    ]

    /// Двухбуквенные английские слова, которые нельзя принимать за произведение переменных.
    private static let shortEnglishWords: Set<String> = [
        "is", "of", "to", "in", "if", "at", "by", "an", "or", "as", "be", "do", "it", "we", "so", "on", "no", "up",
        "my", "me", "he", "us", "am", "go",
    ]

    private static let operatorCharacters = Set("+-*/^=<>≤≥≠()|√∛%°!²³⁴⁵⁶⁷⁸⁹⁰¹_")
    private static let mathVariableLookalikes: Set<Character> = ["х", "Х", "у", "У"]

    static func fragments(in text: String) -> [String] {
        var normalized = MathNormalizer.normalize(text)
        // Двоеточие между числами/скобками, отделённое пробелами, — знак деления: «(3,5 + 1,5) : 2».
        normalized = Rx.replace("(?<=[0-9)²³])\\s+:\\s+(?=[0-9(√a-zA-Zху])", in: normalized, with: " / ")
        let russianContext = normalized.hasCyrillic
        var fragments: [String] = []

        // Разделители утверждений: перевод строки, «;», запятая с пробелом.
        var pieces: [String] = []
        for line in normalized.components(separatedBy: .newlines) {
            for part in line.components(separatedBy: ";") {
                pieces.append(contentsOf: splitOnListCommas(part))
            }
        }

        for piece in pieces {
            let cleaned = stripNumbering(piece)
            var current: [String] = []
            func flush() {
                if !current.isEmpty {
                    fragments.append(current.joined(separator: " "))
                    current = []
                }
            }
            for rawToken in cleaned.split(whereSeparator: { $0 == " " }) {
                let token = stripPunctuation(String(rawToken))
                guard !token.isEmpty else {
                    flush()
                    continue
                }
                if isMathToken(token, russianContext: russianContext) {
                    current.append(MathNormalizer.latinizeLookalikes(token))
                } else {
                    flush()
                }
                // Точка или двоеточие в конце слова завершают фрагмент.
                if let last = rawToken.last, ".?!:".contains(last) {
                    flush()
                }
            }
            flush()
        }

        return fragments.compactMap { tidy($0) }
    }

    /// Запятая с пробелом разделяет утверждения, а запятая между цифрами — десятичный разделитель.
    private static func splitOnListCommas(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        let chars = Array(text)
        for (index, c) in chars.enumerated() {
            if c == "(" { depth += 1 }
            if c == ")" { depth = max(0, depth - 1) }
            if c == ",", depth == 0, index + 1 < chars.count, chars[index + 1] == " " {
                parts.append(current)
                current = ""
            } else {
                current.append(c)
            }
        }
        parts.append(current)
        return parts
    }

    /// Убираем нумерацию заданий: «5)», «№ 12.», «a)».
    private static func stripNumbering(_ text: String) -> String {
        var result = Rx.replace("^\\s*(№\\s*)?\\d+\\s*[\\.\\)]\\s+", in: text, with: "")
        result = Rx.replace("^\\s*[a-zа-я]\\)\\s+", in: result, with: "")
        return result
    }

    private static func stripPunctuation(_ token: String) -> String {
        var result = Substring(token)
        while let first = result.first, "«\"'“”„:".contains(first) { result = result.dropFirst() }
        while let last = result.last, ".,?:;»\"“”„".contains(last) { result = result.dropLast() }
        // «= ?» → «=»
        if result == "?" { return "" }
        return String(result)
    }

    private static func isMathToken(_ token: String, russianContext: Bool) -> Bool {
        let hasDigit = token.contains { $0.isNumber }
        let hasOperator = token.contains { operatorCharacters.contains($0) }
        let cyrillic = token.filter { $0.isCyrillic }
        let latin = token.filter { $0.isLatinLetter }

        if !cyrillic.isEmpty {
            // Кириллица допустима только как «двойник» латинской переменной.
            let latinized = MathNormalizer.latinizeLookalikes(token)
            guard !latinized.hasCyrillic else { return false }
            if hasDigit || hasOperator { return cyrillic.count <= 3 }
            return token.count == 1 && mathVariableLookalikes.contains(token.first ?? " ")
        }

        if hasDigit || hasOperator {
            // Буквенная часть не должна быть обычным словом: «5th», «2nd» и т.п.
            let letterRuns = token.split(whereSeparator: { !$0.isLetter }).map { String($0).lowercased() }
            return letterRuns.allSatisfy { isMathWord($0, russianContext: russianContext, standalone: false) }
        }

        guard !latin.isEmpty, latin.count == token.count else {
            // Греческие буквы и символы вроде π.
            return token.allSatisfy { $0.isLetter && !$0.isASCII && !$0.isCyrillic } && token.count <= 2
        }
        return isMathWord(token.lowercased(), russianContext: russianContext, standalone: true)
    }

    private static func isMathWord(_ word: String, russianContext: Bool, standalone: Bool) -> Bool {
        if word.count == 1 { return true }
        if functionNames.contains(word) { return true }
        // Функция со «слипшимся» аргументом: sinx, cos2x, lnx.
        for name in functionNames where word.hasPrefix(name) && word.count - name.count <= 2 {
            return true
        }
        if word.count == 2 { return !shortEnglishWords.contains(word) || !standalone }
        if !standalone { return word.count <= 4 }
        // В русском тексте короткое латинское «слово» — почти наверняка произведение переменных (abc, xyz).
        return russianContext && word.count <= 4
    }

    /// Финальная чистка фрагмента. `nil` — если в нём нет ничего математического.
    private static func tidy(_ fragment: String) -> String? {
        var text = fragment.trimmed
        // Хвостовые «=» и «= ?» — просьба вычислить.
        while text.hasSuffix("=") || text.hasSuffix("?") {
            text = String(text.dropLast()).trimmed
        }
        text = balanceParentheses(text)
        guard !text.isEmpty else { return nil }
        let hasContent = text.contains { $0.isNumber || $0.isLetter }
        return hasContent ? text : nil
    }

    /// Убираем непарные скобки по краям (фигурная скобка системы уравнений и т.п.).
    private static func balanceParentheses(_ text: String) -> String {
        var chars = Array(text)
        var changed = true
        while changed {
            changed = false
            var depth = 0
            var minDepth = 0
            for c in chars {
                if c == "(" { depth += 1 }
                if c == ")" { depth -= 1 }
                minDepth = min(minDepth, depth)
            }
            if depth > 0, let index = chars.firstIndex(of: "(") {
                chars.remove(at: index)
                changed = true
            } else if minDepth < 0, let index = chars.lastIndex(of: ")") {
                chars.remove(at: index)
                changed = true
            }
        }
        return String(chars).trimmed
    }
}
