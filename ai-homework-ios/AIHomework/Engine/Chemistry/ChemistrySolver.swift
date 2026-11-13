import Foundation

/// Химическая формула: состав по элементам в порядке первого появления.
struct ChemicalFormula: Sendable, Hashable {
    let text: String
    let composition: [String: Int]
    let order: [String]

    /// Запись с подстрочными индексами: `H₂SO₄`.
    var display: String {
        let subscripts: [Character: Character] = [
            "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        ]
        var result = ""
        var previousIsCoefficientPosition = true
        for c in text {
            if c == "*" {
                result.append("·")
                previousIsCoefficientPosition = true
            } else if let sub = subscripts[c], !previousIsCoefficientPosition {
                result.append(sub)
            } else {
                result.append(c)
                if !c.isNumber { previousIsCoefficientPosition = false }
            }
        }
        return result
    }

    var atomCount: Int { composition.values.reduce(0, +) }

    /// Молярная масса по школьным (округлённым) атомным массам.
    func schoolMolarMass() throws -> Rational {
        var sum = Rational.zero
        for symbol in order {
            guard let element = PeriodicTable.element(symbol), let count = composition[symbol] else { continue }
            sum = try sum + (try element.schoolMass * Rational(count))
        }
        return sum
    }

    var preciseMolarMass: Double {
        order.reduce(0) { $0 + (PeriodicTable.element($1)?.mass ?? 0) * Double(composition[$1] ?? 0) }
    }
}

/// Разбор записи вида `Ca(OH)2`, `CuSO4*5H2O`, `Fe2(SO4)3`.
struct ChemicalFormulaParser {
    private let chars: [Character]
    private var pos = 0
    private var order: [String] = []

    static func parse(_ text: String) -> ChemicalFormula? {
        let normalized = normalize(text)
        guard !normalized.isEmpty else { return nil }
        var parser = ChemicalFormulaParser(chars: Array(normalized))
        guard let composition = parser.parseSequence(), parser.pos == parser.chars.count, !composition.isEmpty else { return nil }
        return ChemicalFormula(text: normalized, composition: composition, order: parser.order)
    }

    private init(chars: [Character]) {
        self.chars = chars
    }

    static func normalize(_ text: String) -> String {
        let subscripts: [Character: Character] = [
            "₀": "0", "₁": "1", "₂": "2", "₃": "3", "₄": "4", "₅": "5", "₆": "6", "₇": "7", "₈": "8", "₉": "9",
        ]
        var result = ""
        for c in text {
            if let digit = subscripts[c] {
                result.append(digit)
            } else if c == "[" || c == "{" {
                result.append("(")
            } else if c == "]" || c == "}" {
                result.append(")")
            } else if "·•∙⋅".contains(c) {
                result.append("*")
            } else {
                result.append(c)
            }
        }
        return result
    }

    private mutating func readNumber() -> Int? {
        var digits = ""
        while pos < chars.count, chars[pos].isASCII, chars[pos].isNumber {
            digits.append(chars[pos])
            pos += 1
        }
        return digits.isEmpty ? nil : Int(digits)
    }

    private func merge(_ target: inout [String: Int], _ source: [String: Int], times: Int) {
        for (symbol, count) in source {
            target[symbol, default: 0] += count * times
        }
    }

