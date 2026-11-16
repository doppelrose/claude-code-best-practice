import Foundation

enum MathToken: Equatable, Sendable {
    case number(Rational)
    case real(Double)
    case ident(String)
    case function(MathFn)
    case constant(MathConst)
    /// Основание логарифма, записанное индексом: `log₂`, `log_2`.
    case logBase(Rational)
    /// Экспонента `exp(...)` — разбирается как `e^(...)`.
    case exp
    case op(Character)
    case lparen
    case rparen
    case comma
    case bar
    case degree

    var displayText: String {
        switch self {
        case .number(let r): return r.description
        case .real(let d): return "\(d)"
        case .ident(let name): return name
        case .function(let f): return f.displayName
        case .constant(let c): return c.symbol
        case .logBase(let r): return "_\(r.description)"
        case .exp: return "exp"
        case .op(let c): return String(c)
        case .lparen: return "("
        case .rparen: return ")"
        case .comma: return ","
        case .bar: return "|"
        case .degree: return "°"
        }
    }
}

/// Приведение «человеческой» и распознанной камерой записи к единому виду.
enum MathNormalizer {
    private static let replacements: [(String, String)] = [
        ("<=", "≤"), (">=", "≥"), ("=<", "≤"), ("=>", "≥"), ("!=", "≠"), ("<>", "≠"), ("==", "="),
        ("⩽", "≤"), ("⩾", "≥"), ("≦", "≤"), ("≧", "≥"),
        ("**", "^"),
        ("·", "*"), ("⋅", "*"), ("∙", "*"), ("•", "*"), ("✕", "*"), ("∗", "*"),
        ("÷", ":"), ("∕", "/"), ("⁄", "/"),
        ("−", "-"), ("–", "-"), ("—", "-"), ("‒", "-"), ("﹣", "-"), ("－", "-"),
        ("＋", "+"), ("＝", "="),
        ("［", "("), ("］", ")"), ("[", "("), ("]", ")"), ("{", "("), ("}", ")"),
        ("\u{00A0}", " "), ("\u{2009}", " "), ("\u{202F}", " "), ("\t", " "),
        ("½", "(1/2)"), ("⅓", "(1/3)"), ("¼", "(1/4)"), ("¾", "(3/4)"), ("⅔", "(2/3)"), ("⅕", "(1/5)"),
    ]

    /// Кириллические буквы, которые OCR часто подставляет вместо латинских переменных.
    static let cyrillicLookalikes: [Character: Character] = [
        "х": "x", "Х": "x", "у": "y", "У": "y", "а": "a", "с": "c", "е": "e",
        "к": "k", "м": "m", "р": "p", "т": "t", "в": "b", "п": "n",
    ]

    static func normalize(_ text: String) -> String {
        var result = resolveTimesSign(text)
        for (from, to) in replacements {
            result = result.replacingOccurrences(of: from, with: to)
        }
        return result
    }

