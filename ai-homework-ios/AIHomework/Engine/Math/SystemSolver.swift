import Foundation

struct SystemOutcome: Sendable {
    var kindTitle: String
    var answer: String
    var explanation: String
    var steps: [SolutionStep]
    var notes: [String]
    var isApproximate: Bool
}

/// Системы уравнений: линейные (метод сложения / Гаусса) и простые нелинейные (подстановка).
struct SystemSolver: Sendable {
    let l: L10n
    let fmt: MathFormatter

    init(lang: AppLanguage, formatter: MathFormatter) {
        l = L10n(lang)
        fmt = formatter
    }

    func solve(_ equations: [(lhs: Expr, rhs: Expr)]) throws -> SystemOutcome {
        var polynomials: [Polynomial] = []
        for equation in equations {
            guard let polynomial = try Algebra.polynomial(.sub(equation.lhs, equation.rhs)) else {
                throw MathError.unsupported(
                    detail: l(
                        "Локальный движок решает системы только из многочленов (без корней, дробей с переменной и функций).",
                        "The local engine solves only polynomial systems (no roots, variable denominators or functions)."))
            }
            polynomials.append(polynomial)
        }
        let variables = Set(polynomials.flatMap { $0.variables }).sorted()
        guard !variables.isEmpty else {
            throw MathError.unsupported(detail: l("В системе нет неизвестных.", "The system has no unknowns."))
        }
        guard variables.count <= 4, equations.count <= 4 else {
            throw MathError.unsupported(
                detail: l("Поддерживаются системы не более чем с четырьмя неизвестными.", "Systems with at most four unknowns are supported."))
        }

        let written = equations.map { "\(fmt.expr($0.lhs)) = \(fmt.expr($0.rhs))" }.joined(separator: "\n")
        let steps = [SolutionStep(l("Запишем систему", "Write the system"), formula: written)]

        if polynomials.allSatisfy({ $0.totalDegree <= 1 }) {
            return try solveLinear(polynomials, variables: variables, steps: steps)
        }
        if polynomials.count == 2, variables.count == 2 {
            return try solveBySubstitution(polynomials, variables: variables, steps: steps)
        }
        throw MathError.unsupported(
            detail: l(
                "Нелинейные системы поддерживаются только для двух уравнений с двумя неизвестными.",
                "Nonlinear systems are supported only for two equations in two unknowns."))
    }

    // MARK: - Linear systems

    /// Строка расширенной матрицы: коэффициенты при неизвестных и правая часть.
    private struct Row {
        var coefficients: [Rational]
        var constant: Rational
    }

    private func rowText(_ row: Row, _ variables: [String]) -> String {
        var terms: [Monomial: Rational] = [:]
        for (index, name) in variables.enumerated() {
            terms[Monomial(variable: name)] = row.coefficients[index]
        }
        return "\(fmt.polynomial(Polynomial(terms: terms))) = \(fmt.rational(row.constant))"
    }

    private func systemText(_ rows: [Row], _ variables: [String]) -> String {
        rows.map { rowText($0, variables) }.joined(separator: "\n")
    }

