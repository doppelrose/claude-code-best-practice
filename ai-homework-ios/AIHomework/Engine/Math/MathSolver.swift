import Foundation

/// Фасад математического движка: по тексту задания определяет его тип,
/// вызывает нужный решатель и собирает объяснение.
///
/// Возвращает `nil`, если в тексте нет математической записи, которую движок умеет решать
/// (например, текстовая задача «У Маши 5 яблок…») — тогда решение ищут другие механизмы.
struct MathSolver: Sendable {
    let lang: AppLanguage
    private let l: L10n
    private let evaluator = MathEvaluator()

    init(lang: AppLanguage) {
        self.lang = lang
        l = L10n(lang)
    }

    private enum Intent {
        case derivative, integral, factor, simplify, zeros, auto
    }

    // MARK: - Entry point

    func solve(_ text: String) -> Solution? {
        // Нумерованный список заданий в одной строке — решаем каждый пункт отдельно (AUD-57).
        if let list = MathTextExtractor.numberedList(in: text), list.items.count >= 2,
            !list.intro.lowercased().containsAny(["систем", "system"]),
            let solution = solveList(intro: list.intro, items: list.items)
        {
            return solution
        }
        return solveSingle(text)
    }

    private func solveSingle(_ rawText: String) -> Solution? {
        let text = prepare(rawText)
        let lower = text.lowercased()
        if let solution = solvePercent(lower) { return solution }
        if let solution = solveDivisibility(lower) { return solution }
        if let refusal = refuseFunctionStudy(lower) { return refusal }

        let intent = detectIntent(lower)
        // Пределы определённого интеграла вырезаем до разбора: иначе «от 0 до 2 x^2 dx»
        // превращается в подынтегральное «2 x^2» (AUD-13).
        var extractionText = text
        var bounds: (lower: Rational, upper: Rational)?
        if intent == .integral, let found = definiteIntegralBounds(in: text) {
            bounds = (found.lower, found.upper)
            extractionText = found.remainder
        }
        let fragments = MathTextExtractor.fragments(in: extractionText)
        let candidates = fragments.filter { isMeaningful($0, explicitIntent: intent != .auto) }
        guard !candidates.isEmpty else { return nil }

        // Одинокое «10 %» из текстовой задачи — не задание, а кусок условия (AUD-10).
        if intent == .auto, candidates.allSatisfy({ Rx.contains("^\\s*[+-]?\\s*\\d+(?:[.,]\\d+)?\\s*%\\s*$", in: $0) }),
            lower.contains(where: { $0.isLetter })
        {
            return failure(
                .unsupported(
                    detail: l(
                        "Похоже на текстовую задачу на проценты, которую точный алгоритм не узнал. Запишите её одним действием (например, «15% от 200») или решите с нейросетью.",
                        "This looks like a percentage word problem that the exact algorithm did not recognize. Write it as a single operation (e.g. “15% of 200”) or solve it with the AI model."
                    )), interpreted: candidates[0])
        }

        let preferDecimals = candidates.contains { Rx.contains("\\d[.,]\\d", in: $0) }
        let fmt = MathFormatter(lang: lang, preferDecimals: preferDecimals)
        let hintVariable = fragments.first { $0.count == 1 && ($0.first?.isLetter ?? false) }

        var solution: Solution
        do {
            solution = try dispatch(
                candidates: candidates, intent: intent, lower: lower, fmt: fmt, hintVariable: hintVariable, bounds: bounds)
        } catch let error as MathError {
            return failure(error, interpreted: candidates.first ?? "")
        } catch {
            return failure(.unsupported(detail: l("Не удалось решить задание.", "Could not solve the problem.")), interpreted: candidates.first ?? "")
        }

        // Числа из условия, не вошедшие ни в одно выражение, — признак того, что решено не всё (AUD-10).
        if solution.isSolved, intent == .auto || intent == .simplify {
            let unused = fragments.filter { fragment in
                !candidates.contains(fragment) && fragment.contains(where: { $0.isNumber })
            }
            if !unused.isEmpty {
                solution.notes.append(
                    l(
                        "В условии есть числа, которые не вошли в решение (\(unused.joined(separator: ", "))). Проверьте, что решено именно то, что спрашивается.",
                        "The problem contains numbers that were not used in the solution (\(unused.joined(separator: ", "))). Check that the right thing was solved."
                    ))
                solution.reliability = .heuristic
            }
        }
        return finalize(solution, original: rawText)
    }

    /// Предварительная чистка текста задания: номер задания, разделители тысяч, индексы переменных.
    private func prepare(_ text: String) -> String {
        var result = MathSolver.stripTaskNumber(text)
        if lang == .en {
            result = MathSolver.removeEnglishThousandsSeparators(result)
        }
        return MathNormalizer.subscriptIndexedVariables(result)
    }

    /// Номер задания в начале — не данные: «3. Найдите НОД…», «№ 12. Разложите…», «12) …», «Задание 7.» (AUD-09).
    static func stripTaskNumber(_ text: String) -> String {
        let pattern =
            "^\\s*(?:(?:№|#)\\s*\\d+[a-zа-я]?\\s*[.):]?|\\d+\\s*[.)]|(?:задани[еяю]|задача|упражнение|номер|exercise|task|problem)\\s*№?\\s*\\d+[a-zа-я]?\\s*[.):]?)\\s+"
        return Rx.replace(pattern, in: text, with: "")
    }

    /// «1,500» в английском тексте — это тысяча пятьсот, а не полтора (AUD-33).
    static func removeEnglishThousandsSeparators(_ text: String) -> String {
        var result = text
        let matches = Rx.ranges("(?<![\\d.,])\\d{1,3}(?:,\\d{3})+(?![\\d]|,\\d)", in: text)
        for match in matches.reversed() {
            guard let range = match[0] else { continue }
            result.replaceSubrange(range, with: text[range].replacingOccurrences(of: ",", with: ""))
        }
        return result
    }

    /// Пометки об исправлениях распознавания и понижение метки до «эвристики».
    private func finalize(_ solution: Solution, original: String) -> Solution {
        var result = solution
        if MathNormalizer.readsTimesAsVariable(original) {
            result.notes.insert(timesSignNote, at: 0)
        }
        if result.isSolved, result.reliability == .exact || result.reliability == .approximate,
            result.notes.contains(where: { $0 == timesSignNote || $0 == assumedPowerText })
        {
            result.reliability = .heuristic
        }
        return result
    }

    private var timesSignNote: String {
        l(
            "Знак «×» прочитан как переменная x — распознавание часто путает их. Если это не так, исправьте распознанный текст.",
            "The “×” sign was read as the variable x — recognition often confuses them. If that is wrong, edit the recognized text.")
    }

    /// Нумерованный список: каждый пункт решается отдельно, ответы собираются вместе.
    private func solveList(intro: String, items: [String]) -> Solution? {
        var parts: [Solution] = []
        for item in items.prefix(10) {
            guard let part = solveSingle(intro.isEmpty ? item : intro + " " + item) else { return nil }
            parts.append(part)
        }
        guard parts.contains(where: { $0.isSolved }) else { return parts.first }
        var answers: [String] = []
        var steps: [SolutionStep] = []
        var notes: [String] = []
        var explanations: [String] = []
        var reliability: SolutionReliability = .exact
        for (index, part) in parts.enumerated() {
            let label = "\(index + 1))"
            if part.isSolved {
                answers.append("\(label) \(part.answer)")
            } else {
                answers.append("\(label) —")
                notes.append(l("Пункт \(index + 1) не решён: \(part.explanation)", "Item \(index + 1) is not solved: \(part.explanation)"))
                reliability = .heuristic
            }
            steps.append(SolutionStep(l("Пункт \(index + 1)", "Item \(index + 1)"), formula: part.interpretedProblem))
            steps.append(contentsOf: part.steps.map { SolutionStep("\(label) \($0.title)", $0.detail, formula: $0.formula) })
            notes.append(contentsOf: part.notes.map { "\(label) \($0)" })
            if part.isSolved, !explanations.contains(part.explanation) { explanations.append(part.explanation) }
            switch part.reliability {
            case .heuristic: reliability = .heuristic
            case .approximate where reliability == .exact: reliability = .approximate
            default: break
            }
        }
        return Solution(
            subject: .math, problemType: l("Несколько заданий", "Several problems"),
            interpretedProblem: parts.enumerated().map { "\($0.offset + 1)) \($0.element.interpretedProblem)" }.joined(separator: "; "),
            answer: answers.joined(separator: "; "), explanation: explanations.joined(separator: "\n"), steps: steps,
            formulas: Array(Set(parts.flatMap { $0.formulas })).sorted(), reliability: reliability, engine: .math, notes: notes)
    }

    private func failure(_ error: MathError, interpreted: String) -> Solution {
        var solution = Solution.unsupported(
            subject: .math,
            problemType: l("Математика", "Math"),
            reason: error.message(l),
            engine: .math)
        solution.interpretedProblem = interpreted
        return solution
    }

    // MARK: - Classification

    private func detectIntent(_ lower: String) -> Intent {
        if lower.containsAny(["производн", "derivative", "differentiate", "d/dx", "продифференц"]) { return .derivative }
        if lower.containsAny(["интеграл", "первообразн", "integral", "integrate", "antiderivative", "∫"]) { return .integral }
        if lower.containsAny(["нули функции", "нуль функции", "нулей функции", "корни функции", "zeros of", "zeroes of", "roots of the function"]) {
            return .zeros
        }
        if lower.containsAny(["множител", "factor"]) && !lower.containsAny(["простые множ", "prime factor"]) { return .factor }
        if lower.containsAny(["упрост", "simplif", "раскр", "expand", "приведите подобн", "привести подобн", "сократ"]) { return .simplify }
        return .auto
    }

