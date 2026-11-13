import Foundation

/// Решатель расчётных задач по физике «в одну формулу».
///
/// Это не языковая модель, а детерминированный алгоритм: он находит в тексте числа с единицами
/// измерения, переводит их в СИ, определяет искомую величину по ключевым словам и подбирает
/// формулу из школьной базы, в которой неизвестна ровно одна величина. Как именно понято
/// условие, всегда показывается в блоке «Дано» — пользователь может это проверить.
struct PhysicsSolver: Sendable {
    let lang: AppLanguage
    private let l: L10n
    private let fmt: MathFormatter
    private let evaluator = MathEvaluator()

    init(lang: AppLanguage) {
        self.lang = lang
        l = L10n(lang)
        fmt = MathFormatter(lang: lang, preferDecimals: true)
    }

    /// Величина, найденная в тексте.
    struct Given: Sendable {
        var quantityID: String?
        var dimension: PhysicalDimension
        /// Значение в единицах СИ.
        var value: Double
        /// Как записано в условии: «150 км».
        var sourceText: String
        var isSI: Bool
        /// Табличная константа, а не данные из условия.
        var isTabular = false
    }

    private struct Candidate {
        var formula: PhysicsFormula
        var unknownLetter: String
        var assignment: [String: Given]
        var score: Int
        var result: Double
    }

    // MARK: - Entry point

    func solve(_ text: String) -> Solution? {
        let normalized = normalize(text)
        if let conversion = solveConversion(normalized) { return conversion }

        var givens = extractGivens(normalized)
        guard !givens.isEmpty else { return nil }
        mergeTemperatures(&givens, text: normalized)

        let lower = normalized.lowercased()
        let target = detectTarget(lower)
        let gValue = gravity(in: lower)
        let substance = PhysicsData.substances.first { Rx.contains($0.pattern, in: lower) }

        var candidates: [Candidate] = []
        for formula in PhysicsData.formulas {
            for unknownLetter in formula.forms.keys.sorted() {
                if let candidate = match(
                    formula, unknownLetter: unknownLetter, givens: givens, target: target, gravity: gValue, substance: substance)
                {
                    candidates.append(candidate)
                }
            }
        }
        candidates.sort { $0.score > $1.score }

        guard let best = candidates.first else {
            // Величины с единицами есть, а формулы нет — честно сообщаем, что именно распознано.
            guard givens.count >= 2 else { return nil }
            return unsupported(givens: givens, target: target)
        }
        // Неоднозначность: две формулы подходят одинаково хорошо, а ответы разные.
        if let second = candidates.dropFirst().first(where: { $0.score == best.score }),
            abs(second.result - best.result) > 1e-9 * max(1, abs(best.result))
        {
            return unsupported(givens: givens, target: target, ambiguous: true)
        }
        return buildSolution(best, substance: substance, gravity: gValue)
    }

    // MARK: - Text normalisation

    private func normalize(_ text: String) -> String {
        var result = MathNormalizer.normalize(text)
        // Степени десяти: «3·10⁸» → «3*10^8».
        let superscripts: [Character: Character] = [
            "⁰": "0", "¹": "1", "⁴": "4", "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9", "⁻": "-",
        ]
        var converted = ""
        var inSuperscript = false
        for c in result {
            if let digit = superscripts[c] {
                if !inSuperscript { converted.append("^") }
                converted.append(digit)
                inSuperscript = true
            } else {
                inSuperscript = false
                converted.append(c)
            }
        }
        result = converted
        return result
    }

    // MARK: - Extraction

    private static let unitPattern: String = {
        let symbols = PhysicsData.units.flatMap { $0.symbols }.sorted { $0.count > $1.count }
        return symbols.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
    }()

    private static let unitBySymbol: [String: PhysicalUnit] = {
        var result: [String: PhysicalUnit] = [:]
        for unit in PhysicsData.units {
            for symbol in unit.symbols where result[symbol] == nil {
                result[symbol] = unit
            }
        }
        return result
    }()

