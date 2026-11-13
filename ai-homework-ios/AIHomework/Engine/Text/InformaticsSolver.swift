import Foundation

/// Информатика: перевод чисел между системами счисления и единицы измерения информации.
struct InformaticsSolver: Sendable {
    let lang: AppLanguage
    private let l: L10n
    private let fmt: MathFormatter

    init(lang: AppLanguage) {
        self.lang = lang
        l = L10n(lang)
        fmt = MathFormatter(lang: lang, preferDecimals: true)
    }

    func solve(_ text: String) -> Solution? {
        let lower = text.lowercased()
        if let solution = solveInformationUnits(lower) { return solution }
        return solveBaseConversion(text)
    }

    // MARK: - Number systems

    private static let baseNames: [(pattern: String, base: Int)] = [
        ("шестнадцат[еи]ричн\\w*|hexadecimal|\\bhex\\b", 16), ("двоичн\\w*|binary", 2), ("троичн\\w*|ternary", 3),
        ("четверичн\\w*|quaternary", 4), ("пятеричн\\w*", 5), ("восьмеричн\\w*|octal", 8), ("десятичн\\w*|decimal", 10),
    ]

    private static let subscriptDigits: [Character: Int] = [
        "₀": 0, "₁": 1, "₂": 2, "₃": 3, "₄": 4, "₅": 5, "₆": 6, "₇": 7, "₈": 8, "₉": 9,
    ]

    private func digitValue(_ c: Character) -> Int? {
        if let value = c.wholeNumberValue, c.isASCII { return value }
        guard c.isASCII, let ascii = c.uppercased().unicodeScalars.first?.value, ascii >= 65, ascii <= 70 else { return nil }
        return Int(ascii) - 55
    }

    private func digitCharacter(_ value: Int) -> Character {
        Character(String(value, radix: 16, uppercase: true))
    }

    private func baseName(_ base: Int) -> String {
        switch base {
        case 2: return l("двоичная", "binary")
        case 8: return l("восьмеричная", "octal")
        case 10: return l("десятичная", "decimal")
        case 16: return l("шестнадцатеричная", "hexadecimal")
        default: return l("с основанием \(base)", "base \(base)")
        }
    }