    /// Задания «про функцию», которые точный алгоритм не решает: график, наибольшее значение,
    /// чётность, область определения… Лучше честно отказать, чем выдать ответ на другой вопрос (AUD-11).
    private func refuseFunctionStudy(_ lower: String) -> Solution? {
        let graph = Rx.contains("график(?!ическ)|(?<![a-z])(?:graph|plot|sketch)", in: lower)
        let study = lower.containsAny([
            "наибольш", "наименьш", "максимальн", "минимальн", "экстремум", "точки максимума", "точки минимума",
            "чётн", "четн", "област", "множество значений", "монотонн", "возраста", "убыва", "асимптот",
            "периодичн", "исследу", "maximum", "minimum", "extrem", "domain", "range of", "parity", "even or odd",
            "increasing", "decreasing", "asymptot",
        ])
        let aboutFunction = lower.containsAny(["функци", "function"])
        guard graph || (study && aboutFunction) else { return nil }
        var solution = Solution.unsupported(
            subject: .math, problemType: l("Исследование функции", "Studying a function"),
            reason: l(
                "Построение графика и исследование функции (наибольшее и наименьшее значения, чётность, область определения, промежутки монотонности) точный алгоритм на устройстве не выполняет. Чтобы не выдать ответ на другой вопрос, задание передаётся нейросети.",
                "Graphing and studying a function (maximum and minimum values, parity, domain, monotonicity) is not done by the exact on-device algorithm. To avoid answering a different question, the task is left to the AI model."
            ), engine: .math)
        solution.interpretedProblem = MathTextExtractor.fragments(in: lower).first ?? ""
        return solution
    }

    /// «от a до b» / «from a to b»: пределы и текст без них.
    private func definiteIntegralBounds(in text: String) -> (lower: Rational, upper: Rational, remainder: String)? {
        let normalized = MathNormalizer.normalize(text)
        let number = "(-?\\s*\\d+(?:[.,]\\d+)?)"
        let pattern = "(?<![а-яa-z])(?:от|from)\\s+\(number)\\s+(?:до|to)\\s+\(number)(?![\\d.,]*\\d)"
        guard let match = Rx.ranges(pattern, in: normalized).first, let whole = match[0], let a = match[1], let b = match[2],
            let low = signedNumber(String(normalized[a])), let high = signedNumber(String(normalized[b]))
        else { return nil }
        var remainder = normalized
        remainder.replaceSubrange(whole, with: " ")
        return (low, high, remainder)
    }

    private func signedNumber(_ text: String) -> Rational? {
        let compact = text.replacingOccurrences(of: " ", with: "")
        let negative = compact.hasPrefix("-")
        guard let value = Rational(decimal: negative ? String(compact.dropFirst()) : compact) else { return nil }
        return negative ? value.negated : value
    }

    private static let functionWords = ["sin", "cos", "tg", "tan", "ctg", "cot", "ln", "lg", "log", "sqrt", "abs", "exp", "arc"]

    /// Есть ли во фрагменте настоящая операция (а не просто число или буква).
    private func isMeaningful(_ fragment: String, explicitIntent: Bool) -> Bool {
        let operators = Set("+-*/^=<>≤≥≠√∛|!%:²³⁴⁵⁶⁷⁸⁹")
        if fragment.contains(where: { operators.contains($0) }) { return true }
        let lower = fragment.lowercased()
        if MathSolver.functionWords.contains(where: { lower.contains($0) }) { return true }
        if fragment.contains("(") && fragment.contains(where: { $0.isNumber }) { return true }
        // При явной просьбе («найдите производную 5x») годится и простой одночлен.
        return explicitIntent && fragment.count > 1 && fragment.contains(where: { $0.isLetter })
    }

    private func hasRelation(_ fragment: String) -> Bool {
        fragment.contains(where: { "=<>≤≥≠".contains($0) }) || fragment.contains("<=") || fragment.contains(">=")
    }

    /// Убираем запись функции: «f(x) = …», «y = …».
    private func stripFunctionPrefix(_ fragment: String) -> (body: String, variable: String?, name: String?) {
        if let match = Rx.first("^\\s*([a-zA-Z])\\s*\\(\\s*([a-zA-Z])\\s*\\)\\s*=\\s*(.+)$", in: fragment) {
            return (match[3], match[2], match[1])
        }
        if let match = Rx.first("^\\s*y\\s*=\\s*(.+)$", in: fragment), !hasRelation(match[1]) {
            return (match[1], nil, "y")
        }
        return (fragment, nil, nil)
    }

    private func chooseVariable(_ variables: Set<String>, hint: String?, lower: String) -> String? {
        if let match = Rx.first("(?:относительно|for|найдите|найти|find)\\s+([a-zа-я])(?![a-zа-я])", in: lower) {
            let letter = MathNormalizer.latinizeLookalikes(match[1])
            if variables.contains(letter) { return letter }
        }
        if let hint, variables.contains(hint) { return hint }
        for preferred in ["x", "y", "z", "t"] where variables.contains(preferred) {
            return preferred
        }
        return variables.sorted().first
    }

    // MARK: - Dispatch

    /// «x₀ = 2», «x = 3» — задание точки или значения, а не выражение для решения.
    private func isAssignment(_ fragment: String) -> Bool {
        Rx.contains("^\\s*[a-z][₀0]?\\s*=\\s*-?\\s*\\d+(?:[.,]\\d+)?\\s*$", in: fragment)
    }

    /// Пометка «решена только часть»: в условии несколько выражений.
    private func partialNote() -> String {
        l(
            "В тексте найдено несколько выражений — решено первое. Чтобы решить другое, выделите на фото только нужную часть задания.",
            "Several expressions were found — the first one was solved. To solve another, select only the needed part of the photo.")
    }

    private func markPartial(_ solution: Solution, if partial: Bool) -> Solution {
        guard partial else { return solution }
        var result = solution
        result.notes.append(partialNote())
        if result.isSolved { result.reliability = .heuristic }
        return result
    }

    private func dispatch(
        candidates: [String], intent: Intent, lower: String, fmt: MathFormatter, hintVariable: String?,
        bounds: (lower: Rational, upper: Rational)?
    ) throws -> Solution {
        let relational = candidates.filter { hasRelation($0) }
        let expressions = candidates.filter { !hasRelation($0) }

        switch intent {
        case .derivative:
            let targets = candidates.filter { !isAssignment($0) }
            let stripped = stripFunctionPrefix(targets.first ?? candidates[0])
            let solution = try solveDerivative(
                stripped.body, variableHint: stripped.variable ?? hintVariable, functionName: stripped.name, lower: lower, fmt: fmt)
            return markPartial(solution, if: targets.count > 1)
        case .integral:
            let targets = candidates.filter { !isAssignment($0) }
            let stripped = stripFunctionPrefix(targets.first ?? candidates[0])
            let solution = try solveIntegral(stripped.body, variableHint: stripped.variable ?? hintVariable, bounds: bounds, fmt: fmt)
            return markPartial(solution, if: targets.count > 1)
        case .zeros:
            // «Нули функции f(x) = …» — это корни уравнения f(x) = 0 (AUD-11).
            if let definition = candidates.first(where: { stripFunctionPrefix($0).name != nil }) {
                let stripped = stripFunctionPrefix(definition)
                var solution = try solveRelational(stripped.body + " = 0", lower: lower, fmt: fmt, hintVariable: stripped.variable ?? hintVariable)
                solution.problemType = l("Нули функции", "Zeros of a function")
                solution.explanation =
                    l("Нули функции — значения аргумента, при которых функция равна нулю, поэтому решаем уравнение f(x) = 0. ",
                      "The zeros of a function are the argument values where it equals zero, so we solve f(x) = 0. ")
                    + solution.explanation
                return markPartial(solution, if: candidates.count > 1)
            }
        case .factor:
            if let expression = expressions.first {
                return try solveFactor(expression, fmt: fmt)
            }
        case .simplify, .auto:
            break
        }

        // «Найдите значение выражения … при x = 5».
        if let solution = try solveSubstitution(candidates: candidates, lower: lower, fmt: fmt) {
            return solution
        }

        // Система: несколько уравнений с несколькими неизвестными.
        let equations = relational.filter { !$0.contains(where: { "<>≤≥≠".contains($0) }) }
        if equations.count >= 2 {
            var parsed: [(lhs: Expr, rhs: Expr)] = []
            for equation in equations {
                let statement = try MathParser.parseStatement(equation).statement
                if statement.sides.count == 2 { parsed.append((statement.sides[0], statement.sides[1])) }
            }
            let variables = parsed.reduce(into: Set<String>()) { $0.formUnion($1.lhs.variables.union($1.rhs.variables)) }
            if parsed.count >= 2, variables.count >= 2 {
                let outcome = try SystemSolver(lang: lang, formatter: fmt).solve(parsed)
                return Solution(
                    subject: .math, problemType: outcome.kindTitle,
                    interpretedProblem: parsed.map { "\(fmt.expr($0.lhs)) = \(fmt.expr($0.rhs))" }.joined(separator: "; "),
                    answer: outcome.answer, explanation: outcome.explanation, steps: outcome.steps,
                    reliability: outcome.isApproximate ? .approximate : .exact, engine: .math, notes: outcome.notes)
            }
        }

        let partial = relational.count + expressions.count > 1

        if let fragment = relational.first, intent == .auto || expressions.isEmpty {
            return markPartial(try solveRelational(fragment, lower: lower, fmt: fmt, hintVariable: hintVariable), if: partial)
        }

        guard let fragment = expressions.first else {
            throw MathError.unsupported(detail: l("Не найдено выражение для решения.", "No expression to solve was found."))
        }
        return markPartial(try solveExpression(fragment, intent: intent, fmt: fmt), if: partial)
    }

    private var assumedPowerText: String {
        l(
            "Цифра вплотную после переменной или скобки («x2», «(x+1)2») прочитана как степень: x², (x+1)². Распознавание часто теряет верхний индекс. Если это не так — исправьте распознанный текст.",
            "A digit right after a variable or a bracket (“x2”, “(x+1)2”) was read as a power: x², (x+1)². Recognition often loses superscripts. If that is wrong, edit the recognized text."
        )
    }

    /// Оговорки об эвристиках разбора: о каждой исправленной записи нужно сказать пользователю.
    private func heuristicNotes(_ heuristics: MathParser.Heuristics) -> [String] {
        var notes: [String] = []
        if heuristics.assumedPowers { notes.append(assumedPowerText) }
        if heuristics.mixedNumbers {
            notes.append(l("Запись «1 1/2» понята как смешанное число: 1 1/2 = 1 + 1/2.", "“1 1/2” was read as a mixed number: 1 1/2 = 1 + 1/2."))
        }
        if heuristics.colonFractions {
            notes.append(
                l(
                    "Дробь рядом со знаком «:» понята как одно число, как принято в школе: 2/3 : 4/9 = (2/3) : (4/9).",
                    "A fraction next to “:” was read as a single number, as is usual at school: 2/3 : 4/9 = (2/3) : (4/9)."))
        }
        return notes
    }