    private func parseNumber(_ mantissa: String, exponent: String) -> Double? {
        guard var value = Double(mantissa.replacingOccurrences(of: ",", with: ".")) else { return nil }
        if !exponent.isEmpty, let power = Double(exponent) {
            value *= Foundation.pow(10, power)
        }
        return value
    }

    func extractGivens(_ text: String) -> [Given] {
        let number = "(\\d+(?:[.,]\\d+)?)(?:\\s*\\*\\s*10\\s*\\^\\s*\\(?(-?\\d+)\\)?)?"
        let pattern = "\(number)\\s*(\(PhysicsSolver.unitPattern))(?![a-zA-Zа-яА-ЯёЁ\\d/])"
        var givens: [Given] = []
        var previousEnd = text.startIndex

        for match in Rx.ranges(pattern, in: text, caseInsensitive: false) {
            guard let whole = match[0], let mantissaRange = match[1], let unitRange = match[3] else { continue }
            let mantissa = String(text[mantissaRange])
            let exponent = match[2].map { String(text[$0]) } ?? ""
            let unitSymbol = String(text[unitRange])
            guard let unit = PhysicsSolver.unitBySymbol[unitSymbol], let raw = parseNumber(mantissa, exponent: exponent) else { continue }

            // Контекст слева — от предыдущей величины или начала предложения.
            let contextStart = max(previousEnd, text.index(whole.lowerBound, offsetBy: -60, limitedBy: text.startIndex) ?? text.startIndex)
            var context = String(text[contextStart..<whole.lowerBound])
            if let sentenceBreak = context.lastIndex(where: { ".;?!".contains($0) }) {
                context = String(context[context.index(after: sentenceBreak)...])
            }

            var quantityID: String?
            // Явное обозначение: «m = 2 кг».
            if let symbolMatch = Rx.first("([A-Za-zρλν][0₀]?)\\s*=\\s*$", in: context, caseInsensitive: false) {
                quantityID = PhysicsData.symbolToQuantity[symbolMatch[1]]
            }
            if quantityID == nil {
                quantityID = nearestQuantity(in: context.lowercased(), dimension: unit.dimension)
            }
            if let id = quantityID, id != "g", PhysicsData.quantityByID[id]?.dimension != unit.dimension {
                quantityID = nil
            }

            givens.append(
                Given(
                    quantityID: quantityID, dimension: unit.dimension, value: raw * unit.factor,
                    sourceText: "\(fmt.approx(raw, significant: 10)) \(displayUnit(unitSymbol))",
                    isSI: unit.factor == 1))
            previousEnd = whole.upperBound
        }
        return givens
    }

    private func displayUnit(_ symbol: String) -> String {
        symbol.replacingOccurrences(of: "^2", with: "²").replacingOccurrences(of: "^3", with: "³").replacingOccurrences(of: "*", with: "·")
    }

    /// Ближайшая слева величина той же размерности, упомянутая словом.
    private func nearestQuantity(in context: String, dimension: PhysicalDimension) -> String? {
        var best: (id: String, position: Int, length: Int)?
        for quantity in PhysicsData.quantities where quantity.dimension == dimension {
            for keyword in quantity.keywords {
                for match in Rx.ranges(keyword, in: context) {
                    guard let range = match[0] else { continue }
                    let position = context.distance(from: context.startIndex, to: range.lowerBound)
                    let length = context.distance(from: range.lowerBound, to: range.upperBound)
                    if best == nil || position > (best?.position ?? -1) || (position == best?.position && length > (best?.length ?? 0)) {
                        best = (quantity.id, position, length)
                    }
                }
            }
        }
        return best?.id
    }