    private mutating func parseSequence() -> [String: Int]? {
        var result: [String: Int] = [:]
        var parsedAnything = false
        while pos < chars.count {
            let c = chars[pos]
            if c == "(" {
                pos += 1
                guard let inner = parseSequence(), pos < chars.count, chars[pos] == ")" else { return nil }
                pos += 1
                let count = readNumber() ?? 1
                guard count > 0, count < 1000 else { return nil }
                merge(&result, inner, times: count)
                parsedAnything = true
            } else if c == ")" {
                break
            } else if c == "*" {
                // Кристаллогидрат: CuSO4*5H2O
                pos += 1
                let multiplier = readNumber() ?? 1
                guard let rest = parseSequence() else { return nil }
                merge(&result, rest, times: multiplier)
                parsedAnything = true
            } else if c.isASCII, c.isUppercase {
                var symbol = String(c)
                pos += 1
                if pos < chars.count, chars[pos].isASCII, chars[pos].isLowercase {
                    let two = symbol + String(chars[pos])
                    if PeriodicTable.element(two) != nil {
                        symbol = two
                        pos += 1
                    }
                }
                guard PeriodicTable.element(symbol) != nil else { return nil }
                let count = readNumber() ?? 1
                guard count > 0, count < 1000 else { return nil }
                if !order.contains(symbol) { order.append(symbol) }
                result[symbol, default: 0] += count
                parsedAnything = true
            } else {
                return nil
            }
        }
        return parsedAnything ? result : nil
    }
}

/// Химия: молярная масса, массовые доли, количество вещества, уравнивание реакций.
struct ChemistrySolver: Sendable {
    let lang: AppLanguage
    private let l: L10n
    private let fmt: MathFormatter

    init(lang: AppLanguage) {
        self.lang = lang
        l = L10n(lang)
        fmt = MathFormatter(lang: lang, preferDecimals: true)
    }

    /// Кириллические буквы, которыми OCR подменяет латинские в формулах: «Н₂О», «СО₂».
    private static let lookalikes: [Character: Character] = [
        "А": "A", "В": "B", "С": "C", "Е": "E", "Н": "H", "К": "K", "М": "M", "О": "O", "Р": "P", "Т": "T", "Х": "X", "У": "Y",
        "а": "a", "с": "c", "е": "e", "о": "o", "р": "p", "х": "x", "у": "y", "г": "r",
    ]

    // MARK: - Entry point

    func solve(_ text: String) -> Solution? {
        var prepared = latinizeFormulaTokens(ChemicalFormulaParser.normalize(text))
        // «M(H2SO4)», «ω(O)», «n(NaOH)» — снимаем обозначение величины, оставляя формулу.
        prepared = Rx.replace(
            "(?<![A-Za-z])(?:Mr|Ar|M|n|m|V|N|w|W|ω)\\s*\\(([^()]*(?:\\([^()]*\\)[^()]*)*)\\)", in: prepared, with: " $1 ",
            caseInsensitive: false)
        let lower = text.lowercased()

        if let reaction = findReaction(in: prepared) {
            return balance(reaction)
        }
        let formulas = findFormulas(in: prepared)
        guard let formula = formulas.first else { return nil }

        do {
            if let solution = try solveAmount(formula, lower: lower, prepared: prepared) { return solution }
            if lower.containsAny(["массов", "mass fraction", "mass percent", "percent composition", "percentage composition", "ω", "процентн"]) {
                return try massFractions(formula, lower: lower)
            }
            return try molarMass(formula)
        } catch let error as MathError {
            return Solution.unsupported(subject: .chemistry, problemType: l("Химия", "Chemistry"), reason: error.message(l), engine: .chemistry)
        } catch {
            return nil
        }
    }

    /// Признаки химии в тексте (для определения предмета). Аббревиатуры вроде «OK» или «BC»
    /// формально состоят из символов элементов, поэтому требуем цифру или строчную букву.
    func evidence(in text: String) -> FormulaEvidence {
        let prepared = latinizeFormulaTokens(ChemicalFormulaParser.normalize(text))
        if findReaction(in: prepared) != nil { return .reaction }
        let convincing = findFormulas(in: prepared).contains { formula in
            formula.text.contains { $0.isNumber || $0.isLowercase }
        }
        return convincing ? .formula : .none
    }

    // MARK: - Finding formulas in text

    /// Заменяем кириллических «двойников» только в словах, похожих на формулы.
    private func latinizeFormulaTokens(_ text: String) -> String {
        var result = ""
        var token = ""
        func flush() {
            guard !token.isEmpty else { return }
            let isFormulaLike =
                token.allSatisfy { c in
                    ChemistrySolver.lookalikes[c] != nil || (c.isASCII && (c.isLetter || c.isNumber)) || "()*".contains(c)
                }
                && token.contains { $0.isUppercase }
                && token.contains { ($0.isASCII && $0.isLetter) || $0.isNumber }
                && token.contains { ChemistrySolver.lookalikes[$0] != nil }
            result += isFormulaLike ? String(token.map { ChemistrySolver.lookalikes[$0] ?? $0 }) : token
            token = ""
        }
        for c in text {
            if c.isLetter || c.isNumber || "()*".contains(c) {
                token.append(c)
            } else {
                flush()
                result.append(c)
            }
        }
        flush()
        return result
    }

