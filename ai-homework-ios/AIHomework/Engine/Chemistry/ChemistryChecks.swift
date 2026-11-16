import Foundation

/// Проверки «здравого смысла» для химического решателя.
///
/// Уравнивание и молярная масса — точная арифметика, но сама запись может быть неверной:
/// OCR путает букву O с цифрой 0, у ионов есть заряды, а формально уравненная реакция может
/// не идти на практике. Здесь собраны небольшие школьные таблицы, по которым решатель
/// понижает метку «точно» и честно предупреждает пользователя.
enum ChemistryChecks {
    // MARK: - Частые вещества (для восстановления «0 → O»)

    /// Вещества школьного курса, в записи которых есть буква O.
    static let commonCompounds: Set<String> = [
        "H2O", "H2O2", "O2", "O3", "CO", "CO2", "NO", "NO2", "N2O", "N2O3", "N2O5", "SO2", "SO3", "SiO2", "P2O5", "P2O3",
        "Cl2O7", "MnO2", "Mn2O7", "CrO3", "Cr2O3", "Fe2O3", "Fe3O4", "FeO", "CuO", "Cu2O", "ZnO", "MgO", "CaO", "BaO",
        "Na2O", "K2O", "Li2O", "Al2O3", "PbO", "PbO2", "Ag2O", "HgO", "Na2O2",
        "NaOH", "KOH", "LiOH", "Ca(OH)2", "Ba(OH)2", "Mg(OH)2", "Cu(OH)2", "Fe(OH)2", "Fe(OH)3", "Al(OH)3", "Zn(OH)2",
        "NH4OH",
        "H2SO4", "H2SO3", "HNO3", "HNO2", "H3PO4", "H2CO3", "H2SiO3", "HClO4", "HClO3", "HClO",
        "CaCO3", "Na2CO3", "K2CO3", "MgCO3", "BaCO3", "NaHCO3", "Ca(HCO3)2",
        "Na2SO4", "K2SO4", "CuSO4", "FeSO4", "ZnSO4", "MgSO4", "CaSO4", "BaSO4", "Al2(SO4)3", "Fe2(SO4)3", "(NH4)2SO4",
        "NaNO3", "KNO3", "AgNO3", "Cu(NO3)2", "Ca(NO3)2", "Pb(NO3)2", "Ba(NO3)2", "NH4NO3", "Zn(NO3)2", "Mg(NO3)2",
        "Na3PO4", "K3PO4", "Ca3(PO4)2", "Na2SiO3", "KMnO4", "K2MnO4", "K2Cr2O7", "K2CrO4", "KClO3", "NaClO",
        "CH3OH", "C2H5OH", "CH3COOH", "HCOOH", "C6H12O6", "C12H22O11", "CH3COONa", "HCHO", "CH3CHO", "C3H5(OH)3",
        "CuSO4*5H2O",
    ]

    // MARK: - Степени окисления (для проверки бинарных соединений)

    /// Типичные положительные степени окисления.
    private static let positiveStates: [String: [Int]] = [
        "H": [1], "Li": [1], "Na": [1], "K": [1], "Rb": [1], "Cs": [1], "Ag": [1],
        "Be": [2], "Mg": [2], "Ca": [2], "Sr": [2], "Ba": [2], "Zn": [2], "Cd": [2],
        "Cu": [1, 2], "Hg": [1, 2], "B": [3], "Al": [3], "Ga": [3], "Fe": [2, 3], "Co": [2, 3], "Ni": [2, 3],
        "Cr": [2, 3, 6], "Mn": [2, 3, 4, 6, 7], "Pb": [2, 4], "Sn": [2, 4], "Au": [1, 3], "Pt": [2, 4],
        "Ti": [2, 3, 4], "V": [2, 3, 4, 5], "W": [4, 6], "Mo": [4, 6], "Bi": [3, 5], "Sb": [3, 5],
        "C": [2, 4], "Si": [4], "N": [1, 2, 3, 4, 5], "P": [3, 5], "As": [3, 5],
        "S": [4, 6], "Se": [4, 6], "Cl": [1, 3, 4, 5, 6, 7], "Br": [1, 3, 5, 7], "I": [1, 3, 5, 7], "O": [2],
    ]

