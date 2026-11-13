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
        case derivative, integral, factor, simplify, auto
    }

    // MARK: - Entry point

    func solve(_ text: String) -> Solution? {
        let lower = text.lowercased()
        if let solution = solvePercent(lower) { return solution }
        if let solution = solveDivisibility(lower) { return solution }

        let intent = detectIntent(lower)
        let fragments = MathTextExtractor.fragments(in: text)
        let candidates = fragments.filter { isMeaningful($0, explicitIntent: intent != .auto) }
        guard !candidates.isEmpty else { return nil }

        let preferDecimals = candidates.contains { Rx.contains("\\d[.,]\\d", in: $0) }
        let fmt = MathFormatter(lang: lang, preferDecimals: preferDecimals)
        let hintVariable = fragments.first { $0.count == 1 && ($0.first?.isLetter ?? false) }

        do {
            return try dispatch(
                candidates: candidates, intent: intent, lower: lower, fmt: fmt, hintVariable: hintVariable)
        } catch let error as MathError {
            return failure(error, interpreted: candidates.first ?? "")
        } catch {
            return failure(.unsupported(detail: l("Не удалось решить задание.", "Could not solve the problem.")), interpreted: candidates.first ?? "")
        }
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
        if lower.containsAny(["множител", "factor"]) && !lower.containsAny(["простые множ", "prime factor"]) { return .factor }
        if lower.containsAny(["упрост", "simplif", "раскр", "expand", "приведите подобн", "привести подобн"]) { return .simplify }
        return .auto
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

    private func dispatch(candidates: [String], intent: Intent, lower: String, fmt: MathFormatter, hintVariable: String?) throws -> Solution {
        let relational = candidates.filter { hasRelation($0) }
        let expressions = candidates.filter { !hasRelation($0) }
        var extraNotes: [String] = []

        switch intent {
        case .derivative:
            let stripped = stripFunctionPrefix(candidates[0])
            return try solveDerivative(stripped.body, variableHint: stripped.variable ?? hintVariable, functionName: stripped.name, fmt: fmt)
        case .integral:
            let stripped = stripFunctionPrefix(candidates[0])
            return try solveIntegral(stripped.body, variableHint: stripped.variable ?? hintVariable, lower: lower, fmt: fmt)
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

        if relational.count + expressions.count > 1 {
            extraNotes.append(
                l(
                    "В тексте найдено несколько выражений — решено первое. Чтобы решить другое, выделите на фото только нужную часть задания.",
                    "Several expressions were found — the first one was solved. To solve another, select only the needed part of the photo."
                ))
        }

        if let fragment = relational.first, intent == .auto || expressions.isEmpty {
            var solution = try solveRelational(fragment, lower: lower, fmt: fmt, hintVariable: hintVariable)
            solution.notes += extraNotes
            return solution
        }

        guard let fragment = expressions.first else {
            throw MathError.unsupported(detail: l("Не найдено выражение для решения.", "No expression to solve was found."))
        }
        var solution = try solveExpression(fragment, intent: intent, fmt: fmt)
        solution.notes += extraNotes
        return solution
    }

    private func assumedPowerNote(_ assumed: Bool) -> [String] {
        assumed
            ? [
                l(
                    "Запись вида «x2» прочитана как степень x². Если это не так — исправьте распознанный текст.",
                    "Input like “x2” was read as the power x². If that is wrong, edit the recognized text.")
            ] : []
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
        let notes = assumedPowerNote(parsed.assumedPowers)
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
        guard relation.isInequality else {
            throw MathError.unsupported(detail: l("Знак «≠» не поддерживается.", "The “≠” sign is not supported."))
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
        let notes = assumedPowerNote(parsed.assumedPowers)
        if expr.isConstant {
            return try solveArithmetic(expr, fmt: fmt, notes: notes)
        }
        return try solveSimplification(expr, fmt: fmt, notes: notes)
    }

    private func solveArithmetic(_ expr: Expr, fmt: MathFormatter, notes: [String], environmentNote: String? = nil) throws -> Solution {
        let (value, evaluationSteps) = try evaluator.evaluateWithSteps(expr)
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

    private func solveSimplification(_ expr: Expr, fmt: MathFormatter, notes: [String]) throws -> Solution {
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
            allNotes.append(l("Выражение уже записано в простом виде.", "The expression is already in a simple form."))
        }
        return Solution(
            subject: .math, problemType: l("Упрощение выражения", "Simplifying an expression"),
            interpretedProblem: original, answer: resultText, explanation: explanation, steps: steps,
            reliability: .exact, engine: .math, notes: allNotes)
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
        var notes = assumedPowerNote(parsed.assumedPowers)
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

    private func solveDerivative(_ fragment: String, variableHint: String?, functionName: String?, fmt: MathFormatter) throws -> Solution {
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

        return Solution(
            subject: .math, problemType: l("Производная функции", "Derivative of a function"),
            interpretedProblem: "\(head) = \(fmt.expr(expr))", answer: "\(primeHead) = \(resultText)",
            explanation: l(
                "Производная показывает скорость изменения функции. Её находят по таблице производных и правилам дифференцирования суммы, произведения, частного и сложной функции.",
                "The derivative shows how fast a function changes. It is found from the table of derivatives and the sum, product, quotient and chain rules."
            ),
            steps: steps, formulas: rules.map { Differentiator.ruleText($0, l) }, reliability: .exact, engine: .math,
            notes: assumedPowerNote(parsed.assumedPowers))
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

    private func solveIntegral(_ fragment: String, variableHint: String?, lower: String, fmt: MathFormatter) throws -> Solution {
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
        let number = "(-?\\d+(?:[.,]\\d+)?)"
        let boundsPattern = "(?:от|from)\\s+\(number)\\s+(?:до|to)\\s+\(number)"
        let normalizedLower = MathNormalizer.normalize(lower)
        if let match = Rx.first(boundsPattern, in: normalizedLower), let a = Rational(decimal: match[1].replacingOccurrences(of: "-", with: "")),
            let b = Rational(decimal: match[2].replacingOccurrences(of: "-", with: ""))
        {
            let lowerBound = match[1].hasPrefix("-") ? a.negated : a
            let upperBound = match[2].hasPrefix("-") ? b.negated : b
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
                notes: assumedPowerNote(parsed.assumedPowers))
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
            steps: steps, formulas: formulas, reliability: .exact, engine: .math, notes: assumedPowerNote(parsed.assumedPowers))
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
        var solution = try solveArithmetic(substituted, fmt: fmt, notes: assumedPowerNote(parsed.assumedPowers), environmentNote: note)
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

    // MARK: - Divisibility

    private func factorizationText(_ value: Int, _ fmt: MathFormatter) -> String {
        let factors = IntegerMath.primeFactors(value)
        guard !factors.isEmpty else { return String(value) }
        return factors.map { $0.power == 1 ? "\($0.prime)" : "\($0.prime)\(fmt.superscript($0.power))" }.joined(separator: "·")
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
        let numbers = Rx.matches("(?<![\\d.,])\\d{1,12}(?![\\d.,]\\d)", in: lower).compactMap { Int($0[0]) }.filter { $0 > 0 }
        guard !numbers.isEmpty else { return nil }

        if wantsPrimes, !wantsGCD, !wantsLCM, let value = numbers.first, value > 1 {
            var steps: [SolutionStep] = []
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
                    l("Делим на наименьший простой делитель, пока не получим 1", "Divide by the smallest prime divisor until we reach 1"),
                    formula: lines.joined(separator: "\n")))
            let answer = "\(value) = \(factorizationText(value, fmt))"
            steps.append(SolutionStep(l("Запишем произведение", "Write the product"), formula: answer))
            return Solution(
                subject: .math, problemType: l("Разложение на простые множители", "Prime factorization"),
                interpretedProblem: "\(value)", answer: answer,
                explanation: l(
                    "Любое натуральное число больше 1 единственным образом раскладывается в произведение простых чисел.",
                    "Every natural number greater than 1 factors uniquely into a product of primes."),
                steps: steps, reliability: .exact, engine: .math)
        }

        guard numbers.count >= 2, numbers.count <= 6 else { return nil }
        var steps: [SolutionStep] = [
            SolutionStep(
                l("Разложим числа на простые множители", "Factor the numbers into primes"),
                formula: numbers.map { "\($0) = \(factorizationText($0, fmt))" }.joined(separator: "\n"))
        ]
        var answers: [String] = []
        let listed = numbers.map(String.init).joined(separator: "; ")
        if wantsGCD {
            let gcd = numbers.dropFirst().reduce(numbers[0]) { Rational.gcd($0, $1) }
            steps.append(
                SolutionStep(
                    l("НОД: берём общие простые множители с наименьшими показателями", "GCD: take the common prime factors with the smallest exponents"),
                    formula: l("НОД(\(listed)) = \(factorizationText(gcd, fmt)) = \(gcd)", "gcd(\(listed)) = \(factorizationText(gcd, fmt)) = \(gcd)")))
            answers.append(l("НОД = \(gcd)", "GCD = \(gcd)"))
        }
        if wantsLCM {
            var lcm = numbers[0]
            for value in numbers.dropFirst() {
                guard let next = try? Rational.lcm(lcm, value) else { return nil }
                lcm = next
            }
            steps.append(
                SolutionStep(
                    l("НОК: берём все простые множители с наибольшими показателями", "LCM: take all prime factors with the largest exponents"),
                    formula: l("НОК(\(listed)) = \(factorizationText(lcm, fmt)) = \(lcm)", "lcm(\(listed)) = \(factorizationText(lcm, fmt)) = \(lcm)")))
            answers.append(l("НОК = \(lcm)", "LCM = \(lcm)"))
        }
        return Solution(
            subject: .math, problemType: l("Делимость чисел", "Divisibility"),
            interpretedProblem: listed, answer: answers.joined(separator: "; "),
            explanation: l(
                "НОД — наибольшее число, на которое делятся все данные числа. НОК — наименьшее число, которое делится на каждое из них.",
                "The GCD is the largest number dividing all the given numbers. The LCM is the smallest number divisible by each of them."),
            steps: steps, reliability: .exact, engine: .math)
    }
}