    /// Распознавание текста часто читает латинскую `x` как знак умножения `×`.
    /// «×» считается умножением, только если стоит между двумя операндами (`2 × 3`, `a × (b + 1)`);
    /// иначе это переменная: `×^2 − 5×`, `×² + 1`, `3×`.
    ///
    /// Знаки в строке решаются вместе (AUD-12): если хотя бы один «×» — заведомо переменная,
    /// то и «×» вплотную между коэффициентом и цифрой (`2×2`) — это переменная с потерянной
    /// степенью: `2×2 − 5× + 2 = 0` — это `2x² − 5x + 2 = 0`, а не `4 − 5x + 2 = 0`.
    static func resolveTimesSign(_ text: String) -> String {
        guard text.contains("×") else { return text }
        let chars = Array(text)
        func isOperandEnd(_ ch: Character?) -> Bool {
            guard let ch else { return false }
            return ch.isNumber || ch.isLetter || ch == ")" || ch == "²" || ch == "³"
        }
        func isOperandStart(_ ch: Character?) -> Bool {
            guard let ch else { return false }
            return ch.isNumber || ch.isLetter || ch == "(" || ch == "√"
        }
        // true — умножение, false — переменная.
        var decisions: [Int: Bool] = [:]
        var tightBeforeDigit: Set<Int> = []
        for (index, c) in chars.enumerated() where c == "×" {
            var left = index - 1
            while left >= 0, chars[left] == " " { left -= 1 }
            var right = index + 1
            while right < chars.count, chars[right] == " " { right += 1 }
            let previous: Character? = left >= 0 ? chars[left] : nil
            let next: Character? = right < chars.count ? chars[right] : nil
            decisions[index] = isOperandEnd(previous) && isOperandStart(next)
            if left == index - 1, right == index + 1, let previous, let next, previous.isNumber || previous.isLetter,
                next.isASCII, next.isNumber
            {
                tightBeforeDigit.insert(index)
            }
        }
        if decisions.values.contains(false) {
            for index in tightBeforeDigit { decisions[index] = false }
        }
        var result = ""
        for (index, c) in chars.enumerated() {
            if let multiplication = decisions[index] {
                result.append(multiplication ? "*" : "x")
            } else {
                result.append(c)
            }
        }
        return result
    }

    /// Прочитан ли хотя бы один «×» как переменная — это исправление OCR, о нём нужно предупредить.
    static func readsTimesAsVariable(_ text: String) -> Bool {
        guard text.contains("×") else { return false }
        let resolved = Array(resolveTimesSign(text))
        let original = Array(text)
        guard resolved.count == original.count else { return true }
        return zip(original, resolved).contains { $0 == "×" && $1 == "x" }
    }

    /// Индексы переменных (AUD-63): если в записи есть и `x1`, и `x2`, это `x₁` и `x₂`, а не `x` и `x²`.
    static func subscriptIndexedVariables(_ text: String) -> String {
        guard text.contains(where: { $0.isASCII && $0.isNumber }) else { return text }
        let pattern = "(?<![A-Za-z])([A-Za-z])([1-9])(?![0-9]|[.,][0-9])"
        var digitsByLetter: [String: Set<String>] = [:]
        for match in Rx.matches(pattern, in: text, caseInsensitive: false) {
            digitsByLetter[match[1], default: []].insert(match[2])
        }
        let indexed = digitsByLetter.filter { $0.value.contains("1") && $0.value.count >= 2 }.map(\.key)
        guard !indexed.isEmpty else { return text }
        var result = text
        let subscripts: [String: String] = ["1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉"]
        for letter in indexed {
            for (digit, sub) in subscripts {
                result = Rx.replace(
                    "(?<![A-Za-z])\(letter)\(digit)(?![0-9]|[.,][0-9])", in: result, with: letter + sub, caseInsensitive: false)
            }
        }
        return result
    }

    /// Замена кириллических «двойников» латиницей — применяется только к уже выделенному
    /// математическому фрагменту, не к обычному тексту.
    static func latinizeLookalikes(_ text: String) -> String {
        String(text.map { cyrillicLookalikes[$0] ?? $0 })
    }
}

/// Лексер математической записи.
struct MathLexer {
    private let chars: [Character]
    private var pos = 0
    private(set) var tokens: [MathToken] = []
    /// Была ли применена эвристика «x2 → x²» или «(x+1)2 → (x+1)²» (типичная ошибка распознавания степени).
    private(set) var assumedPowers = false
    /// Было ли «1 1/2» прочитано как смешанное число.
    private(set) var mixedNumbers = false

    private static let superscripts: [Character: Character] = [
        "⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9",
    ]
    private static let subscripts: [Character: Character] = [
        "₀": "0", "₁": "1", "₂": "2", "₃": "3", "₄": "4", "₅": "5", "₆": "6", "₇": "7", "₈": "8", "₉": "9",
    ]