    // MARK: - Equations and inequalities

    private func solveRelational(_ fragment: String, lower: String, fmt: MathFormatter, hintVariable: String?) throws -> Solution {
        // «f(x) = …» без просьбы решить — это задание функции, а не уравнение.
        let stripped = stripFunctionPrefix(fragment)
        if stripped.name != nil, stripped.variable != nil, !hasRelation(stripped.body) {
            var solution = try solveExpression(stripped.body, intent: .auto, fmt: fmt)
            solution.notes.append(
                l(
                    "Запись «\(stripped.name ?? "f")(\(stripped.variable ?? "x")) = …» понята как задание функции; показано упрощение её правой части.",
                    "“\(stripped.name ?? "f")(\(stripped.variable ?? "x")) = …” was read as a function definition; its right-hand side is simplified."
                ))
            return solution
        }

        let parsed = try MathParser.parseStatement(fragment)
        let statement = parsed.statement
        let notes = heuristicNotes(parsed.heuristics)
        let interpreted = fmt.statement(statement)

        if statement.relations.count == 2 {
            return try solveDoubleInequality(statement, fmt: fmt, lower: lower, hint: hintVariable, notes: notes)
        }
        guard statement.relations.count == 1, statement.sides.count == 2 else {
            throw MathError.unsupported(
                detail: l("Цепочки из нескольких знаков сравнения не поддерживаются.", "Chains of several relation signs are not supported."))
        }
        let relation = statement.relations[0]
        let (lhs, rhs) = (statement.sides[0], statement.sides[1])

        guard let variable = chooseVariable(statement.variables, hint: hintVariable, lower: lower) else {
            return try solveNumericComparison(lhs: lhs, rhs: rhs, relation: relation, fmt: fmt, interpreted: interpreted)
        }

        if relation == .eq {
            let outcome = try EquationSolver(lang: lang, formatter: fmt).solve(lhs: lhs, rhs: rhs, variable: variable)
            return Solution(
                subject: .math, problemType: outcome.kindTitle, interpretedProblem: interpreted,
                answer: outcome.answer, explanation: outcome.explanation, steps: outcome.steps, formulas: outcome.formulas,
                reliability: outcome.isApproximate ? .approximate : .exact, engine: .math, notes: notes + outcome.notes)
        }
        // «≠» решает InequalitySolver: подходят все точки, кроме корней соответствующего уравнения.
        guard relation.isInequality || relation == .ne else {
            throw MathError.unsupported(detail: l("Этот знак сравнения не поддерживается.", "This comparison sign is not supported."))
        }
        let outcome = try InequalitySolver(lang: lang, formatter: fmt).solve(lhs: lhs, rhs: rhs, relation: relation, variable: variable)
        return Solution(
            subject: .math, problemType: outcome.kindTitle, interpretedProblem: interpreted,
            answer: outcome.answer, explanation: outcome.explanation, steps: outcome.steps,
            reliability: outcome.isApproximate ? .approximate : .exact, engine: .math, notes: notes + outcome.notes)
    }

    /// `a < kx + c < b` — решаем как пересечение двух линейных неравенств.
    private func solveDoubleInequality(_ statement: MathStatement, fmt: MathFormatter, lower: String, hint: String?, notes: [String]) throws -> Solution {
        let unsupported = MathError.unsupported(
            detail: l(
                "Двойные неравенства поддерживаются только вида a < kx + c < b.",
                "Double inequalities are supported only in the form a < kx + c < b."))
        let (r1, r2) = (statement.relations[0], statement.relations[1])
        let ascending = (r1 == .lt || r1 == .le) && (r2 == .lt || r2 == .le)
        let descending = (r1 == .gt || r1 == .ge) && (r2 == .gt || r2 == .ge)
        guard ascending || descending, let x = chooseVariable(statement.variables, hint: hint, lower: lower),
            let low = try Algebra.polynomial(statement.sides[0])?.constantValue,
            let high = try Algebra.polynomial(statement.sides[2])?.constantValue,
            let middle = try Algebra.polynomial(statement.sides[1]), middle.totalDegree == 1,
            let coefficients = middle.coefficients(in: x)
        else { throw unsupported }

        let (k, c) = (coefficients[1], coefficients[0])
        var steps: [SolutionStep] = [SolutionStep(l("Запишем двойное неравенство", "Write the double inequality"), formula: fmt.statement(statement))]
        var left = try low - c
        var right = try high - c
        var (leftRelation, rightRelation) = (r1, r2)
        if !c.isZero {
            steps.append(
                SolutionStep(
                    l("Вычтем \(fmt.rational(c)) из всех трёх частей", "Subtract \(fmt.rational(c)) from all three parts"),
                    formula:
                        "\(fmt.rational(left)) \(r1.rawValue) \(fmt.polynomial(Polynomial(coefficients: [.zero, k], variable: x))) \(r2.rawValue) \(fmt.rational(right))"
                ))
        }
        left = try left / k
        right = try right / k
        if k.isNegative {
            leftRelation = leftRelation.flipped
            rightRelation = rightRelation.flipped
        }
        if k != .one {
            steps.append(
                SolutionStep(
                    l("Разделим все части на \(fmt.rational(k))", "Divide all parts by \(fmt.rational(k))"),
                    k.isNegative
                        ? l("Делим на отрицательное число — оба знака меняются на противоположные.", "Dividing by a negative number reverses both signs.")
                        : "",
                    formula: "\(fmt.rational(left)) \(leftRelation.rawValue) \(x) \(rightRelation.rawValue) \(fmt.rational(right))"))
        }
        // Приводим к виду меньшее < x < большее.
        var lowerBound = left
        var upperBound = right
        var lowerClosed = leftRelation == .le
        var upperClosed = rightRelation == .le
        if leftRelation == .gt || leftRelation == .ge {
            lowerBound = right
            upperBound = left
            lowerClosed = rightRelation == .ge
            upperClosed = leftRelation == .ge
        }
        let answer: String
        if lowerBound > upperBound || (lowerBound == upperBound && !(lowerClosed && upperClosed)) {
            answer = l("Нет решений", "No solutions")
        } else {
            answer =
                "\(fmt.rational(lowerBound)) \(lowerClosed ? "≤" : "<") \(x) \(upperClosed ? "≤" : "<") \(fmt.rational(upperBound))"
                + l(", то есть ", ", i.e. ")
                + "\(x) ∈ \(lowerClosed ? "[" : "(")\(fmt.rational(lowerBound)); \(fmt.rational(upperBound))\(upperClosed ? "]" : ")")"
        }
        return Solution(
            subject: .math, problemType: l("Двойное неравенство", "Double inequality"),
            interpretedProblem: fmt.statement(statement), answer: answer,
            explanation: l(
                "С двойным неравенством работают как с обычным, выполняя одно и то же действие сразу над всеми тремя частями.",
                "A double inequality is handled like a regular one, applying the same operation to all three parts at once."),
            steps: steps, reliability: .exact, engine: .math, notes: notes)
    }

    /// Числовое равенство или сравнение без переменных: проверяем, верно ли оно.
    private func solveNumericComparison(lhs: Expr, rhs: Expr, relation: Relation, fmt: MathFormatter, interpreted: String) throws -> Solution {
        let left = try evaluator.evaluate(lhs)
        let right = try evaluator.evaluate(rhs)
        let difference = left.double - right.double
        let sign: Int
        if left.isExact, right.isExact, left == right {
            sign = 0
        } else {
            sign = abs(difference) <= 1e-12 * max(1, abs(left.double)) ? 0 : (difference > 0 ? 1 : -1)
        }
        let holds = relation.holds(sign: sign)
        let actual = sign == 0 ? "=" : (sign > 0 ? ">" : "<")
        let steps = [
            SolutionStep(l("Вычислим левую часть", "Evaluate the left side"), formula: "\(fmt.expr(lhs)) = \(fmt.valueWithApproximation(left))"),
            SolutionStep(l("Вычислим правую часть", "Evaluate the right side"), formula: "\(fmt.expr(rhs)) = \(fmt.valueWithApproximation(right))"),
            SolutionStep(l("Сравним результаты", "Compare the results"), formula: "\(fmt.value(left)) \(actual) \(fmt.value(right))"),
        ]
        return Solution(
            subject: .math, problemType: l("Проверка числового равенства", "Checking a numeric statement"),
            interpretedProblem: interpreted,
            answer: holds ? l("Верно", "True") : l("Неверно: \(fmt.value(left)) \(actual) \(fmt.value(right))", "False: \(fmt.value(left)) \(actual) \(fmt.value(right))"),
            explanation: l(
                "В записи нет неизвестных, поэтому достаточно вычислить обе части и сравнить их.",
                "There are no unknowns, so it is enough to evaluate both sides and compare them."),
            steps: steps, reliability: left.isExact && right.isExact ? .exact : .approximate, engine: .math)
    }

    // MARK: - Expressions

    private func solveExpression(_ fragment: String, intent: Intent, fmt: MathFormatter) throws -> Solution {
        let parsed = try MathParser.parseDetailed(fragment)
        let expr = parsed.expr
        let notes = heuristicNotes(parsed.heuristics)
        if expr.isConstant {
            return try solveArithmetic(expr, fmt: fmt, notes: notes)
        }
        return try solveSimplification(expr, fmt: fmt, notes: notes, explicitRequest: intent == .simplify)
    }

    /// Точный целый ответ длинной арифметикой, когда 64 бит не хватает: `2^100`, `10^20 + 1` (AUD-59).
    private func exactIntegerSolution(_ expr: Expr, fmt: MathFormatter, notes: [String], environmentNote: String?) throws -> Solution? {
        guard let big = try evaluator.exactInteger(expr) else { return nil }
        let text = big.isNegative ? MathFormatter.minus + big.magnitude.description : big.description
        var steps: [SolutionStep] = []
        if let environmentNote {
            steps.append(SolutionStep(l("Подставим значения", "Substitute the values"), formula: environmentNote))
        }
        let approximation = Double(big.description).flatMap { $0.isFinite ? "≈ " + fmt.approx($0) : nil } ?? ""
        steps.append(
            SolutionStep(
                l("Вычислим точно", "Compute exactly"),
                l(
                    "Число не помещается в обычную точность калькулятора, поэтому действия выполнены «в столбик» — без округления. \(approximation)",
                    "The number exceeds ordinary calculator precision, so the operations were done digit by digit, without rounding. \(approximation)"
                ).trimmed,
                formula: "\(fmt.expr(expr)) = \(text)"))
        return Solution(
            subject: .math, problemType: l("Значение выражения", "Value of an expression"),
            interpretedProblem: fmt.expr(expr), answer: text,
            explanation: l(
                "Порядок действий: сначала выражения в скобках и функции, затем возведение в степень, потом умножение и деление слева направо, в конце — сложение и вычитание.",
                "Order of operations: brackets and functions first, then powers, then multiplication and division from left to right, and finally addition and subtraction."
            ),
            steps: steps, reliability: .exact, engine: .math, notes: notes)
    }