    private static let formulaPattern = "(?<![A-Za-zА-Яа-яЁё])((?:[A-Z][a-z]?\\d*|\\((?:[A-Z][a-z]?\\d*)+\\)\\d*)+(?:\\*\\d*(?:[A-Z][a-z]?\\d*)+)?)(?![A-Za-zА-Яа-яЁё])"

    /// Английские слова, совпадающие с записью формулы из символов элементов.
    private static let falseFormulas: Set<String> = [
        "I", "A", "In", "As", "At", "No", "He", "Be", "Am", "Os", "Na", "Find", "The", "Is", "If", "Of", "Or", "On", "So",
        "Calculate", "What", "How", "Balance", "Determine", "Compute", "Solve", "Mr", "M", "Ar", "N", "V", "W", "Y", "U", "K",
        "P", "S", "C", "B", "F", "H", "O",
    ]

    private func findFormulas(in text: String) -> [ChemicalFormula] {
        var result: [ChemicalFormula] = []
        for match in Rx.matches(ChemistrySolver.formulaPattern, in: text, caseInsensitive: false) {
            let token = match[1]
            guard !ChemistrySolver.falseFormulas.contains(token), let formula = ChemicalFormulaParser.parse(token) else { continue }
            // Одиночный символ без индекса — слишком ненадёжно («Со», «Не»), кроме записи с цифрой: O2, H2.
            let hasDigit = token.contains { $0.isNumber }
            guard formula.atomCount >= 2 || hasDigit else { continue }
            // Слово из одной заглавной и строчных букв без цифр («Cu» — допустимо, «Find» — отсеяно выше).
            if !hasDigit, formula.order.count == 1 { continue }
            if !result.contains(formula) { result.append(formula) }
        }
        return result
    }

    // MARK: - Molar mass

    private func molarMassBreakdown(_ formula: ChemicalFormula) throws -> (text: String, value: Rational) {
        var parts: [String] = []
        for symbol in formula.order {
            guard let element = PeriodicTable.element(symbol), let count = formula.composition[symbol] else { continue }
            let mass = fmt.rational(element.schoolMass)
            parts.append(count == 1 ? mass : "\(count)·\(mass)")
        }
        return (parts.joined(separator: " + "), try formula.schoolMolarMass())
    }

    private func atomicMassesStep(_ formula: ChemicalFormula) -> SolutionStep {
        let lines = formula.order.compactMap { symbol -> String? in
            guard let element = PeriodicTable.element(symbol) else { return nil }
            return "Ar(\(symbol)) = \(fmt.rational(element.schoolMass)) — \(element.name(l).lowercased())"
        }
        return SolutionStep(
            l("Атомные массы из таблицы Менделеева", "Atomic masses from the periodic table"),
            l("Используем округлённые значения, как принято в школе.", "We use rounded values, as is customary at school."),
            formula: lines.joined(separator: "\n"))
    }