    /// Типичные отрицательные степени окисления (по модулю). Для O, S и C учтены
    /// пероксиды, дисульфиды и карбиды (−1).
    private static let negativeStates: [String: [Int]] = [
        "O": [2, 1], "F": [1], "Cl": [1], "Br": [1], "I": [1], "S": [2, 1], "Se": [2], "N": [3], "P": [3],
        "As": [3], "C": [4, 1], "Si": [4], "H": [1],
    ]

    /// Можно ли составить бинарное соединение из типичных степеней окисления.
    /// `nil` — проверить нельзя (не бинарное соединение, ион или элемент не из таблицы).
    static func binaryCompoundIsPlausible(_ formula: ChemicalFormula) -> Bool? {
        guard formula.charge == 0, formula.order.count == 2 else { return nil }
        let first = formula.order[0]
        let second = formula.order[1]
        guard let firstCount = formula.composition[first], let secondCount = formula.composition[second],
            firstCount <= 24, secondCount <= 24
        else { return nil }
        let known = { (symbol: String) in positiveStates[symbol] != nil || negativeStates[symbol] != nil }
        guard known(first), known(second) else { return nil }

        func totals(_ states: [Int], _ count: Int) -> Set<Int> {
            var sums: Set<Int> = [0]
            for _ in 0..<count {
                sums = Set(sums.flatMap { sum in states.map { sum + $0 } })
            }
            return sums
        }
        func works(_ positive: String, _ positiveCount: Int, _ negative: String, _ negativeCount: Int) -> Bool {
            guard let up = positiveStates[positive], let down = negativeStates[negative] else { return false }
            return !totals(up, positiveCount).isDisjoint(with: totals(down, negativeCount))
        }
        return works(first, firstCount, second, secondCount) || works(second, secondCount, first, firstCount)
    }

    // MARK: - Ряд активности металлов

    /// Металлы, стоящие в ряду активности правее водорода: они не вытесняют водород
    /// ни из растворов кислот, ни из воды.
    static let metalsAfterHydrogen: Set<String> = ["Cu", "Hg", "Ag", "Pd", "Pt", "Au", "Bi", "Ir", "Rh", "Os", "Ru"]

    /// Металл из `metalsAfterHydrogen`, который в записанной реакции «вытесняет» H₂ из кислоты или воды.
    static func metalThatCannotDisplaceHydrogen(reactants: [ChemicalFormula], products: [ChemicalFormula]) -> String? {
        let releasesHydrogen = products.contains { $0.charge == 0 && $0.composition == ["H": 2] }
        guard releasesHydrogen else { return nil }
        let hasAcidOrWater = reactants.contains { formula in
            formula.charge == 0 && formula.composition["H"] != nil && formula.order.count >= 2
                && (formula.composition == ["H": 2, "O": 1] || formula.order.first == "H")
        }
        guard hasAcidOrWater else { return nil }
        return reactants.first { formula in
            formula.charge == 0 && formula.order.count == 1 && metalsAfterHydrogen.contains(formula.order[0])
        }?.order.first
    }

    // MARK: - OCR: цифра 0 вместо буквы O

    struct ZeroCorrection: Sendable {
        /// Как было записано: `H2S04`.
        let original: String
        /// Восстановленная формула: `H2SO4`.
        let corrected: ChemicalFormula
    }