    /// `sin(30)` без «°» — в школе почти всегда градусы: показываем и это значение (AUD-60).
    private func degreeNotes(_ expr: Expr, fmt: MathFormatter, depth: Int = 0) -> [String] {
        guard depth < MathParser.maxTreeDepth else { return [] }
        switch expr {
        case .num, .real, .sym, .const:
            return []
        case .neg(let inner):
            return degreeNotes(inner, fmt: fmt, depth: depth + 1)
        case .bin(_, let a, let b):
            return degreeNotes(a, fmt: fmt, depth: depth + 1) + degreeNotes(b, fmt: fmt, depth: depth + 1)
        case .fn(let f, let args):
            var notes = args.flatMap { degreeNotes($0, fmt: fmt, depth: depth + 1) }
            let tabular: Set<Int> = [15, 30, 45, 60, 75, 90, 120, 135, 150, 180, 210, 225, 240, 270, 300, 315, 330, 360]
            if [.sin, .cos, .tan, .cot].contains(f), args.count == 1, case .num(let r) = args[0], r.isInteger,
                tabular.contains(abs(r.num))
            {
                let call = "\(f.displayName)(\(fmt.rational(r)))"
                let inDegrees = "\(f.displayName) \(fmt.rational(r))°"
                if let value = try? evaluator.evaluate(.fn(f, [.fn(.deg, [.num(r)])])) {
                    notes.append(
                        l(
                            "Аргумент \(call) понят в радианах. Если угол задан в градусах, то \(inDegrees) = \(fmt.valueWithApproximation(value)).",
                            "The argument of \(call) was read in radians. If the angle is in degrees, \(inDegrees) = \(fmt.valueWithApproximation(value))."
                        ))
                } else {
                    notes.append(
                        l("Аргумент \(call) понят в радианах; в градусах \(inDegrees) не определён.",
                          "The argument of \(call) was read in radians; in degrees \(inDegrees) is undefined."))
                }
            }
            return notes
        }
    }

    private func solveArithmetic(_ expr: Expr, fmt: MathFormatter, notes rawNotes: [String], environmentNote: String? = nil) throws -> Solution {
        let notes = rawNotes + degreeNotes(expr, fmt: fmt)
        let value: MathValue
        let evaluationSteps: [EvaluationStep]
        do {
            (value, evaluationSteps) = try evaluator.evaluateWithSteps(expr)
        } catch MathError.overflow {
            if let exact = try exactIntegerSolution(expr, fmt: fmt, notes: notes, environmentNote: environmentNote) { return exact }
            throw MathError.overflow
        }
        if !value.isExact, let exact = (try? exactIntegerSolution(expr, fmt: fmt, notes: notes, environmentNote: environmentNote)) ?? nil {
            return exact
        }
        var steps: [SolutionStep] = []
        if let environmentNote {
            steps.append(SolutionStep(l("Подставим значения", "Substitute the values"), formula: environmentNote))
        }
        var actionNumber = 0
        for step in evaluationSteps {
            let operation = fmt.expr(step.operation)
            let result = fmt.value(step.result)
            guard operation != result else { continue }
            actionNumber += 1
            var detail = ""
            // Сложение дробей с разными знаменателями — показываем общий знаменатель.
            if case .bin(let op, .num(let a), .num(let b)) = step.operation, op == .add || op == .sub,
                !a.isInteger || !b.isInteger, a.den != b.den, !fmt.preferDecimals,
                let common = try? Rational.lcm(a.den, b.den)
            {
                let left = "\(fmt.integer(a.num * (common / a.den)))/\(common)"
                let right = "\(fmt.integer(abs(b.num) * (common / b.den)))/\(common)"
                let sign = (op == .add) == !b.isNegative ? "+" : "−"
                detail = l(
                    "Общий знаменатель \(common): \(left) \(sign) \(right).",
                    "Common denominator \(common): \(left) \(sign) \(right).")
            }
            let relation = step.result.isExact ? "=" : "≈"
            steps.append(
                SolutionStep(l("Действие \(actionNumber)", "Step \(actionNumber)"), detail, formula: "\(operation) \(relation) \(result)"))
        }
        if steps.isEmpty {
            steps.append(SolutionStep(l("Вычислим", "Evaluate"), formula: "\(fmt.expr(expr)) = \(fmt.value(value))"))
        }
        let answer = fmt.valueWithApproximation(value)
        return Solution(
            subject: .math,
            problemType: l("Значение выражения", "Value of an expression"),
            interpretedProblem: fmt.expr(expr),
            answer: answer,
            explanation: l(
                "Порядок действий: сначала выражения в скобках и функции, затем возведение в степень, потом умножение и деление слева направо, в конце — сложение и вычитание.",
                "Order of operations: brackets and functions first, then powers, then multiplication and division from left to right, and finally addition and subtraction."
            ),
            steps: steps,
            reliability: value.isExact ? .exact : .approximate,
            engine: .math,
            notes: notes)
    }

    /// Слагаемые верхнего уровня со знаками.
    private func topLevelTerms(_ expr: Expr) -> [(negative: Bool, term: Expr)] {
        switch expr {
        case .bin(.add, let a, let b):
            return topLevelTerms(a) + topLevelTerms(b)
        case .bin(.sub, let a, let b):
            return topLevelTerms(a) + topLevelTerms(b).map { (!$0.negative, $0.term) }
        case .neg(let inner):
            return topLevelTerms(inner).map { (!$0.negative, $0.term) }
        default:
            return [(false, expr)]
        }
    }

    private func solveSimplification(_ expr: Expr, fmt: MathFormatter, notes: [String], explicitRequest: Bool) throws -> Solution {
        let original = fmt.expr(expr)
        var steps: [SolutionStep] = [SolutionStep(l("Запишем выражение", "Write the expression"), formula: original)]
        let resultText: String
        var explanation = l(
            "Раскрываем скобки, перемножаем и приводим подобные слагаемые — те, у которых одинаковая буквенная часть.",
            "Expand the brackets, multiply and combine like terms — the ones with the same variable part.")

        if let function = try Algebra.rationalFunction(expr) {
            // Раскрытие скобок в каждом слагаемом отдельно.
            var expansions: [String] = []
            let terms = topLevelTerms(expr)
            if terms.count > 1 {
                for item in terms {
                    guard let polynomial = try Algebra.polynomial(item.term) else { continue }
                    let before = fmt.expr(item.term)
                    let after = fmt.polynomial(polynomial)
                    if before != after { expansions.append("\(before) = \(after)") }
                }
            }
            if !expansions.isEmpty {
                steps.append(
                    SolutionStep(
                        l("Раскроем скобки в каждом слагаемом", "Expand the brackets in each term"),
                        formula: expansions.joined(separator: "\n")))
            }
            let reduced = try function.reduced()
            if let polynomial = try reduced.asPolynomial() {
                resultText = fmt.polynomial(polynomial)
                steps.append(
                    SolutionStep(
                        function.isPolynomial
                            ? l("Приведём подобные слагаемые", "Combine like terms")
                            : l("Сократим дробь и приведём подобные", "Cancel the fraction and combine like terms"),
                        formula: resultText))
            } else {
                resultText = "\(fmt.polynomialFactor(reduced.numerator))/\(fmt.polynomialFactor(reduced.denominator))"
                steps.append(
                    SolutionStep(
                        l("Приведём к общему знаменателю и сократим", "Bring to a common denominator and cancel"),
                        formula: resultText))
                explanation = l(
                    "Дроби приводим к общему знаменателю, раскрываем скобки в числителе и сокращаем общие множители числителя и знаменателя.",
                    "Bring the fractions to a common denominator, expand the numerator and cancel common factors of the numerator and denominator.")
            }
        } else {
            resultText = fmt.expr(SymbolicSimplifier.simplify(expr))
            steps.append(SolutionStep(l("Упростим по правилам алгебры", "Simplify using algebra rules"), formula: resultText))
        }

        var allNotes = notes
        if resultText == original {
            // Без просьбы упростить неизменённое выражение — не ответ: непонятно, что спрашивается (AUD-11).
            guard explicitRequest else {
                throw MathError.unsupported(
                    detail: l(
                        "Выражение уже записано в простом виде, а что с ним нужно сделать, из текста непонятно. Уточните задание: например, «решите уравнение …» или «найдите значение при x = …».",
                        "The expression is already in a simple form, and the text does not say what to do with it. Clarify the task, e.g. “solve the equation …” or “evaluate at x = …”."
                    ))
            }
            allNotes.append(l("Выражение уже записано в простом виде.", "The expression is already in a simple form."))
        }
        if let domainNote = try? cancelledDomainNote(expr, fmt: fmt) {
            allNotes.append(domainNote)
        }
        return Solution(
            subject: .math, problemType: l("Упрощение выражения", "Simplifying an expression"),
            interpretedProblem: original, answer: resultText, explanation: explanation, steps: steps,
            reliability: .exact, engine: .math, notes: allNotes)
    }

    /// После сокращения дроби напоминаем об ОДЗ: (x² − 1)/(x − 1) = x + 1 только при x ≠ 1.
    private func cancelledDomainNote(_ expr: Expr, fmt: MathFormatter) throws -> String? {
        guard let function = try Algebra.rationalFunction(expr), !function.isPolynomial else { return nil }
        let reduced = try function.reduced()
        let variables = Set(function.denominator.variables)
        guard variables.count == 1, let x = variables.first, let original = function.denominator.coefficients(in: x) else { return nil }
        let reducedDenominator = reduced.denominator.coefficients(in: x) ?? [.one]
        let roots = try UnivariatePolynomial.extractRationalRoots(original).roots
        var excluded: [Rational] = []
        for root in roots where !excluded.contains(root) {
            // Нужна оговорка только для точек, которые «пропали» при сокращении.
            let stillExcluded = (try? UnivariatePolynomial.evaluate(reducedDenominator, at: root).isZero) ?? false
            if !stillExcluded { excluded.append(root) }
        }
        guard !excluded.isEmpty else { return nil }
        let list = excluded.sorted().map { "\(x) ≠ \(fmt.rational($0))" }.joined(separator: ", ")
        return l(
            "Сокращение верно при \(list): в этих точках исходное выражение не определено (знаменатель равен нулю).",
            "The cancellation holds for \(list): the original expression is undefined there (zero denominator).")
    }