    private func molarMass(_ formula: ChemicalFormula) throws -> Solution {
        let breakdown = try molarMassBreakdown(formula)
        let unit = l("г/моль", "g/mol")
        let steps = [
            atomicMassesStep(formula),
            SolutionStep(
                l("Сложим массы всех атомов в формуле", "Add the masses of all atoms in the formula"),
                l("Индекс показывает, сколько атомов элемента в молекуле.", "A subscript shows how many atoms of the element the molecule has."),
                formula: "Mr(\(formula.display)) = \(breakdown.text) = \(fmt.rational(breakdown.value))"),
            SolutionStep(
                l("Молярная масса численно равна относительной молекулярной", "The molar mass is numerically equal to the relative molecular mass"),
                formula: "M(\(formula.display)) = \(fmt.rational(breakdown.value)) \(unit)"),
        ]
        return Solution(
            subject: .chemistry, problemType: l("Молярная масса вещества", "Molar mass"),
            interpretedProblem: formula.display,
            answer: "M(\(formula.display)) = \(fmt.rational(breakdown.value)) \(unit)",
            explanation: l(
                "Относительная молекулярная масса — это сумма относительных атомных масс всех атомов в формуле с учётом индексов.",
                "The relative molecular mass is the sum of the relative atomic masses of all atoms in the formula, taking subscripts into account."),
            steps: steps, formulas: ["Mr = Σ n·Ar"], reliability: .exact, engine: .chemistry,
            notes: [
                l(
                    "Точное значение по стандартным атомным массам: \(fmt.approx(formula.preciseMolarMass, significant: 7)) г/моль.",
                    "Precise value from standard atomic weights: \(fmt.approx(formula.preciseMolarMass, significant: 7)) g/mol.")
            ])
    }

    // MARK: - Mass fractions

    private func massFractions(_ formula: ChemicalFormula, lower: String) throws -> Solution {
        let breakdown = try molarMassBreakdown(formula)
        var lines: [String] = []
        var fractions: [String: Rational] = [:]
        for symbol in formula.order {
            guard let element = PeriodicTable.element(symbol), let count = formula.composition[symbol] else { continue }
            let part = try element.schoolMass * Rational(count)
            let fraction = try (try part / breakdown.value) * Rational(100)
            fractions[symbol] = fraction
            lines.append(
                "ω(\(symbol)) = \(count == 1 ? "" : "\(count)·")\(fmt.rational(element.schoolMass))/\(fmt.rational(breakdown.value))·100% ≈ \(fmt.approx(fraction.doubleValue, significant: 4))%"
            )
        }
        // Спрашивают про конкретный элемент?
        var requested: String?
        if let element = PeriodicTable.element(mentionedIn: lower), formula.composition[element.symbol] != nil {
            requested = element.symbol
        }
        let all = formula.order.compactMap { symbol in fractions[symbol].map { "ω(\(symbol)) ≈ \(fmt.approx($0.doubleValue, significant: 4))%" } }
        let answer: String
        if let requested, let value = fractions[requested] {
            answer = "ω(\(requested)) ≈ \(fmt.approx(value.doubleValue, significant: 4))%"
        } else {
            answer = all.joined(separator: "; ")
        }
        let steps = [
            atomicMassesStep(formula),
            SolutionStep(
                l("Найдём относительную молекулярную массу", "Find the relative molecular mass"),
                formula: "Mr(\(formula.display)) = \(breakdown.text) = \(fmt.rational(breakdown.value))"),
            SolutionStep(
                l("Вычислим массовые доли элементов", "Compute the mass fractions of the elements"),
                l(
                    "Массовая доля — это доля массы атомов элемента в массе всей молекулы.",
                    "A mass fraction is the share of the element's atoms in the mass of the whole molecule."),
                formula: lines.joined(separator: "\n")),
        ]
        return Solution(
            subject: .chemistry, problemType: l("Массовая доля элемента", "Mass fraction of an element"),
            interpretedProblem: formula.display, answer: answer,
            explanation: l(
                "Чтобы найти массовую долю элемента, массу всех его атомов в формуле делят на молекулярную массу вещества и умножают на 100%.",
                "To find an element's mass fraction, divide the mass of all its atoms in the formula by the molecular mass and multiply by 100%."),
            steps: steps, formulas: ["ω(Э) = n·Ar(Э)/Mr·100%"], reliability: .exact, engine: .chemistry)
    }

    // MARK: - Amount of substance

    private enum AmountKind { case mass, moles, volume }