    /// Имена функций и констант, от длинных к коротким (жадное сопоставление).
    private static let words: [(String, MathToken)] = [
        ("arcsin", .function(.asin)), ("arccos", .function(.acos)), ("arcctg", .function(.acot)),
        ("arccot", .function(.acot)), ("arctan", .function(.atan)), ("arctg", .function(.atan)),
        ("asin", .function(.asin)), ("acos", .function(.acos)), ("atan", .function(.atan)),
        ("sqrt", .function(.sqrt)), ("cbrt", .function(.cbrt)),
        ("sin", .function(.sin)), ("cos", .function(.cos)), ("tan", .function(.tan)),
        ("ctg", .function(.cot)), ("cot", .function(.cot)),
        ("abs", .function(.abs)), ("exp", .exp), ("log", .function(.log)),
        ("tg", .function(.tan)), ("ln", .function(.ln)), ("lg", .function(.lg)),
        ("pi", .constant(.pi)),
    ]

    init(_ text: String) {
        chars = Array(MathNormalizer.normalize(text))
    }

    mutating func tokenize() throws -> [MathToken] {
        tokens = []
        pos = 0
        while pos < chars.count {
            let c = chars[pos]
            if c == " " || c == "\n" || c == "\r" {
                pos += 1
            } else if c.isASCII, c.isNumber {
                try readNumber()
            } else if (c == "." || c == ","), pos + 1 < chars.count, chars[pos + 1].isASCII, chars[pos + 1].isNumber,
                !lastTokenIsValue
            {
                // Запись вида ".5"
                try readNumber()
            } else if let digit = MathLexer.superscripts[c] {
                readSuperscript(first: digit)
            } else if c == "⁻", pos + 1 < chars.count, MathLexer.superscripts[chars[pos + 1]] != nil {
                pos += 1
                let digit = MathLexer.superscripts[chars[pos]] ?? "1"
                readSuperscript(first: digit, negative: true)
            } else if isLetter(c) {
                try readWord()
            } else {
                try readSymbol(c)
            }
        }
        return tokens
    }

    private var lastTokenIsValue: Bool {
        switch tokens.last {
        case .number, .real, .ident, .constant, .rparen: return true
        default: return false
        }
    }

    private func isLetter(_ c: Character) -> Bool {
        guard c.isLetter else { return false }
        // Латиница и греческие буквы. Кириллица к этому моменту уже должна быть
        // либо отброшена как текст, либо заменена латинскими «двойниками».
        return c.unicodeScalars.allSatisfy { scalar in
            (scalar.value < 0x250) || (scalar.value >= 0x370 && scalar.value < 0x400)
        }
    }

    private mutating func readNumber() throws {
        let start = pos
        // «(x+1)2» → «(x+1)²»: цифра вплотную после скобки — потерянная при распознавании степень.
        let afterParenthesis = start > 0 && chars[start - 1] == ")" && tokens.last == .rparen
        var text = ""
        while pos < chars.count, chars[pos].isASCII, chars[pos].isNumber {
            text.append(chars[pos])
            pos += 1
        }
        if afterParenthesis, text.count == 1, let digit = Int(text), digit >= 2, !followsDecimal(at: pos) {
            tokens.append(.op("^"))
            tokens.append(.number(Rational(digit)))
            assumedPowers = true
            return
        }
        // Смешанное число «1 1/2» (AUD-57): целое, пробел, правильная дробь.
        if let mixed = readMixedFraction(whole: text) {
            tokens.append(.number(mixed))
            mixedNumbers = true
            return
        }
        // Разделитель тысяч пробелом: «1 500», «12 000 000» (две записи подряд иначе — ошибка).
        if text.count <= 3 {
            while let group = thousandsGroup(at: pos) {
                text += group
                pos += 4
            }
        }
        // Десятичный разделитель: точка или запятая, сразу за которой идёт цифра.
        if pos + 1 < chars.count, chars[pos] == "." || chars[pos] == ",", chars[pos + 1].isASCII, chars[pos + 1].isNumber {
            text.append(".")
            pos += 1
            while pos < chars.count, chars[pos].isASCII, chars[pos].isNumber {
                text.append(chars[pos])
                pos += 1
            }
        }
        if let rational = Rational(decimal: text) {
            tokens.append(.number(rational))
        } else if let value = Double(text), value.isFinite {
            tokens.append(.real(value))
        } else {
            throw MathError.syntax(detail: text)
        }
    }