    /// Находит в тексте формулы, где цифра 0 стоит на месте буквы O (`H2S04`, `C02`, `H20`, `Fe203`),
    /// и заменяет их, если исправленная запись — известное вещество или правдоподобное бинарное
    /// соединение. Остальные такие записи возвращаются как неразрешённые: решатель от них отказывается.
    static func correctZeros(in text: String) -> (text: String, corrections: [ZeroCorrection], unresolved: [String]) {
        let pattern = "(?<![A-Za-z])[A-Z][A-Za-z0-9()]*0[A-Za-z0-9()]*(?![A-Za-z0-9])"
        var result = text
        var corrections: [ZeroCorrection] = []
        var unresolved: [String] = []
        for match in Rx.ranges(pattern, in: text, caseInsensitive: false).reversed() {
            guard let range = match[0] else { continue }
            let token = Array(text[range])
            var fixed = token
            var suspicious = false
            for index in token.indices where token[index] == "0" && index > 0 {
                let previous = token[index - 1]
                let next: Character? = index + 1 < token.count ? token[index + 1] : nil
                let leadingZero = previous.isLetter || previous == "(" || previous == ")"
                let trailingZero = previous.isNumber && (next == nil || next?.isNumber == true || next == "(" || next == ")")
                if leadingZero || trailingZero {
                    fixed[index] = "O"
                    suspicious = true
                }
            }
            guard suspicious else { continue }
            let original = String(token)
            if let formula = ChemicalFormulaParser.parse(String(fixed)),
                commonCompounds.contains(formula.text) || binaryCompoundIsPlausible(formula) == true
            {
                corrections.insert(ZeroCorrection(original: original, corrected: formula), at: 0)
                result.replaceSubrange(range, with: formula.text)
            } else {
                unresolved.insert(original, at: 0)
            }
        }
        return (result, corrections, unresolved)
    }

    // MARK: - Заряды ионов

    private static let superscriptValues: [Character: Character] = [
        "⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9", "⁺": "+", "⁻": "-",
    ]

    /// Приводит записи ионов к виду `Cu^2+`, `SO4^2-`, `OH^-`.
    ///
    /// Понимает `Cu2+`, `Fe3+`, `SO42-`, `NH4+`, `SO4 2-`, `Cu^2+`, `Cu^{2+}`, `Cu²⁺`. Знак считается
    /// зарядом, только если за ним (через пробелы) идёт другой знак, «=», «→» или конец записи:
    /// в `H2+O2=H2O` «+» по-прежнему разделяет вещества.
    static func canonicalizeIons(_ text: String) -> String {
        let chars = Array(text)
        var output = ""
        var index = 0
        while index < chars.count {
            let c = chars[index]
            let startsBody = (c.isASCII && c.isUppercase) || c == "("
            let previousIsLetter = index > 0 && chars[index - 1].isLetter
            guard startsBody, !previousIsLetter else {
                output.append(c)
                index += 1
                continue
            }
            var end = index
            while end < chars.count, chars[end].isASCII, chars[end].isLetter || chars[end].isNumber || chars[end] == "(" || chars[end] == ")" {
                end += 1
            }
            let body = String(chars[index..<end])
            if let ion = readCharge(chars, after: end, body: body) {
                output += ion.body + "^" + (ion.magnitude == 1 ? "" : String(ion.magnitude)) + (ion.positive ? "+" : "-")
                index = ion.end
            } else {
                output += body
                index = end
            }
        }
        return output
    }

    private static func isTerminator(_ chars: [Character], from start: Int) -> Bool {
        var k = start
        while k < chars.count, chars[k] == " " || chars[k] == "\t" { k += 1 }
        return k == chars.count || "+-=→)]},;.?!\n".contains(chars[k])
    }