    /// n = m/M, m = n·M, V = n·Vm, N = n·Nₐ.
    private func solveAmount(_ formula: ChemicalFormula, lower: String, prepared: String) throws -> Solution? {
        let pattern = "(\\d+(?:[.,]\\d+)?)\\s*(кг|kg|мг|mg|г|g|ммоль|mmol|моль|моля|молей|mol|moles|mole|мл|ml|л|l|L)(?![A-Za-zА-Яа-яёЁ\\d])"
        guard let match = Rx.first(pattern, in: prepared, caseInsensitive: false),
            let raw = Double(match[1].replacingOccurrences(of: ",", with: "."))
        else { return nil }
        let unit = match[2]
        let kind: AmountKind
        var value = raw
        switch unit {
        case "кг", "kg": kind = .mass; value = raw * 1000
        case "мг", "mg": kind = .mass; value = raw / 1000
        case "г", "g": kind = .mass
        case "ммоль", "mmol": kind = .moles; value = raw / 1000
        case "моль", "моля", "молей", "mol", "moles", "mole": kind = .moles
        case "мл", "ml": kind = .volume; value = raw / 1000
        default: kind = .volume
        }

        let wantsMoles = lower.containsAny(["количество вещества", "количества вещества", "сколько моль", "сколько молей", "число моль", "amount of substance", "how many moles", "number of moles"])
        let wantsParticles = lower.containsAny(["молекул", "атомов", "частиц", "molecules", "atoms", "particles"])
        let wantsVolume = lower.containsAny(["объём", "объем", "volume"]) && kind != .volume
        let wantsMass = lower.containsAny(["масс", "сколько грамм", "mass", "how many grams"]) && kind != .mass && !lower.containsAny(["молярн", "molar"])
        guard wantsMoles || wantsParticles || wantsVolume || wantsMass else { return nil }

        let molar = try formula.schoolMolarMass().doubleValue
        let breakdown = try molarMassBreakdown(formula)
        let name = formula.display
        let gUnit = l("г", "g")
        let molUnit = l("моль", "mol")
        let literUnit = l("л", "L")
        var steps: [SolutionStep] = []
        var formulas: [String] = []
        var notes: [String] = []

        let givenText: String
        switch kind {
        case .mass: givenText = "m(\(name)) = \(fmt.approx(value)) \(gUnit)"
        case .moles: givenText = "n(\(name)) = \(fmt.approx(value)) \(molUnit)"
        case .volume: givenText = "V(\(name)) = \(fmt.approx(value)) \(literUnit)"
        }
        steps.append(SolutionStep(l("Дано", "Given"), formula: givenText))

        // Сначала находим количество вещества.
        let moles: Double
        switch kind {
        case .mass:
            moles = value / molar
            steps.append(
                SolutionStep(
                    l("Найдём молярную массу", "Find the molar mass"),
                    formula: "M(\(name)) = \(breakdown.text) = \(fmt.rational(breakdown.value)) \(l("г/моль", "g/mol"))"))
            steps.append(
                SolutionStep(
                    l("Найдём количество вещества", "Find the amount of substance"),
                    formula: "n = m/M = \(fmt.approx(value))/\(fmt.approx(molar)) ≈ \(fmt.approx(moles, significant: 4)) \(molUnit)"))
            formulas.append("n = m/M")
        case .moles:
            moles = value
        case .volume:
            moles = value / 22.4
            steps.append(
                SolutionStep(
                    l("Найдём количество вещества газа", "Find the amount of gas"),
                    l("Молярный объём газа при нормальных условиях Vm = 22,4 л/моль.", "The molar volume of a gas at standard conditions is Vm = 22.4 L/mol."),
                    formula: "n = V/Vm = \(fmt.approx(value))/22\(lang.decimalSeparator)4 ≈ \(fmt.approx(moles, significant: 4)) \(molUnit)"))
            formulas.append("n = V/Vm")
            notes.append(l("Расчёт по объёму верен только для газов при нормальных условиях.", "The volume calculation is valid only for gases at standard conditions."))
        }

        var answers: [String] = []
        if wantsMoles || (kind != .moles && !wantsMass && !wantsVolume && !wantsParticles) {
            answers.append("n(\(name)) ≈ \(fmt.approx(moles, significant: 4)) \(molUnit)")
        }
        if wantsMass {
            let mass = moles * molar
            if kind != .mass {
                steps.append(
                    SolutionStep(
                        l("Найдём молярную массу", "Find the molar mass"),
                        formula: "M(\(name)) = \(breakdown.text) = \(fmt.rational(breakdown.value)) \(l("г/моль", "g/mol"))"))
            }
            steps.append(
                SolutionStep(
                    l("Найдём массу", "Find the mass"),
                    formula: "m = n·M = \(fmt.approx(moles, significant: 4))·\(fmt.approx(molar)) ≈ \(fmt.approx(mass, significant: 4)) \(gUnit)"))
            formulas.append("m = n·M")
            answers.append("m(\(name)) ≈ \(fmt.approx(mass, significant: 4)) \(gUnit)")
        }
        if wantsVolume {
            let volume = moles * 22.4
            steps.append(
                SolutionStep(
                    l("Найдём объём газа при нормальных условиях", "Find the gas volume at standard conditions"),
                    formula: "V = n·Vm = \(fmt.approx(moles, significant: 4))·22\(lang.decimalSeparator)4 ≈ \(fmt.approx(volume, significant: 4)) \(literUnit)"))
            formulas.append("V = n·Vm")
            answers.append("V(\(name)) ≈ \(fmt.approx(volume, significant: 4)) \(literUnit)")
            notes.append(l("Объём рассчитан для газа при нормальных условиях (Vm = 22,4 л/моль).", "The volume is computed for a gas at standard conditions (Vm = 22.4 L/mol)."))
        }
        if wantsParticles {
            let particles = moles * 6.02e23
            steps.append(
                SolutionStep(
                    l("Найдём число молекул", "Find the number of molecules"),
                    l("Постоянная Авогадро Nₐ = 6,02·10²³ моль⁻¹.", "Avogadro's constant is Nₐ = 6.02·10²³ mol⁻¹."),
                    formula: "N = n·Nₐ = \(fmt.approx(moles, significant: 4))·6\(lang.decimalSeparator)02·10²³ ≈ \(fmt.approx(particles, significant: 3))"))
            formulas.append("N = n·Nₐ")
            answers.append("N ≈ \(fmt.approx(particles, significant: 3))")
        }
        guard !answers.isEmpty else { return nil }
        notes.append(l("Условие интерпретировано автоматически — сверьте блок «Дано».", "The problem was interpreted automatically — check the “Given” block."))
        return Solution(
            subject: .chemistry, problemType: l("Количество вещества", "Amount of substance"),
            interpretedProblem: givenText, answer: answers.joined(separator: "; "),
            explanation: l(
                "Количество вещества связывает массу, объём газа и число частиц: всё пересчитывается через моль.",
                "The amount of substance links mass, gas volume and number of particles: everything is converted through moles."),
            steps: steps, formulas: formulas, reliability: .heuristic, engine: .chemistry, notes: notes)
    }