    private func solveBaseConversion(_ text: String) -> Solution? {
        let lower = text.lowercased()

        // Упоминания систем счисления с позициями и ролью (источник / цель).
        struct Mention {
            var base: Int
            var position: Int
            var role: Int  // −1 источник, +1 цель, 0 неизвестно
        }
        var mentions: [Mention] = []
        func role(before index: String.Index) -> Int {
            let start = lower.index(index, offsetBy: -14, limitedBy: lower.startIndex) ?? lower.startIndex
            let context = " " + lower[start..<index]
            if Rx.contains("(\\sиз\\s|\\sfrom\\s)[а-яa-z\\s]{0,8}$", in: context) { return -1 }
            if Rx.contains("(\\sв\\s|\\sво\\s|\\sto\\s|\\sinto\\s|\\sin\\s)[а-яa-z\\s]{0,8}$", in: context) { return 1 }
            return 0
        }
        for (pattern, base) in InformaticsSolver.baseNames {
            for match in Rx.ranges(pattern, in: lower) {
                guard let range = match[0] else { continue }
                mentions.append(Mention(base: base, position: lower.distance(from: lower.startIndex, to: range.lowerBound), role: role(before: range.lowerBound)))
            }
        }
        for match in Rx.ranges("(?:основани\\w+|base)\\s+(\\d{1,2})", in: lower) {
            guard let whole = match[0], let digits = match[1], let base = Int(lower[digits]) else { continue }
            mentions.append(Mention(base: base, position: lower.distance(from: lower.startIndex, to: whole.lowerBound), role: role(before: whole.lowerBound)))
        }
        mentions.sort { $0.position < $1.position }

        // Само число: с индексом основания (1011₂, 1F_16), с префиксом (0b…, 0x…) или обычное.
        var digits: String?
        var ownBase: Int?
        if let match = Rx.first("(?<![0-9A-Za-z])([0-9A-Fa-f]+)([₀-₉]{1,2})", in: text, caseInsensitive: false) {
            digits = match[1]
            ownBase = match[2].reduce(0) { $0 * 10 + (InformaticsSolver.subscriptDigits[$1] ?? 0) }
        } else if let match = Rx.first("(?<![0-9A-Za-z])([0-9A-Fa-f]+)_\\{?(\\d{1,2})\\}?", in: text, caseInsensitive: false) {
            digits = match[1]
            ownBase = Int(match[2])
        } else if let match = Rx.first("(?<![0-9A-Za-z])0b([01]+)(?![0-9A-Za-z])", in: text) {
            digits = match[1]
            ownBase = 2
        } else if let match = Rx.first("(?<![0-9A-Za-z])0x([0-9A-Fa-f]+)(?![0-9A-Za-z])", in: text) {
            digits = match[1]
            ownBase = 16
        } else if !mentions.isEmpty {
            // Обычное число: первая «цифровая» запись, не являющаяся номером основания.
            for match in Rx.matches("(?<![0-9A-Za-zА-Яа-я])([0-9][0-9A-Fa-f]*|[A-F][0-9A-F]*[0-9][0-9A-F]*)(?![0-9A-Za-zа-я])", in: text, caseInsensitive: false) {
                if Rx.contains("(?:основани\\w+|base)\\s+\(match[1])(?!\\d)", in: lower) { continue }
                digits = match[1]
                break
            }
        }
        guard let source = digits?.uppercased(), !source.isEmpty else { return nil }
        guard ownBase != nil || !mentions.isEmpty else { return nil }

        var from: Int?
        var to: Int?
        var assumedNote: String?
        if let ownBase {
            from = ownBase
            to = mentions.first(where: { $0.base != ownBase })?.base ?? (ownBase == 10 ? nil : 10)
        } else {
            from = mentions.first(where: { $0.role == -1 })?.base
            to = mentions.first(where: { $0.role == 1 && $0.base != from })?.base
            if from == nil, to == nil, mentions.count >= 2 {
                from = mentions[0].base
                to = mentions[1].base
            }
            if from == nil, let target = to ?? mentions.first?.base {
                to = target
                if target != 10 {
                    from = 10
                } else if source.allSatisfy({ $0 == "0" || $0 == "1" }) {
                    from = 2
                    assumedNote = l(
                        "Исходная система счисления в условии не названа — число из нулей и единиц принято за двоичное.",
                        "The source base is not stated — the number made of zeros and ones is assumed to be binary.")
                }
            }
            if to == nil, let known = from { to = known == 10 ? nil : 10 }
        }
        guard let fromBase = from, let toBase = to, fromBase != toBase, (2...16).contains(fromBase), (2...16).contains(toBase) else { return nil }

        // Проверяем цифры и переводим в десятичное значение.
        var value = 0
        var digitValues: [Int] = []
        for c in source {
            guard let digit = digitValue(c), digit < fromBase else {
                return Solution.unsupported(
                    subject: .informatics, problemType: l("Системы счисления", "Number systems"),
                    reason: l(
                        "В записи «\(source)» есть цифра, недопустимая в системе с основанием \(fromBase). Проверьте распознанный текст.",
                        "“\(source)” contains a digit that is not valid in base \(fromBase). Check the recognized text."),
                    engine: .informatics)
            }
            let (product, o1) = value.multipliedReportingOverflow(by: fromBase)
            let (sum, o2) = product.addingReportingOverflow(digit)
            guard !o1, !o2 else { return nil }
            value = sum
            digitValues.append(digit)
        }

        var steps: [SolutionStep] = []
        if fromBase != 10 {
            let count = digitValues.count
            let expansion = digitValues.enumerated().map { index, digit in "\(digit)·\(fromBase)\(fmt.superscript(count - 1 - index))" }.joined(separator: " + ")
            var powerValues: [String] = []
            for (index, digit) in digitValues.enumerated() {
                var power = 1
                for _ in 0..<(count - 1 - index) { power *= fromBase }
                powerValues.append(String(digit * power))
            }
            steps.append(
                SolutionStep(
                    l("Переведём в десятичную систему", "Convert to decimal"),
                    l(
                        "Каждую цифру умножаем на основание в степени её разряда (разряды считаем справа, начиная с нуля) и складываем.",
                        "Multiply each digit by the base raised to its position (counting from zero on the right) and add up."),
                    formula: "\(source)\(fmt.subscript(fromBase)) = \(expansion) = \(powerValues.joined(separator: " + ")) = \(value)"))
        }
        var result = String(value)
        if toBase != 10 {
            var lines: [String] = []
            var remainders: [Character] = []
            var current = value
            if current == 0 { remainders = ["0"] }
            while current > 0 {
                let remainder = current % toBase
                lines.append("\(current) : \(toBase) = \(current / toBase), \(l("остаток", "remainder")) \(digitCharacter(remainder))")
                remainders.append(digitCharacter(remainder))
                current /= toBase
            }
            result = String(remainders.reversed())
            steps.append(
                SolutionStep(
                    l("Делим на \(toBase) и записываем остатки", "Divide by \(toBase) and write down the remainders"),
                    l(
                        "Делим число на основание, пока не получим ноль. Остатки, прочитанные снизу вверх, дают запись числа.",
                        "Divide by the base until we reach zero. The remainders read from bottom to top give the number."),
                    formula: lines.joined(separator: "\n")))
            steps.append(
                SolutionStep(
                    l("Читаем остатки снизу вверх", "Read the remainders from bottom to top"),
                    formula: "\(value)\(fmt.subscript(10)) = \(result)\(fmt.subscript(toBase))"))
        }
        let answer = "\(source)\(fmt.subscript(fromBase)) = \(result)\(fmt.subscript(toBase))"
        return Solution(
            subject: .informatics, problemType: l("Перевод между системами счисления", "Number base conversion"),
            interpretedProblem: "\(source)\(fmt.subscript(fromBase)) → \(baseName(toBase))",
            answer: answer,
            explanation: l(
                "В позиционной системе счисления значение цифры зависит от её места: каждая позиция — это степень основания.",
                "In a positional number system a digit's value depends on its place: each position is a power of the base."),
            steps: steps, reliability: .exact, engine: .informatics, notes: assumedNote.map { [$0] } ?? [])
    }