    /// Две температуры («от 20 °C до 100 °C») превращаются в одну разность Δt.
    private func mergeTemperatures(_ givens: inout [Given], text: String) {
        let indices = givens.indices.filter { givens[$0].dimension == .temperature }
        if indices.count == 2 {
            let first = givens[indices[0]]
            let second = givens[indices[1]]
            let delta = Given(
                quantityID: "dT", dimension: .temperature, value: abs(second.value - first.value),
                sourceText: "\(fmt.approx(max(first.value, second.value))) − \(fmt.approx(min(first.value, second.value))) = \(fmt.approx(abs(second.value - first.value))) °C",
                isSI: true)
            givens.remove(at: indices[1])
            givens[indices[0]] = delta
        } else if indices.count == 1 {
            givens[indices[0]].quantityID = "dT"
        }
    }

    private func gravity(in lower: String) -> Double {
        if let match = Rx.first("g\\s*(?:=|≈)\\s*(\\d+(?:[.,]\\d+)?)", in: lower),
            let value = Double(match[1].replacingOccurrences(of: ",", with: ".")), value > 9, value < 11
        {
            return value
        }
        return 9.8
    }

    // MARK: - Target detection

    private static let cuePattern =
        "найти|найдите|определите|определить|вычислите|вычислить|рассчитайте|рассчитать|чему равн\\w*|каков\\w*|какое|какая|какой|какую|какие|сколько|"
        + "с какой|на какой|на какую|за какое|find|calculate|determine|compute|what is|what's|what was|what will|how much|how many|how fast|how long|how far|how high"

    /// Искомая величина: первое название величины после слова-вопроса.
    func detectTarget(_ lower: String) -> String? {
        guard let cue = Rx.ranges(PhysicsSolver.cuePattern, in: lower).first?[0] else { return nil }
        let tail = String(lower[cue.lowerBound...])
        var best: (id: String, position: Int, length: Int)?
        for quantity in PhysicsData.quantities {
            for keyword in quantity.keywords {
                guard let range = Rx.ranges(keyword, in: tail).first?[0] else { continue }
                let position = tail.distance(from: tail.startIndex, to: range.lowerBound)
                let length = tail.distance(from: range.lowerBound, to: range.upperBound)
                // Раньше в тексте — важнее; при равенстве побеждает более длинное название («сила тока» против «сила»).
                if best == nil || position < (best?.position ?? Int.max) || (position == best?.position && length > (best?.length ?? 0)) {
                    best = (quantity.id, position, length)
                }
            }
        }
        // «Сколько времени», «how long» и т.п. уже покрыты ключевыми словами величин.
        return best?.id
    }

    // MARK: - Formula matching