    private func solveLinear(_ polynomials: [Polynomial], variables: [String], steps initial: [SolutionStep]) throws -> SystemOutcome {
        var steps = initial
        var rows: [Row] = polynomials.map { polynomial in
            Row(coefficients: variables.map { polynomial.coefficient(ofLinear: $0) }, constant: polynomial.constantTerm.negated)
        }
        let standard = systemText(rows, variables)
        if standard != steps.last?.formula {
            steps.append(
                SolutionStep(
                    l("Приведём уравнения к стандартному виду", "Bring the equations to standard form"),
                    l("Неизвестные — слева, числа — справа.", "Unknowns on the left, numbers on the right."),
                    formula: standard))
        }

        if rows.count == 2, variables.count == 2 {
            if let outcome = try solveTwoByTwo(rows, variables: variables, steps: steps) {
                return outcome
            }
        }

        // Метод Гаусса.
        let n = variables.count
        var pivotColumns: [Int] = []
        var pivotRow = 0
        var operations: [String] = []
        for column in 0..<n where pivotRow < rows.count {
            guard let source = (pivotRow..<rows.count).first(where: { !rows[$0].coefficients[column].isZero }) else { continue }
            if source != pivotRow {
                rows.swapAt(source, pivotRow)
                operations.append(l("Меняем местами уравнения (\(pivotRow + 1)) и (\(source + 1)).", "Swap equations (\(pivotRow + 1)) and (\(source + 1))."))
            }
            let pivot = rows[pivotRow].coefficients[column]
            for index in 0..<rows.count where index != pivotRow {
                let factor = try rows[index].coefficients[column] / pivot
                guard !factor.isZero else { continue }
                for k in 0..<n {
                    rows[index].coefficients[k] = try rows[index].coefficients[k] - (try factor * rows[pivotRow].coefficients[k])
                }
                rows[index].constant = try rows[index].constant - (try factor * rows[pivotRow].constant)
                operations.append(
                    l(
                        "Из уравнения (\(index + 1)) вычитаем уравнение (\(pivotRow + 1)), умноженное на \(fmt.rational(factor)) — исчезает \(variables[column]).",
                        "Subtract equation (\(pivotRow + 1)) times \(fmt.rational(factor)) from equation (\(index + 1)) — \(variables[column]) is eliminated."
                    ))
            }
            pivotColumns.append(column)
            pivotRow += 1
        }
        steps.append(
            SolutionStep(
                l("Исключаем неизвестные методом Гаусса", "Eliminate unknowns by Gaussian elimination"),
                operations.joined(separator: "\n"),
                formula: systemText(rows, variables)))

        // Противоречие: 0 = c.
        if rows.contains(where: { row in row.coefficients.allSatisfy { $0.isZero } && !row.constant.isZero }) {
            steps.append(
                SolutionStep(
                    l("Получили неверное равенство", "We get a false statement"),
                    l("Одно из уравнений превратилось в 0 = число, не равное нулю.", "One equation turned into 0 = a nonzero number.")))
            return SystemOutcome(
                kindTitle: l("Система линейных уравнений", "System of linear equations"),
                answer: l("Система не имеет решений", "The system has no solutions"),
                explanation: l("Уравнения противоречат друг другу.", "The equations contradict each other."),
                steps: steps, notes: [], isApproximate: false)
        }
        if pivotColumns.count < n {
            return SystemOutcome(
                kindTitle: l("Система линейных уравнений", "System of linear equations"),
                answer: l("Система имеет бесконечно много решений", "The system has infinitely many solutions"),
                explanation: l(
                    "Независимых уравнений меньше, чем неизвестных, поэтому одно из неизвестных можно выбрать произвольно.",
                    "There are fewer independent equations than unknowns, so one unknown can be chosen freely."),
                steps: steps, notes: [], isApproximate: false)
        }

        var values: [String: Rational] = [:]
        for (rowIndex, column) in pivotColumns.enumerated() {
            values[variables[column]] = try rows[rowIndex].constant / rows[rowIndex].coefficients[column]
        }
        steps.append(
            SolutionStep(
                l("Находим неизвестные", "Find the unknowns"),
                formula: variables.map { "\($0) = \(fmt.rationalWithApproximation(values[$0] ?? .zero))" }.joined(separator: "\n")))
        return try finishLinear(values, variables: variables, polynomials: polynomials, steps: steps)
    }

    /// Метод сложения для системы 2×2. `nil` — если определитель равен нулю (разбирает общий метод).
    private func solveTwoByTwo(_ rows: [Row], variables: [String], steps initial: [SolutionStep]) throws -> SystemOutcome? {
        var steps = initial
        let (x, y) = (variables[0], variables[1])
        let (a1, b1, c1) = (rows[0].coefficients[0], rows[0].coefficients[1], rows[0].constant)
        let (a2, b2, c2) = (rows[1].coefficients[0], rows[1].coefficients[1], rows[1].constant)
        let determinant = try (try a1 * b2) - (try a2 * b1)
        guard !determinant.isZero else { return nil }

        let xValue: Rational
        if b1.isZero {
            xValue = try c1 / a1
            steps.append(
                SolutionStep(
                    l("В первом уравнении только одно неизвестное", "The first equation has only one unknown"),
                    formula: "\(x) = \(fmt.rationalWithApproximation(xValue))"))
        } else if b2.isZero {
            xValue = try c2 / a2
            steps.append(
                SolutionStep(
                    l("Во втором уравнении только одно неизвестное", "The second equation has only one unknown"),
                    formula: "\(x) = \(fmt.rationalWithApproximation(xValue))"))
        } else {
            // Уравниваем коэффициенты при y и вычитаем.
            let m1 = b2
            let m2 = b1
            let first = Row(coefficients: [try a1 * m1, try b1 * m1], constant: try c1 * m1)
            let second = Row(coefficients: [try a2 * m2, try b2 * m2], constant: try c2 * m2)
            if m1 != .one || m2 != .one {
                steps.append(
                    SolutionStep(
                        l("Уравняем коэффициенты при \(y)", "Make the coefficients of \(y) equal"),
                        l(
                            "Первое уравнение умножим на \(fmt.rational(m1)), второе — на \(fmt.rational(m2)).",
                            "Multiply the first equation by \(fmt.rational(m1)) and the second by \(fmt.rational(m2))."),
                        formula: systemText([first, second], variables)))
            }
            let combinedA = try first.coefficients[0] - second.coefficients[0]
            let combinedC = try first.constant - second.constant
            xValue = try combinedC / combinedA
            steps.append(
                SolutionStep(
                    l("Вычтем из первого уравнения второе", "Subtract the second equation from the first"),
                    l("Слагаемые с \(y) взаимно уничтожаются.", "The terms with \(y) cancel out."),
                    formula:
                        "\(fmt.polynomial(Polynomial(coefficients: [.zero, combinedA], variable: x))) = \(fmt.rational(combinedC))\n\(x) = \(fmt.rationalWithApproximation(xValue))"
                ))
        }

        // Подставляем x в уравнение, где есть y.
        let useFirst = !b1.isZero
        let (a, b, c) = useFirst ? (a1, b1, c1) : (a2, b2, c2)
        let yValue = try (try c - (try a * xValue)) / b
        steps.append(
            SolutionStep(
                l(
                    "Подставим \(x) в \(useFirst ? "первое" : "второе") уравнение",
                    "Substitute \(x) into the \(useFirst ? "first" : "second") equation"),
                formula:
                    "\(fmt.rational(a))·\(wrapNegative(xValue)) + \(wrapNegative(b))·\(y) = \(fmt.rational(c))\n\(y) = \(fmt.rationalWithApproximation(yValue))"
            ))
        return try finishLinear([x: xValue, y: yValue], variables: variables, polynomials: nil, steps: steps, rows: rows)
    }