    // MARK: - Balancing reactions

    struct Reaction: Sendable {
        var reactants: [ChemicalFormula]
        var products: [ChemicalFormula]
        var givenCoefficients: [Int]
    }

    private func findReaction(in text: String) -> Reaction? {
        let unified = text.replacingOccurrences(of: "->", with: "→").replacingOccurrences(of: "=>", with: "→")
            .replacingOccurrences(of: "⟶", with: "→").replacingOccurrences(of: "⇄", with: "→").replacingOccurrences(of: "↔", with: "→")
            .replacingOccurrences(of: "—>", with: "→").replacingOccurrences(of: "−>", with: "→")
        for line in unified.components(separatedBy: .newlines) {
            // Берём самую длинную цепочку «формула + формула → формула».
            let term = "\\d*\\s*(?:[A-Z][a-z]?\\d*|\\((?:[A-Z][a-z]?\\d*)+\\)\\d*)+"
            let side = "\(term)(?:\\s*\\+\\s*\(term))*"
            let pattern = "(?<![A-Za-z])(\(side))\\s*(?:→|=)\\s*(\(side))(?![a-z])"
            for match in Rx.matches(pattern, in: line, caseInsensitive: false) {
                var coefficients: [Int] = []
                func parseSide(_ text: String) -> [ChemicalFormula]? {
                    var formulas: [ChemicalFormula] = []
                    for piece in text.components(separatedBy: "+") {
                        let trimmed = piece.trimmed
                        let digits = String(trimmed.prefix(while: { $0.isNumber }))
                        let body = String(trimmed.dropFirst(digits.count)).trimmed
                        guard let formula = ChemicalFormulaParser.parse(body) else { return nil }
                        formulas.append(formula)
                        coefficients.append(Int(digits) ?? 1)
                    }
                    return formulas
                }
                guard let reactants = parseSide(match[1]), let products = parseSide(match[2]) else { continue }
                guard reactants.count + products.count >= 3 || (reactants.count + products.count == 2 && match[0].contains("→")) else { continue }
                return Reaction(reactants: reactants, products: products, givenCoefficients: coefficients)
            }
        }
        return nil
    }