    private func match(
        _ formula: PhysicsFormula, unknownLetter: String, givens: [Given], target: String?, gravity: Double, substance: Substance?
    ) -> Candidate? {
        guard let unknownID = formula.variables[unknownLetter], let unknown = PhysicsData.quantityByID[unknownID],
            let form = formula.forms[unknownLetter]
        else { return nil }

        var score = 0
        if let target {
            guard let targetQuantity = PhysicsData.quantityByID[target] else { return nil }
            if target == unknownID {
                score += 6
            } else if targetQuantity.dimension == unknown.dimension {
                score += 1
            } else {
                return nil
            }
        }

        // Остальные переменные формулы нужно сопоставить с данными.
        let neededLetters = formula.variables.keys.filter { $0 != unknownLetter }.sorted()
        var assignment: [String: Given] = [:]
        var used = Set<Int>()

        for letter in neededLetters {
            guard let id = formula.variables[letter], let quantity = PhysicsData.quantityByID[id] else { return nil }
            // Сначала точное совпадение по названию, затем — по размерности.
            let exact = givens.indices.first { !used.contains($0) && givens[$0].quantityID == id }
            let untyped = givens.indices.first { !used.contains($0) && givens[$0].quantityID == nil && givens[$0].dimension == quantity.dimension }
            let loose = givens.indices.first {
                !used.contains($0) && givens[$0].dimension == quantity.dimension && givens[$0].quantityID != "g"
            }
            if let index = exact {
                assignment[letter] = givens[index]
                used.insert(index)
                score += 3
            } else if id == "g" {
                assignment[letter] = Given(quantityID: "g", dimension: .acceleration, value: gravity, sourceText: "", isSI: true, isTabular: true)
            } else if let index = untyped {
                assignment[letter] = givens[index]
                used.insert(index)
                score += 2
            } else if let index = loose {
                assignment[letter] = givens[index]
                used.insert(index)
                score += 0
            } else if id == "c", let value = substance?.specificHeat {
                assignment[letter] = Given(quantityID: "c", dimension: .specificHeat, value: value, sourceText: "", isSI: true, isTabular: true)
            } else if id == "rho", let value = substance?.density {
                assignment[letter] = Given(quantityID: "rho", dimension: .density, value: value, sourceText: "", isSI: true, isTabular: true)
            } else {
                return nil
            }
        }

        // Все данные из условия должны быть использованы — иначе формула, скорее всего, не та.
        let unusedCount = givens.indices.filter { !used.contains($0) && givens[$0].quantityID != "g" }.count
        guard unusedCount == 0 else { return nil }
        guard !used.isEmpty else { return nil }

        guard let expr = try? MathParser.parse(form) else { return nil }
        let environment = assignment.mapValues { MathValue.approx($0.value) }
        guard let value = try? evaluator.evaluate(expr, environment), value.double.isFinite else { return nil }
        return Candidate(formula: formula, unknownLetter: unknownLetter, assignment: assignment, score: score, result: value.double)
    }

    // MARK: - Building the answer

    private func symbol(_ id: String) -> String {
        PhysicsData.quantityByID[id]?.symbol ?? id
    }

    private func givenLine(_ given: Given, id: String) -> String {
        guard let quantity = PhysicsData.quantityByID[id] else { return given.sourceText }
        let si = "\(fmt.approx(given.value)) \(quantity.unit(l))"
        if given.isTabular {
            return "\(quantity.symbol) = \(si)"
        }
        if given.isSI || given.sourceText.contains("=") {
            return "\(quantity.symbol) = \(given.sourceText)"
        }
        return "\(quantity.symbol) = \(given.sourceText) = \(si)"
    }

    private func buildSolution(_ candidate: Candidate, substance: Substance?, gravity: Double) -> Solution {
        let formula = candidate.formula
        let unknownID = formula.variables[candidate.unknownLetter] ?? ""
        let unknown = PhysicsData.quantityByID[unknownID]
        let unknownSymbol = unknown?.symbol ?? candidate.unknownLetter
        let unit = unknown?.unit(l) ?? ""

        var givenLines: [String] = []
        var tabularNotes: [String] = []
        for letter in candidate.assignment.keys.sorted() {
            guard let given = candidate.assignment[letter], let id = formula.variables[letter] else { continue }
            givenLines.append(givenLine(given, id: id))
            if given.isTabular {
                if id == "g" {
                    tabularNotes.append(l("g ≈ \(fmt.approx(gravity)) м/с² — ускорение свободного падения.", "g ≈ \(fmt.approx(gravity)) m/s² is the gravitational acceleration."))
                } else if let substance {
                    tabularNotes.append(
                        l(
                            "\(symbol(id)) — табличное значение для вещества «\(substance.nameRu)».",
                            "\(symbol(id)) is a table value for \(substance.nameEn)."))
                }
            }
        }

        // Формула в «настоящих» обозначениях: ρ, Eₖ, v₀.
        let symbolMap = formula.variables.mapValues { Expr.sym(symbol($0)) }
        let numberMap = candidate.assignment.mapValues { Expr.real($0.value) }
        let formText = formula.forms[candidate.unknownLetter] ?? ""
        let symbolic = (try? MathParser.parse(formText)).map { fmt.expr($0.substituting(symbolMap)) } ?? formText
        let numeric = (try? MathParser.parse(formText)).map { fmt.expr($0.substituting(numberMap)) } ?? ""
        let resultText = fmt.approx(candidate.result, significant: 4)

        var steps: [SolutionStep] = [
            SolutionStep(l("Дано", "Given"), l("Все величины переведены в единицы СИ.", "All quantities are converted to SI units."), formula: givenLines.joined(separator: "\n")),
            SolutionStep(l("Найти", "Find"), formula: "\(unknownSymbol) — ?"),
            SolutionStep(l("Формула", "Formula"), l("Используем формулу: \(formula.nameRu).", "We use the formula: \(formula.nameEn)."), formula: formula.display),
        ]
        let rearranged = "\(unknownSymbol) = \(symbolic)"
        if rearranged.replacingOccurrences(of: " ", with: "") != formula.display.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "·", with: "") {
            steps.append(SolutionStep(l("Выразим искомую величину", "Express the unknown"), formula: rearranged))
        }
        steps.append(
            SolutionStep(
                l("Подставим числа", "Substitute the numbers"),
                formula: "\(unknownSymbol) = \(numeric) ≈ \(resultText) \(unit)"))