    private func wrapNegative(_ value: Rational) -> String {
        value.isNegative ? "(\(fmt.rational(value)))" : fmt.rational(value)
    }

    private func finishLinear(
        _ values: [String: Rational], variables: [String], polynomials: [Polynomial]?, steps initial: [SolutionStep], rows: [Row]? = nil
    ) throws -> SystemOutcome {
        var steps = initial
        // Проверка: подставляем в исходные уравнения.
        var checks: [String] = []
        var valid = true
        if let polynomials {
            for polynomial in polynomials {
                let residual = try polynomial.evaluate(values)
                valid = valid && residual.isZero
            }
        }
        if let rows {
            for row in rows {
                var sum = Rational.zero
                for (index, name) in variables.enumerated() {
                    sum = try sum + (try row.coefficients[index] * (values[name] ?? .zero))
                }
                valid = valid && sum == row.constant
                checks.append("\(fmt.rational(sum)) = \(fmt.rational(row.constant)) ✓")
            }
        }
        guard valid else {
            throw MathError.unsupported(
                detail: l(
                    "Найденное решение не прошло проверку подстановкой, поэтому ответ не показан.",
                    "The solution failed the substitution check, so no answer is shown."))
        }
        steps.append(
            SolutionStep(
                l("Проверка подстановкой", "Check by substitution"),
                l("Подставляем найденные значения в каждое уравнение системы.", "Substitute the values into every equation of the system."),
                formula: checks.isEmpty ? nil : checks.joined(separator: "\n")))

        let answer = variables.map { "\($0) = \(fmt.rationalWithApproximation(values[$0] ?? .zero))" }.joined(separator: "; ")
        return SystemOutcome(
            kindTitle: l("Система линейных уравнений", "System of linear equations"),
            answer: answer,
            explanation: l(
                "Идея — избавиться от одного неизвестного: складываем или вычитаем уравнения так, чтобы оно исчезло, находим второе, а затем возвращаемся к первому.",
                "The idea is to get rid of one unknown: add or subtract the equations so that it disappears, find the other one, then go back for the first."
            ),
            steps: steps, notes: [], isApproximate: false)
    }

    // MARK: - Nonlinear 2×2 by substitution