    private static func readCharge(_ chars: [Character], after end: Int, body: String) -> (body: String, magnitude: Int, positive: Bool, end: Int)? {
        guard end < chars.count, ChemicalFormulaParser.parse(body) != nil || body.last?.isNumber == true else { return nil }
        let c = chars[end]

        // Явная запись: Cu^2+, Cu^{2+}, Cu^(2+), Cu^+2.
        if c == "^" {
            var k = end + 1
            if k < chars.count, "{(".contains(chars[k]) { k += 1 }
            var digits = ""
            while k < chars.count, chars[k].isASCII, chars[k].isNumber { digits.append(chars[k]); k += 1 }
            guard k < chars.count, chars[k] == "+" || chars[k] == "-" else { return nil }
            let positive = chars[k] == "+"
            k += 1
            if digits.isEmpty {
                while k < chars.count, chars[k].isASCII, chars[k].isNumber { digits.append(chars[k]); k += 1 }
            }
            if k < chars.count, "})".contains(chars[k]) { k += 1 }
            guard ChemicalFormulaParser.parse(body) != nil, let magnitude = digits.isEmpty ? 1 : Int(digits), (1...8).contains(magnitude)
            else { return nil }
            return (body, magnitude, positive, k)
        }

        // Надстрочные знаки: Cu²⁺, OH⁻.
        if superscriptValues[c] != nil {
            var k = end
            var digits = ""
            var sign: Character?
            while k < chars.count, let value = superscriptValues[chars[k]] {
                if value == "+" || value == "-" {
                    guard sign == nil else { break }
                    sign = value
                } else {
                    digits.append(value)
                }
                k += 1
            }
            guard let sign, ChemicalFormulaParser.parse(body) != nil, let magnitude = digits.isEmpty ? 1 : Int(digits), (1...8).contains(magnitude)
            else { return nil }
            return (body, magnitude, sign == "+", k)
        }

        // Заряд через пробел: «SO4 2-».
        if c == " " {
            var k = end
            while k < chars.count, chars[k] == " " { k += 1 }
            guard k + 1 < chars.count, let digit = chars[k].wholeNumberValue, chars[k].isASCII, (1...8).contains(digit),
                chars[k + 1] == "+" || chars[k + 1] == "-", isTerminator(chars, from: k + 2),
                ChemicalFormulaParser.parse(body) != nil
            else { return nil }
            return (body, digit, chars[k + 1] == "+", k + 2)
        }

        // Знак сразу после формулы: Cu2+, SO42-, NH4+, OH-.
        guard c == "+" || c == "-", isTerminator(chars, from: end + 1) else { return nil }
        let positive = c == "+"
        let trailing = String(body.reversed().prefix { $0.isNumber }.reversed())
        let stem = String(body.dropLast(trailing.count))
        guard let stemFormula = ChemicalFormulaParser.parse(stem.isEmpty ? body : stem) else { return nil }
        let singleElement = stemFormula.order.count == 1 && !stem.contains("(")
        if trailing.isEmpty || stem.last == ")" {
            guard ChemicalFormulaParser.parse(body) != nil else { return nil }
            return (body, 1, positive, end + 1)
        }
        if trailing.count == 1 && !singleElement {
            // NH4+, HCO3- — цифра остаётся индексом, заряд единичный.
            return (body, 1, positive, end + 1)
        }
        // Cu2+ (одна цифра у простого иона), SO42-, Hg22+ — последняя цифра означает заряд.
        guard let magnitude = trailing.last?.wholeNumberValue, (1...8).contains(magnitude) else { return nil }
        let newBody = stem + String(trailing.dropLast())
        guard ChemicalFormulaParser.parse(newBody) != nil else { return nil }
        return (newBody, magnitude, positive, end + 1)
    }

    /// Разбор частицы с необязательным зарядом в каноническом виде: `SO4^2-`.
    static func parseSpecies(_ text: String) -> ChemicalFormula? {
        let parts = text.split(separator: "^", maxSplits: 1).map(String.init)
        guard var formula = ChemicalFormulaParser.parse(parts[0]) else { return nil }
        if parts.count == 2 {
            let spec = parts[1]
            guard let sign = spec.last, sign == "+" || sign == "-" else { return nil }
            let digits = spec.dropLast()
            guard let magnitude = digits.isEmpty ? 1 : Int(digits), magnitude > 0 else { return nil }
            formula.charge = sign == "+" ? magnitude : -magnitude
        }
        return formula
    }
}