    private func isDigit(_ index: Int) -> Bool {
        index < chars.count && chars[index].isASCII && chars[index].isNumber
    }

    /// Идёт ли на позиции `index` продолжение числа: цифра или десятичная часть.
    private func followsDecimal(at index: Int) -> Bool {
        if isDigit(index) { return true }
        return index + 1 < chars.count && (chars[index] == "." || chars[index] == ",") && isDigit(index + 1)
    }

    /// « 500» после «1»: ровно три цифры, а за ними не цифра, не дробь и не десятичная часть.
    private func thousandsGroup(at index: Int) -> String? {
        guard index < chars.count, chars[index] == " ", isDigit(index + 1), isDigit(index + 2), isDigit(index + 3) else { return nil }
        let after = index + 4
        if isDigit(after) { return nil }
        if after < chars.count, chars[after] == "/" || chars[after] == ":" { return nil }
        guard lastTokenAllowsNumberGroup else { return nil }
        return String(chars[(index + 1)...(index + 3)])
    }

    /// Группы тысяч и смешанные числа не склеиваем после «/», «^» и «:» — там пробел значим.
    private var lastTokenAllowsNumberGroup: Bool {
        switch tokens.last {
        case .op(let c)?: return c != "/" && c != "^" && c != ":"
        case .logBase?: return false
        default: return true
        }
    }

    /// «1 1/2»: после целого пробел, числитель, «/», знаменатель; дробь правильная и на этом заканчивается.
    private mutating func readMixedFraction(whole: String) -> Rational? {
        guard lastTokenAllowsNumberGroup, pos < chars.count, chars[pos] == " ", let wholeValue = Int(whole) else { return nil }
        var index = pos + 1
        var numerator = ""
        while isDigit(index) {
            numerator.append(chars[index])
            index += 1
        }
        guard !numerator.isEmpty, index < chars.count, chars[index] == "/" else { return nil }
        index += 1
        var denominator = ""
        while isDigit(index) {
            denominator.append(chars[index])
            index += 1
        }
        guard !denominator.isEmpty, numerator.count <= 6, denominator.count <= 6 else { return nil }
        if index < chars.count {
            let next = chars[index]
            if next.isLetter || next == "(" || next == "^" || next == "." || next == "," || MathLexer.superscripts[next] != nil {
                return nil
            }
        }
        guard let top = Int(numerator), let bottom = Int(denominator), bottom > 0, top < bottom,
            let fraction = try? Rational(top, bottom), let value = try? Rational(wholeValue) + fraction
        else { return nil }
        pos = index
        return value
    }

    private mutating func readSuperscript(first: Character, negative: Bool = false) {
        var digits = String(first)
        pos += 1
        while pos < chars.count, let digit = MathLexer.superscripts[chars[pos]] {
            digits.append(digit)
            pos += 1
        }
        tokens.append(.op("^"))
        let value = Int(digits) ?? 1
        if negative {
            tokens.append(.lparen)
            tokens.append(.op("-"))
            tokens.append(.number(Rational(value)))
            tokens.append(.rparen)
        } else {
            tokens.append(.number(Rational(value)))
        }
    }