        var answer = "\(unknownSymbol) ≈ \(resultText) \(unit)"
        if let friendly = friendlyUnit(candidate.result, dimension: unknown?.dimension) {
            answer += " = \(friendly)"
        }

        var notes = tabularNotes
        notes.append(
            l(
                "Условие интерпретировано автоматически — сверьте блок «Дано» с задачей. Решаются задачи в одну формулу.",
                "The problem was interpreted automatically — compare the “Given” block with the task. Single-formula problems are supported."
            ))
        return Solution(
            subject: .physics,
            problemType: l("Расчётная задача: \(formula.nameRu)", "Calculation: \(formula.nameEn)"),
            interpretedProblem: givenLines.joined(separator: "; ") + "; " + "\(unknownSymbol) — ?",
            answer: answer,
            explanation: l(
                "Записываем, что дано, переводим единицы в СИ, выбираем формулу, связывающую данные с искомой величиной, выражаем неизвестное и подставляем числа.",
                "Write down what is given, convert the units to SI, choose the formula that links the data to the unknown, express the unknown and substitute the numbers."
            ),
            steps: steps,
            formulas: [formula.display],
            reliability: .heuristic,
            engine: .physics,
            notes: notes)
    }

    /// Более привычная единица для больших и малых значений.
    private func friendlyUnit(_ value: Double, dimension: PhysicalDimension?) -> String? {
        guard let dimension else { return nil }
        let magnitude = abs(value)
        switch dimension {
        case .energy where magnitude >= 1e6: return "\(fmt.approx(value / 1e6, significant: 4)) \(l("МДж", "MJ"))"
        case .energy where magnitude >= 1e3: return "\(fmt.approx(value / 1e3, significant: 4)) \(l("кДж", "kJ"))"
        case .power where magnitude >= 1e3: return "\(fmt.approx(value / 1e3, significant: 4)) \(l("кВт", "kW"))"
        case .pressure where magnitude >= 1e3: return "\(fmt.approx(value / 1e3, significant: 4)) \(l("кПа", "kPa"))"
        case .force where magnitude >= 1e3: return "\(fmt.approx(value / 1e3, significant: 4)) \(l("кН", "kN"))"
        case .speed: return "\(fmt.approx(value * 3.6, significant: 4)) \(l("км/ч", "km/h"))"
        case .length where magnitude >= 1e3: return "\(fmt.approx(value / 1e3, significant: 4)) \(l("км", "km"))"
        case .time where magnitude >= 3600: return "\(fmt.approx(value / 3600, significant: 4)) \(l("ч", "h"))"
        case .time where magnitude >= 120: return "\(fmt.approx(value / 60, significant: 4)) \(l("мин", "min"))"
        default: return nil
        }
    }

    private func unsupported(givens: [Given], target: String?, ambiguous: Bool = false) -> Solution {
        let listed = givens.map { given -> String in
            if let id = given.quantityID, let quantity = PhysicsData.quantityByID[id] {
                return "\(quantity.symbol) = \(given.sourceText)"
            }
            return given.sourceText
        }.joined(separator: "; ")
        let reason =
            ambiguous
            ? l(
                "К этим данным подходят несколько формул с разными ответами, поэтому локальный решатель не стал угадывать. Распознанные величины: \(listed).",
                "Several formulas with different answers fit these data, so the local solver did not guess. Recognized quantities: \(listed).")
            : l(
                "В локальной базе нет одной формулы, которая связывает эти величины. Распознано: \(listed). Локальный решатель справляется с задачами в одно действие; для многошаговых задач нужна языковая модель.",
                "The local database has no single formula linking these quantities. Recognized: \(listed). The local solver handles one-step problems; multi-step problems need a language model."
            )
        var solution = Solution.unsupported(
            subject: .physics, problemType: l("Расчётная задача по физике", "Physics calculation"), reason: reason, engine: .physics)
        solution.interpretedProblem = listed
        return solution
    }

    // MARK: - Unit conversion

    /// «Переведите 72 км/ч в м/с».
    private func solveConversion(_ text: String) -> Solution? {
        let lower = text.lowercased()
        guard lower.containsAny(["перевед", "вырази", "преобраз", "convert", "express", "сколько будет"]) || Rx.contains("\\d\\s*\\S+\\s+(?:в|to|in)\\s+\\S+\\s*[?.]?\\s*$", in: lower)
        else { return nil }
        let pattern =
            "(\\d+(?:[.,]\\d+)?)\\s*(\(PhysicsSolver.unitPattern))\\s+(?:в|во|to|in|into)\\s+(\(PhysicsSolver.unitPattern))(?![a-zA-Zа-яА-ЯёЁ\\d/])"
        guard let match = Rx.first(pattern, in: text, caseInsensitive: false),
            let value = Double(match[1].replacingOccurrences(of: ",", with: ".")),
            let from = PhysicsSolver.unitBySymbol[match[2]], let to = PhysicsSolver.unitBySymbol[match[3]],
            from.dimension == to.dimension, from.dimension != .temperature
        else { return nil }

        let si = value * from.factor
        let result = si / to.factor
        let fromUnit = displayUnit(match[2])
        let toUnit = displayUnit(match[3])
        let ratio = from.factor / to.factor
        let steps = [
            SolutionStep(
                l("Соотношение единиц", "Unit relationship"),
                formula: "1 \(fromUnit) = \(fmt.approx(ratio, significant: 8)) \(toUnit)"),
            SolutionStep(
                l("Умножим на коэффициент", "Multiply by the factor"),
                formula: "\(fmt.approx(value, significant: 10)) \(fromUnit) = \(fmt.approx(value, significant: 10))·\(fmt.approx(ratio, significant: 8)) \(toUnit) = \(fmt.approx(result, significant: 8)) \(toUnit)"),
        ]
        return Solution(
            subject: .physics, problemType: l("Перевод единиц измерения", "Unit conversion"),
            interpretedProblem: "\(fmt.approx(value, significant: 10)) \(fromUnit) → \(toUnit)",
            answer: "\(fmt.approx(value, significant: 10)) \(fromUnit) = \(fmt.approx(result, significant: 8)) \(toUnit)",
            explanation: l(
                "Чтобы перевести величину в другие единицы, её умножают на коэффициент, показывающий, сколько новых единиц содержится в одной старой.",
                "To convert a quantity to other units, multiply it by the factor showing how many new units are in one old unit."),
            steps: steps, reliability: .exact, engine: .physics)
    }
}