    private func solveFactor(_ fragment: String, fmt: MathFormatter) throws -> Solution {
        let parsed = try MathParser.parseDetailed(fragment)
        guard let polynomial = try Algebra.polynomial(parsed.expr) else {
            throw MathError.unsupported(
                detail: l("На множители раскладываются только многочлены.", "Only polynomials can be factored."))
        }
        let original = fmt.expr(parsed.expr)
        let result = try Factorizer(fmt: fmt).factor(polynomial, l)
        var steps: [SolutionStep] = [SolutionStep(l("Запишем многочлен", "Write the polynomial"), formula: fmt.polynomial(polynomial))]
        for (index, line) in result.method.enumerated() {
            steps.append(SolutionStep(l("Шаг \(index + 1)", "Step \(index + 1)"), line))
        }
        steps.append(SolutionStep(l("Разложение", "Factorization"), formula: "\(fmt.polynomial(polynomial)) = \(result.text)"))
        var notes = heuristicNotes(parsed.heuristics)
        if !result.changed {
            notes.append(
                l(
                    "Многочлен не раскладывается на множители с рациональными коэффициентами известными движку способами.",
                    "The polynomial cannot be factored over the rationals by the methods the engine knows."))
        }
        return Solution(
            subject: .math, problemType: l("Разложение на множители", "Factoring"),
            interpretedProblem: original, answer: result.text,
            explanation: l(
                "Чтобы разложить многочлен на множители, выносят общий множитель, применяют формулы сокращённого умножения или находят корни: каждому корню r соответствует множитель (x − r).",
                "To factor a polynomial we take out a common factor, apply special product formulas or find roots: each root r gives a factor (x − r)."
            ),
            steps: steps, reliability: .exact, engine: .math, notes: notes)
    }

    // MARK: - Calculus

    /// Точка из «в точке x₀ = 2», «при x = 3», «at x = 1».
    private func derivativePoint(_ lower: String) -> Rational? {
        let normalized = MathNormalizer.normalize(lower)
        let pattern =
            "(?:в\\s+точке|at\\s+(?:the\\s+)?point|(?<![а-яa-z])при|(?<![a-z])at|(?<![a-z])when)\\s+(?:[a-zа-я][₀0]?\\s*=\\s*)?(-?\\s*\\d+(?:[.,]\\d+)?)(?![\\d.,]*\\d|\\s*[a-zа-я(^])"
        guard let match = Rx.first(pattern, in: normalized) else { return nil }
        return signedNumber(match[1])
    }

    private func solveDerivative(_ fragment: String, variableHint: String?, functionName: String?, lower: String, fmt: MathFormatter) throws -> Solution {
        let parsed = try MathParser.parseDetailed(fragment)
        let expr = parsed.expr
        let variables = expr.variables
        let x = variableHint.flatMap { variables.contains($0) ? $0 : nil } ?? (variables.contains("x") ? "x" : variables.sorted().first ?? "x")
        let name = functionName ?? "f"
        let head = name == "y" ? "y" : "\(name)(\(x))"
        let primeHead = name == "y" ? "y′" : "\(name)′(\(x))"

        var differentiator = Differentiator()
        let derivative = try differentiator.derivative(of: expr, by: x)
        let resultText = fmt.expr(derivative)

        var steps: [SolutionStep] = [SolutionStep(l("Запишем функцию", "Write the function"), formula: "\(head) = \(fmt.expr(expr))")]
        let rules = Differentiator.Rule.allCases.filter { differentiator.rules.contains($0) }
        if !rules.isEmpty {
            steps.append(
                SolutionStep(
                    l("Какие правила нужны", "Which rules we need"),
                    rules.map { "• " + Differentiator.ruleText($0, l) }.joined(separator: "\n")))
        }
        let terms = topLevelTerms(expr)
        if terms.count > 1 {
            var lines: [String] = []
            for item in terms {
                var termDifferentiator = Differentiator()
                let termDerivative = try termDifferentiator.derivative(of: item.term, by: x)
                lines.append("(\(fmt.expr(item.term)))′ = \(fmt.expr(termDerivative))")
            }
            steps.append(SolutionStep(l("Продифференцируем каждое слагаемое", "Differentiate each term"), formula: lines.joined(separator: "\n")))
        }
        steps.append(SolutionStep(l("Соберём результат", "Combine the result"), formula: "\(primeHead) = \(resultText)"))

        // «Значение производной в точке x₀» — подставляем точку (AUD-10).
        if let point = derivativePoint(lower) {
            let value = try evaluator.evaluate(derivative, [x: .exact(point)])
            let pointText = fmt.rational(point)
            let atPoint = name == "y" ? "y′(\(pointText))" : "\(name)′(\(pointText))"
            let substituted = fmt.expr(derivative.substituting([x: .num(point)]))
            steps.append(
                SolutionStep(
                    l("Подставим \(x) = \(pointText)", "Substitute \(x) = \(pointText)"),
                    formula: "\(atPoint) = \(substituted) = \(fmt.valueWithApproximation(value))"))
            return Solution(
                subject: .math, problemType: l("Значение производной в точке", "Derivative at a point"),
                interpretedProblem: "\(head) = \(fmt.expr(expr)), \(x)₀ = \(pointText)",
                answer: "\(atPoint) = \(fmt.valueWithApproximation(value))",
                explanation: l(
                    "Сначала находим производную по правилам дифференцирования, затем подставляем в неё значение аргумента.",
                    "First find the derivative using the differentiation rules, then substitute the argument value into it."),
                steps: steps, formulas: rules.map { Differentiator.ruleText($0, l) },
                reliability: value.isExact ? .exact : .approximate, engine: .math, notes: heuristicNotes(parsed.heuristics))
        }

        return Solution(
            subject: .math, problemType: l("Производная функции", "Derivative of a function"),
            interpretedProblem: "\(head) = \(fmt.expr(expr))", answer: "\(primeHead) = \(resultText)",
            explanation: l(
                "Производная показывает скорость изменения функции. Её находят по таблице производных и правилам дифференцирования суммы, произведения, частного и сложной функции.",
                "The derivative shows how fast a function changes. It is found from the table of derivatives and the sum, product, quotient and chain rules."
            ),
            steps: steps, formulas: rules.map { Differentiator.ruleText($0, l) }, reliability: .exact, engine: .math,
            notes: heuristicNotes(parsed.heuristics))
    }

    private func splitConstantFactor(_ expr: Expr) -> (Rational, Expr)? {
        switch expr {
        case .neg(let inner):
            guard let (k, rest) = splitConstantFactor(inner) else { return nil }
            return (k.negated, rest)
        case .bin(.mul, .num(let k), let rest):
            guard let (inner, body) = splitConstantFactor(rest), let product = try? k * inner else { return nil }
            return (product, body)
        case .bin(.div, let top, .num(let k)):
            guard !k.isZero, let (inner, body) = splitConstantFactor(top), let quotient = try? inner / k else { return nil }
            return (quotient, body)
        default:
            return (.one, expr)
        }
    }

    /// Первообразная одного слагаемого по таблице. `nil` — если такого в таблице нет.
    private func tableAntiderivative(_ term: Expr, _ x: String) -> Expr? {
        guard let (k, body) = splitConstantFactor(term) else { return nil }
        let variable = Expr.sym(x)
        let result: Expr
        switch body {
        case .fn(.sin, let args) where args == [variable]:
            result = .neg(.fn(.cos, [variable]))
        case .fn(.cos, let args) where args == [variable]:
            result = .fn(.sin, [variable])
        case .bin(.pow, .const(.e), let exponent) where exponent == variable:
            result = body
        case .bin(.div, .num(let top), let bottom) where bottom == variable:
            return .bin(.mul, .num((try? k * top) ?? k), .fn(.ln, [.fn(.abs, [variable])]))
        default:
            return nil
        }
        return .bin(.mul, .num(k), result)
    }

    /// Есть ли в выражении логарифм — признак слагаемого k/x в подынтегральной функции.
    private func containsLogarithm(_ expr: Expr) -> Bool {
        switch expr {
        case .num, .real, .sym, .const: return false
        case .neg(let inner): return containsLogarithm(inner)
        case .bin(_, let a, let b): return containsLogarithm(a) || containsLogarithm(b)
        case .fn(let f, let args): return f == .ln || args.contains { containsLogarithm($0) }
        }
    }