    // MARK: - Information units

    private static let unitPattern = "(гигабайт\\w*|гбайт\\w*|гб|gigabytes?|gb|мегабайт\\w*|мбайт\\w*|мб|megabytes?|mb|килобайт\\w*|кбайт\\w*|кб|kilobytes?|kb|байт\\w*|bytes?|бит\\w*|bits?)"

    /// Размер единицы в битах и её обозначение.
    private func informationUnit(_ token: String) -> (bits: Int, name: String)? {
        let t = token.lowercased()
        if t.hasPrefix("гигабайт") || t.hasPrefix("гбайт") || t == "гб" || t.hasPrefix("gigabyte") || t == "gb" { return (8 * 1024 * 1024 * 1024, l("Гбайт", "GB")) }
        if t.hasPrefix("мегабайт") || t.hasPrefix("мбайт") || t == "мб" || t.hasPrefix("megabyte") || t == "mb" { return (8 * 1024 * 1024, l("Мбайт", "MB")) }
        if t.hasPrefix("килобайт") || t.hasPrefix("кбайт") || t == "кб" || t.hasPrefix("kilobyte") || t == "kb" { return (8 * 1024, l("Кбайт", "KB")) }
        if t.hasPrefix("байт") || t.hasPrefix("byte") { return (8, l("байт", "bytes")) }
        if t.hasPrefix("бит") || t.hasPrefix("bit") { return (1, l("бит", "bits")) }
        return nil
    }

    private func solveInformationUnits(_ lower: String) -> Solution? {
        let number = "(\\d+(?:[.,]\\d+)?)"
        let unit = InformaticsSolver.unitPattern
        var valueText: String?
        var fromToken: String?
        var toToken: String?
        if let match = Rx.first("\(number)\\s*\(unit)\\s+(?:в|во|to|in|into)\\s+\(unit)", in: lower) {
            (valueText, fromToken, toToken) = (match[1], match[2], match[3])
        } else if let match = Rx.first("(?:сколько|how many)\\s+\(unit)\\s+(?:содерж\\w+\\s+)?(?:are\\s+)?(?:there\\s+)?(?:в|in)\\s+\(number)\\s*\(unit)", in: lower) {
            (toToken, valueText, fromToken) = (match[1], match[2], match[3])
        }
        guard let valueText, let fromToken, let toToken, let value = Rational(decimal: valueText),
            let from = informationUnit(fromToken), let to = informationUnit(toToken), from.bits != to.bits
        else { return nil }
        guard let bits = try? value * Rational(from.bits), let result = try? bits / Rational(to.bits) else { return nil }

        let steps = [
            SolutionStep(
                l("Вспомним соотношения единиц", "Recall the unit relationships"),
                formula: l(
                    "1 байт = 8 бит\n1 Кбайт = 1024 байт\n1 Мбайт = 1024 Кбайт\n1 Гбайт = 1024 Мбайт",
                    "1 byte = 8 bits\n1 KB = 1024 bytes\n1 MB = 1024 KB\n1 GB = 1024 MB")),
            SolutionStep(
                l("Переведём в биты", "Convert to bits"),
                formula: "\(fmt.rational(value)) \(from.name) = \(fmt.rational(value))·\(from.bits) = \(fmt.rational(bits)) \(l("бит", "bits"))"),
            SolutionStep(
                l("Переведём в нужные единицы", "Convert to the required unit"),
                formula: "\(fmt.rational(bits)) : \(to.bits) = \(fmt.rationalWithApproximation(result)) \(to.name)"),
        ]
        return Solution(
            subject: .informatics, problemType: l("Единицы измерения информации", "Units of information"),
            interpretedProblem: "\(fmt.rational(value)) \(from.name) → \(to.name)",
            answer: "\(fmt.rational(value)) \(from.name) = \(fmt.rationalWithApproximation(result)) \(to.name)",
            explanation: l(
                "В информатике приставки «кило», «мега», «гига» традиционно означают умножение на 1024 = 2¹⁰.",
                "In computer science the prefixes kilo, mega and giga traditionally mean multiplication by 1024 = 2¹⁰."),
            steps: steps, reliability: .exact, engine: .informatics)
    }
}
