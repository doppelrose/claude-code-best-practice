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
        ("×", "*"), ("·", "*"), ("⋅", "*"), ("∙", "*"), ("•", "*"), ("✕", "*"), ("∗", "*"),
        ("÷", "/"), ("∕", "/"), ("⁄", "/"),
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
        var result = text
        for (from, to) in replacements {
            result = result.replacingOccurrences(of: from, with: to)
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
    /// Была ли применена эвристика «x2 → x²» (типичная ошибка распознавания степени).
    private(set) var assumedPowers = false

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
        var text = ""
        while pos < chars.count, chars[pos].isASCII, chars[pos].isNumber {
            text.append(chars[pos])
            pos += 1
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
        case ":":
            tokens.append(.op("/"))
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