    private func solveIntegral(
        _ fragment: String, variableHint: String?, bounds: (lower: Rational, upper: Rational)?, fmt: MathFormatter
    ) throws -> Solution {
        // «∫ … dx» → убираем дифференциал.
        var body = fragment.replacingOccurrences(of: "∫", with: "")
        body = Rx.replace("\\s*d\\s*([a-z])\\s*$", in: body, with: "")
        let parsed = try MathParser.parseDetailed(body)
        let expr = parsed.expr
        let variables = expr.variables
        let x = variableHint.flatMap { variables.contains($0) ? $0 : nil } ?? (variables.contains("x") ? "x" : variables.sorted().first ?? "x")

        var antiderivative: Expr?
        var usedTable = false
        if let polynomial = try Algebra.polynomial(expr) {
            antiderivative = try polynomial.antiderivative(in: x).asExpr
        } else {
            var sum: Expr?
            var failed = false
            for item in topLevelTerms(expr) {
                var piece: Expr?
                if let polynomial = try Algebra.polynomial(item.term) {
                    piece = try polynomial.antiderivative(in: x).asExpr
                } else if let table = tableAntiderivative(item.term, x) {
                    piece = table
                    usedTable = true
                }
                guard let piece else {
                    failed = true
                    break
                }
                let signed: Expr = item.negative ? .neg(piece) : piece
                sum = sum.map { .bin(.add, $0, signed) } ?? signed
            }
            antiderivative = failed ? nil : sum.map { SymbolicSimplifier.simplify($0) }
        }
        guard let antiderivative else {
            throw MathError.unsupported(
                detail: l(
                    "Локальный движок находит первообразные многочленов и простейших табличных функций (sin x, cos x, eˣ, 1/x). Для этого выражения нужен более сложный метод интегрирования.",
                    "The local engine integrates polynomials and the simplest table functions (sin x, cos x, eˣ, 1/x). This expression needs a more advanced integration technique."
                ))
        }

        let integrand = fmt.expr(expr)
        let resultText = fmt.expr(antiderivative)
        var steps: [SolutionStep] = [
            SolutionStep(l("Запишем интеграл", "Write the integral"), formula: "∫(\(integrand))d\(x)"),
            SolutionStep(
                l("Интегрируем каждое слагаемое", "Integrate each term"),
                usedTable
                    ? l(
                        "Используем таблицу: ∫xⁿdx = xⁿ⁺¹/(n + 1), ∫sin x dx = −cos x, ∫cos x dx = sin x, ∫eˣdx = eˣ, ∫dx/x = ln|x|.",
                        "Use the table: ∫xⁿdx = xⁿ⁺¹/(n + 1), ∫sin x dx = −cos x, ∫cos x dx = sin x, ∫eˣdx = eˣ, ∫dx/x = ln|x|.")
                    : l(
                        "Для степени: ∫xⁿdx = xⁿ⁺¹/(n + 1). Постоянный множитель выносится за знак интеграла.",
                        "Power rule: ∫xⁿdx = xⁿ⁺¹/(n + 1). A constant factor is taken outside the integral."),
                formula: "F(\(x)) = \(resultText)"),
        ]
        var formulas = ["∫xⁿdx = xⁿ⁺¹/(n + 1) + C"]

        // Определённый интеграл: «от a до b».
        if let (lowerBound, upperBound) = bounds {
            // ∫ dx/x через 0 — несобственный и расходится; формула Ньютона — Лейбница здесь неприменима.
            let (left, right) = lowerBound < upperBound ? (lowerBound, upperBound) : (upperBound, lowerBound)
            if containsLogarithm(antiderivative), left <= .zero, right >= .zero {
                throw MathError.unsupported(
                    detail: l(
                        "Подынтегральная функция не определена при \(x) = 0, а эта точка лежит на отрезке [\(fmt.rational(left)); \(fmt.rational(right))]. Такой интеграл несобственный и расходится — формула Ньютона — Лейбница к нему неприменима.",
                        "The integrand is undefined at \(x) = 0, which lies in [\(fmt.rational(left)); \(fmt.rational(right))]. This improper integral diverges, so the Newton–Leibniz formula does not apply."
                    ))
            }
            // Подынтегральная функция должна быть определена на всём отрезке.
            for step in 0...64 {
                let t = left.doubleValue + (right.doubleValue - left.doubleValue) * Double(step) / 64
                guard evaluator.numeric(expr, variable: x, at: t).isFinite else {
                    throw MathError.unsupported(
                        detail: l(
                            "Подынтегральная функция не определена на части отрезка интегрирования — интеграл несобственный, локальный движок его не вычисляет.",
                            "The integrand is undefined on part of the interval — the integral is improper and the local engine does not compute it."))
                }
            }
            let upperValue = try evaluator.evaluate(antiderivative, [x: .exact(upperBound)])
            let lowerValue = try evaluator.evaluate(antiderivative, [x: .exact(lowerBound)])
            let value = try evaluator.apply(.sub, upperValue, lowerValue)
            formulas.append("∫ₐᵇ f(x)dx = F(b) − F(a)")
            steps.append(
                SolutionStep(
                    l("Применим формулу Ньютона — Лейбница", "Apply the Newton–Leibniz formula"),
                    formula:
                        "F(\(fmt.rational(upperBound))) − F(\(fmt.rational(lowerBound))) = \(fmt.value(upperValue)) − (\(fmt.value(lowerValue))) = \(fmt.value(value))"
                ))
            return Solution(
                subject: .math, problemType: l("Определённый интеграл", "Definite integral"),
                interpretedProblem: "∫(\(integrand))d\(x), \(x) ∈ [\(fmt.rational(lowerBound)); \(fmt.rational(upperBound))]",
                answer: fmt.valueWithApproximation(value),
                explanation: l(
                    "Определённый интеграл равен разности значений первообразной на концах отрезка.",
                    "A definite integral equals the difference of the antiderivative's values at the ends of the interval."),
                steps: steps, formulas: formulas, reliability: value.isExact ? .exact : .approximate, engine: .math,
                notes: heuristicNotes(parsed.heuristics))
        }

        steps.append(
            SolutionStep(
                l("Добавим постоянную интегрирования", "Add the constant of integration"),
                l("Первообразных бесконечно много — они отличаются на константу C.", "There are infinitely many antiderivatives — they differ by a constant C."),
                formula: "\(resultText) + C"))
        return Solution(
            subject: .math, problemType: l("Неопределённый интеграл", "Indefinite integral"),
            interpretedProblem: "∫(\(integrand))d\(x)", answer: "\(resultText) + C",
            explanation: l(
                "Интегрирование — действие, обратное дифференцированию: ищем функцию, производная которой равна данной.",
                "Integration is the inverse of differentiation: we look for a function whose derivative is the given one."),
            steps: steps, formulas: formulas, reliability: .exact, engine: .math, notes: heuristicNotes(parsed.heuristics))
    }

    // MARK: - Substitution

    private func solveSubstitution(candidates: [String], lower: String, fmt: MathFormatter) throws -> Solution? {
        guard lower.containsAny(["при ", "если ", "where ", "when ", "if ", "for "]) else { return nil }
        var environment: [String: MathValue] = [:]
        var assignmentTexts: [String] = []
        var others: [String] = []
        for candidate in candidates {
            if let match = Rx.first("^\\s*([a-zA-Z])\\s*=\\s*(.+)$", in: candidate), !hasRelation(match[2]),
                let valueExpr = try? MathParser.parse(match[2]), valueExpr.isConstant,
                let value = try? evaluator.evaluate(valueExpr)
            {
                environment[match[1]] = value
                assignmentTexts.append("\(match[1]) = \(fmt.value(value))")
            } else {
                others.append(candidate)
            }
        }
        guard !environment.isEmpty, let target = others.first else { return nil }

        var body = target
        var head: String?
        if hasRelation(target) {
            // «y = 2x + 3 при x = 5»
            guard let match = Rx.first("^\\s*([a-zA-Z](?:\\s*\\(\\s*[a-zA-Z]\\s*\\))?)\\s*=\\s*(.+)$", in: target), !hasRelation(match[2]) else {
                return nil
            }
            head = match[1]
            body = match[2]
        }
        let parsed = try MathParser.parseDetailed(body)
        guard !parsed.expr.variables.isEmpty, parsed.expr.variables.isSubset(of: Set(environment.keys)) else { return nil }

        let literals = environment.mapValues { $0.literal }
        let substituted = parsed.expr.substituting(literals)
        let note = "\(assignmentTexts.joined(separator: ", ")): \(fmt.expr(parsed.expr)) = \(fmt.expr(substituted))"
        var solution = try solveArithmetic(substituted, fmt: fmt, notes: heuristicNotes(parsed.heuristics), environmentNote: note)
        solution.problemType = l("Значение выражения при заданных переменных", "Value of an expression for given variables")
        solution.interpretedProblem = "\(head.map { $0 + " = " } ?? "")\(fmt.expr(parsed.expr)), \(assignmentTexts.joined(separator: ", "))"
        if let head { solution.answer = "\(head) = \(solution.answer)" }
        solution.explanation =
            l("Вместо букв подставляем их значения и выполняем действия по порядку. ", "Replace the letters with their values and perform the operations in order. ")
            + solution.explanation
        return solution
    }

    // MARK: - Percentages

    private func number(_ text: String) -> Rational? {
        Rational(decimal: text.replacingOccurrences(of: " ", with: ""))
    }