    /// Коэффициенты находятся как целочисленное решение системы линейных уравнений
    /// «число атомов каждого элемента слева = справа».
    private func balance(_ reaction: Reaction) -> Solution {
        let species = reaction.reactants + reaction.products
        let reactantCount = reaction.reactants.count
        var elements: [String] = []
        for formula in species {
            for symbol in formula.order where !elements.contains(symbol) { elements.append(symbol) }
        }
        let title = l("Расстановка коэффициентов в уравнении реакции", "Balancing a chemical equation")

        func equationText(_ coefficients: [Int]) -> String {
            func side(_ range: Range<Int>) -> String {
                range.map { index in
                    (coefficients[index] == 1 ? "" : "\(coefficients[index])") + species[index].display
                }.joined(separator: " + ")
            }
            return side(0..<reactantCount) + " → " + side(reactantCount..<species.count)
        }
        let skeleton = equationText([Int](repeating: 1, count: species.count))

        func fail(_ reason: String) -> Solution {
            var solution = Solution.unsupported(subject: .chemistry, problemType: title, reason: reason, engine: .chemistry)
            solution.interpretedProblem = skeleton
            return solution
        }

        // Элементы слева и справа должны совпадать.
        let left = Set(reaction.reactants.flatMap { $0.order })
        let right = Set(reaction.products.flatMap { $0.order })
        guard left == right else {
            let missing = left.symmetricDifference(right).sorted().joined(separator: ", ")
            return fail(
                l(
                    "Уравнение нельзя уравнять: элемент(ы) \(missing) есть только в одной части. Проверьте формулы веществ.",
                    "The equation cannot be balanced: element(s) \(missing) appear on one side only. Check the formulas."))
        }

        do {
            // Матрица: строки — элементы, столбцы — вещества (продукты со знаком минус).
            var matrix: [[Rational]] = elements.map { element in
                species.enumerated().map { index, formula in
                    let count = formula.composition[element] ?? 0
                    return Rational(index < reactantCount ? count : -count)
                }
            }
            let columns = species.count
            var pivotColumns: [Int] = []
            var row = 0
            for column in 0..<columns where row < matrix.count {
                guard let source = (row..<matrix.count).first(where: { !matrix[$0][column].isZero }) else { continue }
                matrix.swapAt(source, row)
                let pivot = matrix[row][column]
                for k in 0..<columns { matrix[row][k] = try matrix[row][k] / pivot }
                for other in 0..<matrix.count where other != row {
                    let factor = matrix[other][column]
                    guard !factor.isZero else { continue }
                    for k in 0..<columns {
                        matrix[other][k] = try matrix[other][k] - (try factor * matrix[row][k])
                    }
                }
                pivotColumns.append(column)
                row += 1
            }
            let freeColumns = (0..<columns).filter { !pivotColumns.contains($0) }
            guard freeColumns.count == 1, let free = freeColumns.first else {
                return fail(
                    freeColumns.isEmpty
                        ? l(
                            "Для этих веществ не существует набора коэффициентов: числа атомов уравнять невозможно. Проверьте формулы.",
                            "No set of coefficients exists for these substances: the atom counts cannot be balanced. Check the formulas.")
                        : l(
                            "Уравнение можно уравнять несколькими независимыми способами (это сумма нескольких реакций), поэтому однозначного ответа нет.",
                            "The equation can be balanced in several independent ways (it is a sum of several reactions), so there is no unique answer."
                        ))
            }
            // Свободная переменная = 1, остальные выражаются через неё.
            var solution = [Rational](repeating: .zero, count: columns)
            solution[free] = .one
            for (rowIndex, column) in pivotColumns.enumerated() {
                solution[column] = matrix[rowIndex][free].negated
            }
            var denominator = 1
            for value in solution { denominator = try Rational.lcm(denominator, value.den) }
            var integers: [Int] = []
            for value in solution { integers.append((try value * Rational(denominator)).num) }
            let divisor = integers.reduce(0) { Rational.gcd($0, $1) }
            integers = integers.map { $0 / max(divisor, 1) }
            if integers.allSatisfy({ $0 < 0 }) { integers = integers.map { -$0 } }
            guard integers.allSatisfy({ $0 > 0 }) else {
                return fail(
                    l(
                        "Формально коэффициенты получаются нулевыми или отрицательными — такая реакция в записанном виде невозможна. Проверьте, какие вещества реагенты, а какие продукты.",
                        "The coefficients come out zero or negative — the reaction is impossible as written. Check which substances are reactants and which are products."
                    ))
            }

            let balanced = equationText(integers)
            let alreadyBalanced = reaction.givenCoefficients == integers
            var countsBefore: [String] = []
            var countsAfter: [String] = []
            for element in elements {
                func total(_ range: Range<Int>, _ coefficients: [Int]) -> Int {
                    range.reduce(0) { $0 + coefficients[$1] * (species[$1].composition[element] ?? 0) }
                }
                let ones = [Int](repeating: 1, count: columns)
                let beforeLeft = total(0..<reactantCount, ones)
                let beforeRight = total(reactantCount..<columns, ones)
                countsBefore.append("\(element): \(beforeLeft) \(beforeLeft == beforeRight ? "=" : "≠") \(beforeRight)")
                let afterLeft = total(0..<reactantCount, integers)
                let afterRight = total(reactantCount..<columns, integers)
                countsAfter.append("\(element): \(afterLeft) = \(afterRight) ✓")
            }

            let steps = [
                SolutionStep(l("Запишем схему реакции", "Write the reaction scheme"), formula: skeleton),
                SolutionStep(
                    l("Посчитаем атомы каждого элемента слева и справа", "Count the atoms of each element on both sides"),
                    l("Пока коэффициентов нет, числа атомов могут не совпадать.", "Without coefficients the atom counts may differ."),
                    formula: countsBefore.joined(separator: "\n")),
                SolutionStep(
                    l("Подберём коэффициенты", "Choose the coefficients"),
                    l(
                        "По закону сохранения массы число атомов каждого элемента до и после реакции одинаково. Это даёт систему уравнений для коэффициентов; берём её наименьшее целое решение.",
                        "By the law of conservation of mass, the number of atoms of each element is the same before and after the reaction. This gives a system of equations for the coefficients; we take its smallest integer solution."
                    ),
                    formula: balanced),
                SolutionStep(l("Проверка", "Check"), formula: countsAfter.joined(separator: "\n")),
            ]
            var notes: [String] = []
            if alreadyBalanced {
                notes.append(l("Коэффициенты в условии уже расставлены верно.", "The coefficients in the task are already correct."))
            }
            return Solution(
                subject: .chemistry, problemType: title, interpretedProblem: skeleton, answer: balanced,
                explanation: l(
                    "Коэффициенты ставят перед формулами так, чтобы атомов каждого элемента слева и справа стало поровну. Индексы внутри формул менять нельзя.",
                    "Coefficients are placed in front of formulas so that each element has equal numbers of atoms on both sides. Subscripts inside formulas must not be changed."
                ),
                steps: steps, reliability: .exact, engine: .chemistry, notes: notes)
        } catch {
            return fail(l("Числа слишком велики для расчёта коэффициентов.", "The numbers are too large to compute the coefficients."))
        }
    }
}