    private mutating func readWord() throws {
        var run: [Character] = []
        while pos < chars.count, isLetter(chars[pos]) {
            run.append(chars[pos])
            pos += 1
        }
        let lower = run.map { Character($0.lowercased()) }
        var index = 0
        while index < run.count {
            var matched = false
            for (word, token) in MathLexer.words {
                let wordChars = Array(word)
                if index + wordChars.count <= lower.count, Array(lower[index..<(index + wordChars.count)]) == wordChars {
                    tokens.append(token)
                    index += wordChars.count
                    matched = true
                    break
                }
            }
            if matched { continue }
            let c = run[index]
            index += 1
            switch c {
            case "π": tokens.append(.constant(.pi))
            case "e": tokens.append(.constant(.e))
            default: tokens.append(.ident(String(c)))
            }
        }
        readTrailingIndex()
    }

    /// То, что идёт сразу за буквой: индекс (`x₁`), основание логарифма (`log₂`, `log_2`)
    /// или «прилипшая» цифра степени (`x2` вместо `x²`).
    private mutating func readTrailingIndex() {
        guard pos < chars.count, let last = tokens.last else { return }

        if last == .function(.log) {
            var digits = ""
            if chars[pos] == "_" {
                var probe = pos + 1
                while probe < chars.count, chars[probe].isASCII, chars[probe].isNumber {
                    digits.append(chars[probe])
                    probe += 1
                }
                if !digits.isEmpty { pos = probe }
            } else if chars[pos].isASCII, chars[pos].isNumber {
                // «log2(8)»: цифры вплотную к имени и сразу за ними скобка — это основание.
                var probe = pos
                var candidate = ""
                while probe < chars.count, chars[probe].isASCII, chars[probe].isNumber {
                    candidate.append(chars[probe])
                    probe += 1
                }
                if probe < chars.count, chars[probe] == "(" {
                    digits = candidate
                    pos = probe
                }
            } else {
                while pos < chars.count, let digit = MathLexer.subscripts[chars[pos]] {
                    digits.append(digit)
                    pos += 1
                }
            }
            if let base = Int(digits) {
                tokens.append(.logBase(Rational(base)))
            }
            return
        }

        guard case .ident(let name) = last else { return }

        if MathLexer.subscripts[chars[pos]] != nil {
            var indexed = name
            while pos < chars.count, MathLexer.subscripts[chars[pos]] != nil {
                indexed.append(chars[pos])
                pos += 1
            }
            tokens[tokens.count - 1] = .ident(indexed)
            return
        }

        // «x2» → «x²»: одиночная цифра 2…9 сразу после переменной.
        let c = chars[pos]
        if c.isASCII, c.isNumber, let digit = c.wholeNumberValue, digit >= 2 {
            let nextIsDigit = pos + 1 < chars.count && chars[pos + 1].isASCII && chars[pos + 1].isNumber
            let nextIsDecimal =
                pos + 2 < chars.count && (chars[pos + 1] == "." || chars[pos + 1] == ",")
                && chars[pos + 2].isASCII && chars[pos + 2].isNumber
            if !nextIsDigit, !nextIsDecimal {
                pos += 1
                tokens.append(.op("^"))
                tokens.append(.number(Rational(digit)))
                assumedPowers = true
            }
        }
    }

    private mutating func readSymbol(_ c: Character) throws {
        pos += 1
        switch c {
        case "+", "-", "*", "/", "^", "!", "%":
            tokens.append(.op(c))
        case ":", "∶":
            tokens.append(.op(":"))
        case "(":
            tokens.append(.lparen)
        case ")":
            tokens.append(.rparen)
        case ",", ";":
            tokens.append(.comma)
        case "|":
            tokens.append(.bar)
        case "°", "º", "˚":
            tokens.append(.degree)
        case "√":
            tokens.append(.function(.sqrt))
        case "∛":
            tokens.append(.function(.cbrt))
        case "'", "′", "’", "`":
            // Штрих производной обрабатывается на уровне классификатора задач.
            throw MathError.syntax(detail: String(c))
        default:
            throw MathError.syntax(detail: l10nUnknownSymbol(c))
        }
    }

    private func l10nUnknownSymbol(_ c: Character) -> String {
        "«\(c)»"
    }
}