    private func solvePercent(_ lower: String) -> Solution? {
        guard lower.contains("%") || lower.contains("процент") || lower.contains("percent") else { return nil }
        let text = MathNormalizer.normalize(lower).replacingOccurrences(of: "процентов", with: "%").replacingOccurrences(of: "процента", with: "%")
            .replacingOccurrences(of: " percent", with: "%")
        let n = "(\\d+(?:[.,]\\d+)?)"
        let fmt = MathFormatter(lang: lang, preferDecimals: true)
        let title = l("Задача на проценты", "Percentage problem")
        let percentIdea = l(
            "Процент — это сотая часть числа: 1% = 1/100.",
            "A percent is one hundredth of a number: 1% = 1/100.")

        func build(_ interpreted: String, _ answer: Rational, suffix: String = "", steps: [SolutionStep], formula: String) -> Solution {
            Solution(
                subject: .math, problemType: title, interpretedProblem: interpreted,
                answer: fmt.rationalWithApproximation(answer) + suffix, explanation: percentIdea, steps: steps,
                formulas: [formula], reliability: .exact, engine: .math)
        }

        do {
            let percentCount = text.filter { $0 == "%" }.count
            if percentCount >= 2 {
                if let solution = try solvePercentChain(text, n: n, fmt: fmt, build: build) { return solution }
                if let solution = try solveSuccessiveChanges(text, n: n, fmt: fmt, build: build) { return solution }
                // Несколько процентов, а шаблон не узнан: ответ по первому из них был бы ответом
                // на другой вопрос (AUD-10) — честно отказываем.
                var refusal = Solution.unsupported(
                    subject: .math, problemType: title,
                    reason: l(
                        "В задаче несколько процентных величин, а точный алгоритм узнаёт только одно действие с процентами, цепочку «a% от b% от числа» и последовательные изменения на p%. Решите задачу по действиям или с нейросетью.",
                        "The problem has several percentages, while the exact algorithm recognizes only a single percentage operation, a chain “a% of b% of a number” and successive changes by p%. Solve it step by step or with the AI model."
                    ), engine: .math)
                refusal.interpretedProblem = text
                return refusal
            }
            // Сколько процентов составляет A от B.
            let whatPercent = [
                "сколько\\s*%\\s+(?:составля\\w+\\s+)?(?:число\\s+)?\(n)\\s+от\\s+(?:числа\\s+)?\(n)",
                "\(n)\\s+is\\s+what\\s*%(?:age)?\\s+of\\s+\(n)",
                "what\\s*%(?:age)?\\s+is\\s+\(n)\\s+of\\s+\(n)",
            ]
            for pattern in whatPercent {
                if let match = Rx.first(pattern, in: text), let a = number(match[1]), let b = number(match[2]), !b.isZero {
                    let result = try (try a / b) * Rational(100)
                    return build(
                        l("Сколько процентов составляет \(fmt.rational(a)) от \(fmt.rational(b))", "What percent of \(fmt.rational(b)) is \(fmt.rational(a))"),
                        result, suffix: "%",
                        steps: [
                            SolutionStep(l("Разделим часть на целое", "Divide the part by the whole"), formula: "\(fmt.rational(a)) : \(fmt.rational(b)) = \(fmt.rationalWithApproximation(try a / b))"),
                            SolutionStep(l("Переведём в проценты — умножим на 100", "Convert to percent — multiply by 100"), formula: "\(fmt.rational(try a / b))·100 = \(fmt.rationalWithApproximation(result))%"),
                        ], formula: "p = a/b·100%")
                }
            }
            if let match = Rx.first("what\\s*%(?:age)?\\s+of\\s+\(n)\\s+is\\s+\(n)", in: text), let b = number(match[1]), let a = number(match[2]), !b.isZero {
                let result = try (try a / b) * Rational(100)
                return build(
                    "What percent of \(fmt.rational(b)) is \(fmt.rational(a))", result, suffix: "%",
                    steps: [SolutionStep(l("Разделим часть на целое и умножим на 100", "Divide the part by the whole and multiply by 100"), formula: "\(fmt.rational(a)) : \(fmt.rational(b))·100 = \(fmt.rationalWithApproximation(result))%")],
                    formula: "p = a/b·100%")
            }

            // Увеличить / уменьшить число на p%.
            let change = [
                "(увелич\\w+|уменьш\\w+|повыс\\w+|сниз\\w+|increase\\w*|decrease\\w*|reduce\\w*)\\s+(?:число\\s+|цену\\s+)?\(n)\\s+(?:на|by)\\s+\(n)\\s*%"
            ]
            for pattern in change {
                if let match = Rx.first(pattern, in: text), let base = number(match[2]), let p = number(match[3]) {
                    let up = match[1].hasPrefix("увелич") || match[1].hasPrefix("повыс") || match[1].hasPrefix("increase")
                    let part = try (try base * p) / Rational(100)
                    let result = up ? try base + part : try base - part
                    return build(
                        up
                            ? l("Увеличить \(fmt.rational(base)) на \(fmt.rational(p))%", "Increase \(fmt.rational(base)) by \(fmt.rational(p))%")
                            : l("Уменьшить \(fmt.rational(base)) на \(fmt.rational(p))%", "Decrease \(fmt.rational(base)) by \(fmt.rational(p))%"),
                        result,
                        steps: [
                            SolutionStep(l("Найдём \(fmt.rational(p))% от числа", "Find \(fmt.rational(p))% of the number"), formula: "\(fmt.rational(base))·\(fmt.rational(p))/100 = \(fmt.rationalWithApproximation(part))"),
                            SolutionStep(
                                up ? l("Прибавим к исходному числу", "Add it to the original number") : l("Вычтем из исходного числа", "Subtract it from the original number"),
                                formula: "\(fmt.rational(base)) \(up ? "+" : "−") \(fmt.rational(part)) = \(fmt.rationalWithApproximation(result))"),
                        ], formula: up ? "a·(1 + p/100)" : "a·(1 − p/100)")
                }
            }

            // Найти число, p% которого равны A.
            let reverse = [
                "\(n)\\s*%\\s+которого\\s+(?:равн\\w+|составля\\w+)\\s+\(n)",
                "\(n)\\s*%\\s+of\\s+(?:what|which)\\s+number\\s+is\\s+\(n)",
                "\(n)\\s+(?:составля\\w+|это)\\s+\(n)\\s*%\\s+(?:от\\s+)?(?:какого\\s+)?числа",
                "\(n)\\s+is\\s+\(n)\\s*%\\s+of\\s+(?:what|which)",
            ]
            for (index, pattern) in reverse.enumerated() {
                if let match = Rx.first(pattern, in: text), let first = number(match[1]), let second = number(match[2]) {
                    let (p, part) = index < 2 ? (first, second) : (second, first)
                    guard !p.isZero else { continue }
                    let result = try (try part / p) * Rational(100)
                    return build(
                        l("Найти число, \(fmt.rational(p))% которого равны \(fmt.rational(part))", "Find the number whose \(fmt.rational(p))% is \(fmt.rational(part))"),
                        result,
                        steps: [
                            SolutionStep(l("Найдём 1% числа", "Find 1% of the number"), formula: "\(fmt.rational(part)) : \(fmt.rational(p)) = \(fmt.rationalWithApproximation(try part / p))"),
                            SolutionStep(l("Всё число — это 100%", "The whole number is 100%"), formula: "\(fmt.rational(try part / p))·100 = \(fmt.rationalWithApproximation(result))"),
                        ], formula: "a = b : p·100")
                }
            }

            // p% от числа A.
            if let match = Rx.first("\(n)\\s*%\\s*(?:от|из|of)\\s+(?:числа\\s+|the\\s+number\\s+)?\(n)", in: text), let p = number(match[1]), let base = number(match[2]) {
                let onePercent = try base / Rational(100)
                let result = try onePercent * p
                return build(
                    l("\(fmt.rational(p))% от \(fmt.rational(base))", "\(fmt.rational(p))% of \(fmt.rational(base))"), result,
                    steps: [
                        SolutionStep(l("Найдём 1% числа", "Find 1% of the number"), formula: "\(fmt.rational(base)) : 100 = \(fmt.rationalWithApproximation(onePercent))"),
                        SolutionStep(l("Умножим на количество процентов", "Multiply by the number of percent"), formula: "\(fmt.rational(onePercent))·\(fmt.rational(p)) = \(fmt.rationalWithApproximation(result))"),
                    ], formula: "b = a·p/100")
            }
        } catch {
            return nil
        }
        return nil
    }

    /// «20% от 50% от 400»: проценты применяются по очереди справа налево.
    private func solvePercentChain(
        _ text: String, n: String, fmt: MathFormatter,
        build: (String, Rational, String, [SolutionStep], String) -> Solution
    ) throws -> Solution? {
        let link = "\(n)\\s*%\\s*(?:от|из|of)\\s+(?:числа\\s+|the\\s+number\\s+)?"
        guard let match = Rx.first("((?:\(link)){2,})\(n)(?!\\s*%|[\\d.,]*\\d)", in: text), let base = number(match[match.count - 1]) else {
            return nil
        }
        let percents = Rx.matches("\(n)\\s*%", in: match[1]).compactMap { number($0[1]) }
        guard percents.count >= 2, percents.count == text.filter({ $0 == "%" }).count else { return nil }
        var value = base
        var steps: [SolutionStep] = []
        for p in percents.reversed() {
            let next = try (try value * p) / Rational(100)
            steps.append(
                SolutionStep(
                    l("Найдём \(fmt.rational(p))% от \(fmt.rational(value))", "Find \(fmt.rational(p))% of \(fmt.rational(value))"),
                    formula: "\(fmt.rational(value))·\(fmt.rational(p))/100 = \(fmt.rationalWithApproximation(next))"))
            value = next
        }
        let interpreted = percents.map { "\(fmt.rational($0))%" }.joined(separator: l(" от ", " of ")) + l(" от ", " of ") + fmt.rational(base)
        return build(interpreted, value, "", steps, "b = a·p/100")
    }

    /// «Увеличьте 200 на 15%, затем уменьшите на 10%», «Цена 200 руб. +10 %, затем −10 %».
    private func solveSuccessiveChanges(
        _ text: String, n: String, fmt: MathFormatter,
        build: (String, Rational, String, [SolutionStep], String) -> Solution
    ) throws -> Solution? {
        let verbs =
            "(увелич\\w*|уменьш\\w*|повыс\\w*|повыш\\w*|сниз\\w*|сниж\\w*|подорожа\\w*|подешеве\\w*|подешевл\\w*|вырос\\w*|упал\\w*|increase\\w*|decrease\\w*|reduce\\w*|rais\\w*|rose|fell|drop\\w*|grew|grow\\w*)"
        var changes: [(position: String.Index, up: Bool, percent: Rational)] = []
        var verbalRanges: [Range<String.Index>] = []
        for match in Rx.ranges("\(verbs)[^%]*?(?<![а-яa-z])(?:на|by)\\s+\(n)\\s*%", in: text) {
            guard let whole = match[0], let verbRange = match[1], let valueRange = match[2], let p = number(String(text[valueRange])) else { continue }
            let verb = text[verbRange]
            let up = ["увелич", "повыс", "повыш", "подорожа", "вырос", "increase", "rais", "rose", "grew", "grow"].contains { verb.hasPrefix($0) }
            changes.append((whole.lowerBound, up, p))
            verbalRanges.append(whole)
        }
        for match in Rx.ranges("(?<![\\d.,%\\w])([+-])\\s*\(n)\\s*%", in: text) {
            guard let whole = match[0], let signRange = match[1], let valueRange = match[2], let p = number(String(text[valueRange])) else { continue }
            // Знак внутри уже найденной словесной формулировки («увеличилась на +10%») не считаем повторно.
            if verbalRanges.contains(where: { $0.contains(whole.lowerBound) }) { continue }
            changes.append((whole.lowerBound, text[signRange] == "+", p))
        }
        guard changes.count >= 2, changes.count == text.filter({ $0 == "%" }).count else { return nil }
        changes.sort { $0.position < $1.position }

        // Исходная величина — единственное число без знака процента.
        let plainNumbers = Rx.matches("(?<![\\d.,])\(n)(?![\\d.,]*\\d|\\s*%)", in: text).compactMap { number($0[1]) }
        guard plainNumbers.count == 1, let base = plainNumbers.first else { return nil }

        var value = base
        var steps: [SolutionStep] = []
        var formula = fmt.rational(base)
        for change in changes {
            let factor = change.up ? try Rational(100) + change.percent : try Rational(100) - change.percent
            let next = try (try value * factor) / Rational(100)
            steps.append(
                SolutionStep(
                    change.up
                        ? l("Увеличим на \(fmt.rational(change.percent))%", "Increase by \(fmt.rational(change.percent))%")
                        : l("Уменьшим на \(fmt.rational(change.percent))%", "Decrease by \(fmt.rational(change.percent))%"),
                    l(
                        "Новое значение составляет \(fmt.rational(factor))% от предыдущего.",
                        "The new value is \(fmt.rational(factor))% of the previous one."),
                    formula: "\(fmt.rational(value))·\(fmt.rational(factor))/100 = \(fmt.rationalWithApproximation(next))"))
            formula += "·\(fmt.rational(try factor / Rational(100)))"
            value = next
        }
        steps.append(SolutionStep(l("Итог", "Result"), formula: "\(formula) = \(fmt.rationalWithApproximation(value))"))
        let interpreted = fmt.rational(base) + " " + changes.map { ($0.up ? "+" : MathFormatter.minus) + fmt.rational($0.percent) + "%" }.joined(separator: l(", затем ", ", then "))
        return build(interpreted, value, "", steps, "a·(1 ± p/100)")
    }