    private func solveBySubstitution(_ polynomials: [Polynomial], variables: [String], steps initial: [SolutionStep]) throws -> SystemOutcome {
        var steps = initial

        // Ищем уравнение и переменную, которую легко выразить: входит только в первой степени
        // с числовым коэффициентом.
        var choice: (equation: Int, variable: String, coefficient: Rational)?
        search: for (index, polynomial) in polynomials.enumerated() {
            for name in variables where polynomial.degree(in: name) == 1 {
                let coefficient = polynomial.coefficient(ofLinear: name)
                let mixed = polynomial.terms.keys.contains { $0.degree(in: name) == 1 && $0.degree > 1 }
                if !coefficient.isZero, !mixed {
                    choice = (index, name, coefficient)
                    break search
                }
            }
        }
        guard let choice else {
            throw MathError.unsupported(
                detail: l(
                    "Ни одно из уравнений не позволяет просто выразить одну переменную через другую — такую систему локальный движок не решает.",
                    "Neither equation lets one variable be expressed simply through the other — the local engine cannot solve this system."))
        }
        let expressed = choice.variable
        guard let other = variables.first(where: { $0 != expressed }) else {
            throw MathError.unsupported(detail: l("В системе одно неизвестное.", "The system has one unknown."))
        }
        let source = polynomials[choice.equation]
        let target = polynomials[1 - choice.equation]

        // source = coefficient·expressed + rest = 0  ⇒  expressed = −rest / coefficient
        let rest = try source - Polynomial(terms: [Monomial(variable: expressed): choice.coefficient])
        let expression = try rest.negated.divided(by: choice.coefficient)
        steps.append(
            SolutionStep(
                l(
                    "Выразим \(expressed) из \(choice.equation == 0 ? "первого" : "второго") уравнения",
                    "Express \(expressed) from the \(choice.equation == 0 ? "first" : "second") equation"),
                formula: "\(expressed) = \(fmt.polynomial(expression))"))

        let substituted = try target.substituting(expressed, with: expression)
        steps.append(
            SolutionStep(
                l("Подставим в другое уравнение", "Substitute into the other equation"),
                l("Получаем уравнение с одним неизвестным \(other).", "We get an equation in the single unknown \(other)."),
                formula: "\(fmt.polynomial(substituted)) = 0"))

        guard let coefficients = substituted.coefficients(in: other) else {
            throw MathError.unsupported(detail: l("Не удалось исключить переменную.", "Could not eliminate the variable."))
        }
        let degree = UnivariatePolynomial.degree(coefficients)
        var roots: [RootValue] = []
        var formulas: [String] = []
        var approximate = false
        if degree == 0 {
            let consistent = coefficients[0].isZero
            return SystemOutcome(
                kindTitle: l("Система уравнений", "System of equations"),
                answer: consistent
                    ? l("Система имеет бесконечно много решений", "The system has infinitely many solutions")
                    : l("Система не имеет решений", "The system has no solutions"),
                explanation: consistent
                    ? l("После подстановки получилось верное равенство 0 = 0.", "After substitution we get the true statement 0 = 0.")
                    : l("После подстановки получилось неверное числовое равенство.", "After substitution we get a false numeric statement."),
                steps: steps, notes: [], isApproximate: false)
        } else if degree == 1 {
            roots = [.rational(try coefficients[0].negated / coefficients[1])]
        } else {
            let equationSolver = EquationSolver(lang: l.lang, formatter: fmt)
            roots = try equationSolver.polynomialRootsWithSteps(
                coefficients, variable: other, steps: &steps, formulas: &formulas, approximate: &approximate)
        }
        guard !roots.isEmpty else {
            steps.append(SolutionStep(l("Действительных корней нет", "There are no real roots")))
            return SystemOutcome(
                kindTitle: l("Система уравнений", "System of equations"),
                answer: l("Система не имеет действительных решений", "The system has no real solutions"),
                explanation: l("Уравнение после подстановки не имеет действительных корней.", "The equation obtained after substitution has no real roots."),
                steps: steps, notes: [], isApproximate: false)
        }

        // Обратная подстановка.
        var pairs: [String] = []
        var backLines: [String] = []
        for root in roots {
            let expressedText: String
            if case .rational(let value) = root {
                let result = try expression.evaluate([other: value])
                expressedText = fmt.rationalWithApproximation(result)
                pairs.append(pairText(variables, [other: fmt.rational(value), expressed: fmt.rational(result)]))
            } else {
                approximate = approximate || !root.isExact
                let result = expression.evaluate([other: root.double])
                expressedText = "≈ " + fmt.approx(result)
                pairs.append(pairText(variables, [other: fmt.approx(root.double), expressed: fmt.approx(result)], approximate: true))
            }
            backLines.append("\(other) = \(fmt.root(root)) ⇒ \(expressed) \(expressedText.hasPrefix("≈") ? "" : "= ")\(expressedText)")
        }
        steps.append(
            SolutionStep(
                l("Найдём \(expressed) для каждого значения \(other)", "Find \(expressed) for each value of \(other)"),
                formula: backLines.joined(separator: "\n")))

        var notes: [String] = []
        if approximate {
            notes.append(l("Часть значений найдена приближённо.", "Some values are approximate."))
        }
        return SystemOutcome(
            kindTitle: l("Система уравнений", "System of equations"),
            answer: "(\(variables.joined(separator: "; "))): " + pairs.joined(separator: ", "),
            explanation: l(
                "Метод подстановки: из одного уравнения выражаем одну переменную и подставляем в другое — остаётся уравнение с одним неизвестным.",
                "The substitution method: express one variable from one equation and substitute it into the other — an equation in one unknown remains."
            ),
            steps: steps, notes: notes, isApproximate: approximate)
    }

    private func pairText(_ variables: [String], _ values: [String: String], approximate: Bool = false) -> String {
        (approximate ? "≈ " : "") + "(" + variables.map { values[$0] ?? "?" }.joined(separator: "; ") + ")"
    }
}