    // MARK: - Divisibility

    private func factorizationText(_ value: Int, _ fmt: MathFormatter) -> String {
        let factors = IntegerMath.primeFactors(value)
        guard !factors.isEmpty else { return String(value) }
        return factors.map { $0.power == 1 ? "\($0.prime)" : "\($0.prime)\(fmt.superscript($0.power))" }.joined(separator: "·")
    }

    /// Разложение одного или нескольких чисел на простые множители.
    private func primeFactorizationSolution(_ values: [Int], fmt: MathFormatter) -> Solution {
        var steps: [SolutionStep] = []
        var answers: [String] = []
        for value in values {
            var rest = value
            var lines: [String] = []
            for factor in IntegerMath.primeFactors(value) {
                for _ in 0..<factor.power {
                    lines.append("\(rest) : \(factor.prime) = \(rest / factor.prime)")
                    rest /= factor.prime
                }
            }
            steps.append(
                SolutionStep(
                    values.count == 1
                        ? l("Делим на наименьший простой делитель, пока не получим 1", "Divide by the smallest prime divisor until we reach 1")
                        : l("Число \(value): делим на наименьший простой делитель, пока не получим 1", "Number \(value): divide by the smallest prime divisor until we reach 1"),
                    formula: lines.joined(separator: "\n")))
            answers.append("\(value) = \(factorizationText(value, fmt))")
        }
        let answer = answers.joined(separator: "; ")
        steps.append(SolutionStep(l("Запишем произведение", "Write the product"), formula: answers.joined(separator: "\n")))
        return Solution(
            subject: .math, problemType: l("Разложение на простые множители", "Prime factorization"),
            interpretedProblem: values.map(String.init).joined(separator: "; "), answer: answer,
            explanation: l(
                "Любое натуральное число больше 1 единственным образом раскладывается в произведение простых чисел.",
                "Every natural number greater than 1 factors uniquely into a product of primes."),
            steps: steps, reliability: .exact, engine: .math)
    }

    /// Группы «НОД/НОК → числа»: числа после ключевого слова до следующего ключевого слова.
    /// «НОД и НОК чисел 12 и 18» — обе величины для одних чисел; если чисел после слов нет — берём все.
    private func divisibilityGroups(_ lower: String, numbers: [(position: String.Index, value: Int)]) -> [(gcd: Bool, numbers: [Int])] {
        let keywordPattern =
            "(?<![а-яa-z])(?:нод|нок)(?![а-яa-z])|наибольш\\w*\\s+общ\\w*\\s+делител\\w*|наименьш\\w*\\s+общ\\w*\\s+кратн\\w*|(?<![a-z])(?:gcd|gcf|hcf|lcm)(?![a-z])|(?:greatest|highest)\\s+common\\s+(?:divisor|factor)|(?:least|lowest)\\s+common\\s+multiple"
        let keywords: [(range: Range<String.Index>, gcd: Bool)] = Rx.ranges(keywordPattern, in: lower).compactMap { match in
            guard let range = match[0] else { return nil }
            let word = lower[range]
            let gcd = word.hasPrefix("нод") || word.contains("делител") || ["gcd", "gcf", "hcf", "divisor", "factor"].contains { word.contains($0) }
            return (range, gcd)
        }
        guard !keywords.isEmpty else { return [] }
        var segments: [[Int]] = []
        for (index, keyword) in keywords.enumerated() {
            let end = index + 1 < keywords.count ? keywords[index + 1].range.lowerBound : lower.endIndex
            segments.append(numbers.filter { $0.position >= keyword.range.upperBound && $0.position < end }.map(\.value))
        }
        if segments.allSatisfy({ $0.isEmpty }) {
            let all = numbers.map(\.value)
            return keywords.map { ($0.gcd, all) }
        }
        // «НОД и НОК чисел …»: пустой отрезок наследует числа следующего.
        for index in stride(from: segments.count - 2, through: 0, by: -1) where segments[index].isEmpty {
            segments[index] = segments[index + 1]
        }
        if let last = segments.indices.last, segments[last].isEmpty {
            segments[last] = numbers.filter { $0.position < keywords[0].range.lowerBound }.map(\.value)
        }
        var groups: [(gcd: Bool, numbers: [Int])] = []
        for (index, keyword) in keywords.enumerated() {
            if groups.contains(where: { $0.gcd == keyword.gcd && $0.numbers == segments[index] }) { continue }
            groups.append((keyword.gcd, segments[index]))
        }
        return groups
    }

    private func solveDivisibility(_ lower: String) -> Solution? {
        let wantsGCD = lower.containsAny(["нод", "наибольший общий делитель", "наибольшего общего делителя", "gcd", "gcf", "hcf", "greatest common"])
        let wantsLCM = lower.containsAny(["нок", "наименьшее общее кратное", "наименьшего общего кратного", "lcm", "least common multiple", "lowest common multiple"])
        let wantsPrimes = lower.containsAny(["простые множ", "простых множ", "prime factor"])
        guard wantsGCD || wantsLCM || wantsPrimes else { return nil }
        // Слово «нод»/«нок» должно стоять отдельно, а не внутри другого слова («иногда», «однокоренные»).
        if !wantsPrimes, !lower.containsAny(["наибольш", "наименьш", "gcd", "gcf", "hcf", "lcm", "common"]),
            !Rx.contains("(?<![а-яa-z])(нод|нок)(?![а-яa-z])", in: lower)
        {
            return nil
        }
        let fmt = MathFormatter(lang: lang)
        let numberPattern = "(?<![\\d.,])\\d{1,12}(?![\\d.,]\\d)"
        let numberMatches: [(position: String.Index, value: Int)] = Rx.ranges(numberPattern, in: lower).compactMap { match in
            guard let range = match[0], let value = Int(lower[range]), value > 0 else { return nil }
            return (range.lowerBound, value)
        }
        let numbers = numberMatches.map(\.value)
        guard !numbers.isEmpty else { return nil }

        if wantsPrimes, !wantsGCD, !wantsLCM {
            let values = numbers.filter { $0 > 1 }
            guard !values.isEmpty, values.count <= 6, values.count == numbers.count else { return nil }
            return primeFactorizationSolution(values, fmt: fmt)
        }

        // Каждому «НОД»/«НОК» — свои числа: «НОД чисел 24 и 36 и НОК чисел 8 и 12» (AUD-10).
        let groups = divisibilityGroups(lower, numbers: numberMatches)
        guard !groups.isEmpty, groups.allSatisfy({ $0.numbers.count >= 2 && $0.numbers.count <= 6 }) else { return nil }
        let distinctNumbers = groups.flatMap(\.numbers).reduce(into: [Int]()) { if !$0.contains($1) { $0.append($1) } }
        var steps: [SolutionStep] = [
            SolutionStep(
                l("Разложим числа на простые множители", "Factor the numbers into primes"),
                formula: distinctNumbers.map { "\($0) = \(factorizationText($0, fmt))" }.joined(separator: "\n"))
        ]
        let sameNumbers = Set(groups.map(\.numbers)).count == 1
        let kinds = groups.map(\.gcd)
        let repeatedKind = Set(kinds).count < kinds.count
        var answers: [String] = []
        for group in groups {
            let listed = group.numbers.map(String.init).joined(separator: "; ")
            if group.gcd {
                let gcd = group.numbers.dropFirst().reduce(group.numbers[0]) { Rational.gcd($0, $1) }
                steps.append(
                    SolutionStep(
                        l("НОД: берём общие простые множители с наименьшими показателями", "GCD: take the common prime factors with the smallest exponents"),
                        formula: l("НОД(\(listed)) = \(factorizationText(gcd, fmt)) = \(gcd)", "gcd(\(listed)) = \(factorizationText(gcd, fmt)) = \(gcd)")))
                answers.append(repeatedKind ? l("НОД(\(listed)) = \(gcd)", "GCD(\(listed)) = \(gcd)") : l("НОД = \(gcd)", "GCD = \(gcd)"))
            } else {
                var lcm = group.numbers[0]
                for value in group.numbers.dropFirst() {
                    guard let next = try? Rational.lcm(lcm, value) else { return nil }
                    lcm = next
                }
                steps.append(
                    SolutionStep(
                        l("НОК: берём все простые множители с наибольшими показателями", "LCM: take all prime factors with the largest exponents"),
                        formula: l("НОК(\(listed)) = \(factorizationText(lcm, fmt)) = \(lcm)", "lcm(\(listed)) = \(factorizationText(lcm, fmt)) = \(lcm)")))
                answers.append(repeatedKind ? l("НОК(\(listed)) = \(lcm)", "LCM(\(listed)) = \(lcm)") : l("НОК = \(lcm)", "LCM = \(lcm)"))
            }
        }
        let listed = sameNumbers
            ? (groups.first?.numbers ?? []).map(String.init).joined(separator: "; ")
            : groups.map { group in
                (group.gcd ? l("НОД", "gcd") : l("НОК", "lcm")) + "(" + group.numbers.map(String.init).joined(separator: "; ") + ")"
            }.joined(separator: ", ")
        return Solution(
            subject: .math, problemType: l("Делимость чисел", "Divisibility"),
            interpretedProblem: listed, answer: answers.joined(separator: "; "),
            explanation: l(
                "НОД — наибольшее число, на которое делятся все данные числа. НОК — наименьшее число, которое делится на каждое из них.",
                "The GCD is the largest number dividing all the given numbers. The LCM is the smallest number divisible by each of them."),
            steps: steps, reliability: .exact, engine: .math)
    }
}
