import Foundation

/// Вычислительное ядро: вещественные корни многочленов с рациональными коэффициентами.
enum PolynomialRootFinder {
    /// Различные вещественные корни по возрастанию. Точные, где это возможно.
    static func realRoots(_ coefficients: [Rational]) throws -> [RootValue] {
        let c = UnivariatePolynomial.trimmed(coefficients)
        guard c.count > 1 else { return [] }
        let extraction = try UnivariatePolynomial.extractRationalRoots(c)
        var roots: [RootValue] = Set(extraction.roots).map { RootValue.rational($0) }
        let remaining = extraction.remaining
        let degree = remaining.count - 1
        if degree == 2 {
            roots += try quadraticRoots(a: remaining[2], b: remaining[1], c: remaining[0])
        } else if degree > 2 {
            if let biquadratic = try biquadraticRoots(remaining) {
                roots += biquadratic
            } else {
                roots += Algebra.realRoots(remaining.map { $0.doubleValue }).map { RootValue.approx($0) }
            }
        }
        return sortedDistinct(roots)
    }

    static func sortedDistinct(_ roots: [RootValue]) -> [RootValue] {
        var result: [RootValue] = []
        for root in roots.sorted(by: { $0.double < $1.double }) {
            if let last = result.last, abs(last.double - root.double) <= 1e-9 * max(1, abs(root.double)) {
                // Из двух совпадающих оставляем точный.
                if !last.isExact, root.isExact { result[result.count - 1] = root }
                continue
            }
            result.append(root)
        }
        return result
    }

    /// Корни `ax² + bx + c = 0` в точном виде.
    static func quadraticRoots(a: Rational, b: Rational, c: Rational) throws -> [RootValue] {
        guard !a.isZero else {
            guard !b.isZero else { return [] }
            return [.rational(try c.negated / b)]
        }
        let discriminant = try (try b * b) - (try Rational(4) * (try a * c))
        if discriminant.isNegative { return [] }
        let twoA = try Rational.two * a
        let center = try b.negated / twoA
        if discriminant.isZero { return [.rational(center)] }
        let scale = try twoA.reciprocal()
        let first = try Surd.make(rationalPart: center, coefficient: scale.negated, sqrtOf: discriminant)
        let second = try Surd.make(rationalPart: center, coefficient: scale, sqrtOf: discriminant)
        return [first, second].sorted { $0.double < $1.double }
    }

    /// Биквадратное уравнение `ax⁴ + bx² + c = 0` через замену `t = x²`.
    static func biquadraticRoots(_ c: [Rational]) throws -> [RootValue]? {
        guard c.count == 5, c[1].isZero, c[3].isZero else { return nil }
        var roots: [RootValue] = []
        for t in try quadraticRoots(a: c[4], b: c[2], c: c[0]) {
            switch t {
            case .rational(let value):
                if value.isZero {
                    roots.append(.rational(.zero))
                } else if value.isPositive {
                    roots.append(try Surd.make(rationalPart: .zero, coefficient: .one, sqrtOf: value))
                    roots.append(try Surd.make(rationalPart: .zero, coefficient: .minusOne, sqrtOf: value))
                }
            default:
                let value = t.double
                if value > 0 {
                    roots.append(.approx(value.squareRoot()))
                    roots.append(.approx(-value.squareRoot()))
                }
            }
        }
        return roots
    }
}

/// Результат решения уравнения вместе с объяснением.
struct EquationOutcome: Sendable {
    enum SolutionSet: Sendable, Equatable {
        case roots([RootValue])
        case none
        case all
    }

    var kindTitle: String
    var set: SolutionSet
    var answer: String
    var explanation: String
    var steps: [SolutionStep]
    var formulas: [String]
    var notes: [String]
    var isApproximate: Bool

    var roots: [RootValue] {
        if case .roots(let values) = set { return values }
        return []
    }
}

/// Решение уравнений с одной неизвестной и пошаговым объяснением.
struct EquationSolver: Sendable {
    let l: L10n
    let fmt: MathFormatter
    private let evaluator = MathEvaluator()

    init(lang: AppLanguage, formatter: MathFormatter) {
        l = L10n(lang)
        fmt = formatter
    }

    // MARK: - Entry point

    func solve(lhs: Expr, rhs: Expr, variable x: String) throws -> EquationOutcome {
        let original = "\(fmt.expr(lhs)) = \(fmt.expr(rhs))"
        let difference = Expr.sub(lhs, rhs)

        guard let function = try Algebra.rationalFunction(difference) else {
            return try solveNumerically(lhs: lhs, rhs: rhs, variable: x, original: original)
        }

        let variables = Set(function.numerator.variables).union(function.denominator.variables)
        if !variables.subtracting([x]).isEmpty {
            return try solveParametric(function, variable: x, original: original)
        }

        if let polynomial = try function.asPolynomial() {
            return try solvePolynomialEquation(polynomial, lhs: lhs, rhs: rhs, variable: x, original: original)
        }
        return try solveRationalEquation(function, lhs: lhs, rhs: rhs, variable: x, original: original)
    }

    // MARK: - Polynomial equations

    private func solvePolynomialEquation(
        _ polynomial: Polynomial, lhs: Expr, rhs: Expr, variable x: String, original: String
    ) throws -> EquationOutcome {
        let coefficients = polynomial.coefficients(in: x) ?? [polynomial.constantTerm]
        let degree = UnivariatePolynomial.degree(coefficients)
        var steps: [SolutionStep] = [SolutionStep(l("Запишем уравнение", "Write the equation"), formula: original)]

        switch degree {
        case 0:
            let isIdentity = coefficients[0].isZero
            let simplified = "\(fmt.rational(coefficients[0])) = 0"
            steps.append(
                SolutionStep(
                    l("Перенесём всё в левую часть и упростим", "Move everything to the left side and simplify"),
                    l("Переменная сократилась.", "The variable cancels out."),
                    formula: simplified))
            if isIdentity {
                steps.append(
                    SolutionStep(
                        l("Получили верное равенство", "We get a true statement"),
                        l(
                            "Равенство выполняется при любом значении \(x).",
                            "The equality holds for every value of \(x).")))
                return outcome(
                    kind: l("Тождество", "Identity"),
                    set: .all,
                    answer: l("\(x) — любое число", "\(x) is any number"),
                    explanation: l(
                        "После упрощения переменная исчезает и остаётся верное равенство 0 = 0, значит подходит любое число.",
                        "After simplification the variable disappears and the true statement 0 = 0 remains, so any number works."),
                    steps: steps)
            }
            steps.append(
                SolutionStep(
                    l("Получили неверное равенство", "We get a false statement"),
                    l("Ни одно значение \(x) не подходит.", "No value of \(x) satisfies it.")))
            return outcome(
                kind: l("Уравнение без решений", "Equation with no solutions"),
                set: .none,
                answer: l("Нет решений", "No solutions"),
                explanation: l(
                    "После упрощения переменная исчезает и остаётся неверное числовое равенство, поэтому корней нет.",
                    "After simplification the variable disappears and a false numeric statement remains, so there are no roots."),
                steps: steps)

        case 1:
            return try solveLinear(coefficients, lhs: lhs, rhs: rhs, variable: x, steps: steps)

        default:
            let standard = "\(fmt.polynomial(polynomial)) = 0"
            if standard != original {
                steps.append(
                    SolutionStep(
                        l(
                            "Перенесём все слагаемые в левую часть и приведём подобные",
                            "Move all terms to the left side and combine like terms"),
                        formula: standard))
            }
            var formulas: [String] = []
            var approximate = false
            let roots = try polynomialRootsWithSteps(
                coefficients, variable: x, steps: &steps, formulas: &formulas, approximate: &approximate)
            let kind: String
            switch degree {
            case 2: kind = l("Квадратное уравнение", "Quadratic equation")
            case 3: kind = l("Кубическое уравнение", "Cubic equation")
            default: kind = l("Уравнение \(degree)-й степени", "Degree-\(degree) equation")
            }
            return finish(
                kind: kind, roots: roots, lhs: lhs, rhs: rhs, variable: x, steps: steps, formulas: formulas,
                approximate: approximate,
                explanation: degree == 2
                    ? l(
                        "Квадратное уравнение решается через дискриминант: он показывает, сколько у уравнения корней, и позволяет найти их по формуле.",
                        "A quadratic equation is solved with the discriminant: it tells how many roots exist and lets us compute them with the quadratic formula."
                    )
                    : l(
                        "Сначала ищем рациональные корни среди делителей свободного члена, затем делим многочлен на найденные множители и решаем то, что осталось.",
                        "First we look for rational roots among the divisors of the constant term, then divide the polynomial by the factors found and solve what remains."
                    ))
        }
    }

    private func solveLinear(
        _ coefficients: [Rational], lhs: Expr, rhs: Expr, variable x: String, steps initialSteps: [SolutionStep]
    ) throws -> EquationOutcome {
        var steps = initialSteps
        let a = coefficients[1]
        let b = coefficients[0]

        if let left = try Algebra.polynomial(lhs), let right = try Algebra.polynomial(rhs) {
            let expanded = "\(fmt.polynomial(left)) = \(fmt.polynomial(right))"
            if expanded != steps.last?.formula {
                steps.append(
                    SolutionStep(
                        l("Раскроем скобки и приведём подобные слагаемые", "Expand brackets and combine like terms"),
                        formula: expanded))
            }
            let leftX = left.coefficient(ofLinear: x)
            let rightX = right.coefficient(ofLinear: x)
            let leftConstant = left.constantTerm
            let rightConstant = right.constantTerm
            if !rightX.isZero || !leftConstant.isZero {
                let movedLeft = try Polynomial(coefficients: [.zero, leftX], variable: x)
                    - Polynomial(coefficients: [.zero, rightX], variable: x)
                let movedRight = try rightConstant - leftConstant
                steps.append(
                    SolutionStep(
                        l(
                            "Перенесём слагаемые с \(x) влево, а числа — вправо",
                            "Move the terms with \(x) to the left and the numbers to the right"),
                        l(
                            "При переносе через знак «=» слагаемое меняет знак.",
                            "A term changes its sign when it crosses the “=” sign."),
                        formula: "\(fmt.polynomial(movedLeft)) = \(fmt.rational(movedRight))"))
            }
        } else {
            let standard = Polynomial(coefficients: coefficients, variable: x)
            steps.append(
                SolutionStep(
                    l("Приведём уравнение к виду ax + b = 0", "Bring the equation to the form ax + b = 0"),
                    formula: "\(fmt.polynomial(standard)) = 0"))
        }

        let root = try b.negated / a
        if a != .one {
            steps.append(
                SolutionStep(
                    l("Разделим обе части на коэффициент при \(x)", "Divide both sides by the coefficient of \(x)"),
                    l("Коэффициент равен \(fmt.rational(a)).", "The coefficient is \(fmt.rational(a))."),
                    formula: "\(x) = \(fmt.rational(b.negated)) : \(wrapNegative(a)) = \(fmt.rationalWithApproximation(root))"))
        } else {
            steps.append(SolutionStep(l("Получаем корень", "We get the root"), formula: "\(x) = \(fmt.rationalWithApproximation(root))"))
        }

        return finish(
            kind: l("Линейное уравнение", "Linear equation"),
            roots: [.rational(root)], lhs: lhs, rhs: rhs, variable: x, steps: steps, formulas: [], approximate: false,
            explanation: l(
                "В линейном уравнении неизвестное собирают в одной части, числа — в другой, а затем делят на коэффициент при неизвестном.",
                "In a linear equation we collect the unknown on one side and the numbers on the other, then divide by the coefficient of the unknown."
            ))
    }

    private func wrapNegative(_ value: Rational) -> String {
        value.isNegative ? "(\(fmt.rational(value)))" : fmt.rational(value)
    }

    /// Корни многочлена степени ≥ 2 с записью шагов.
    func polynomialRootsWithSteps(
        _ rawCoefficients: [Rational], variable x: String, steps: inout [SolutionStep], formulas: inout [String],
        approximate: inout Bool
    ) throws -> [RootValue] {
        var coefficients = UnivariatePolynomial.trimmed(rawCoefficients)

        // Целые коэффициенты без общего множителя, старший — положительный.
        let form = try UnivariatePolynomial.integerForm(coefficients)
        var integers = form.coefficients
        var multiplier = form.multiplier
        if let lead = integers.last, lead < 0 {
            integers = integers.map { -$0 }
            multiplier = multiplier.negated
        }
        if multiplier != .one {
            coefficients = integers.map { Rational($0) }
            let action =
                multiplier.isInteger
                ? l("Умножим обе части на \(fmt.rational(multiplier))", "Multiply both sides by \(fmt.rational(multiplier))")
                : l(
                    "Разделим обе части на \(fmt.rational((try? multiplier.reciprocal()) ?? .one))",
                    "Divide both sides by \(fmt.rational((try? multiplier.reciprocal()) ?? .one))")
            steps.append(
                SolutionStep(
                    action,
                    l("Так коэффициенты станут целыми и проще.", "This makes the coefficients simpler integers."),
                    formula: "\(fmt.polynomial(Polynomial(coefficients: coefficients, variable: x))) = 0"))
        }

        let degree = coefficients.count - 1
        if degree == 2 {
            return try quadraticWithSteps(
                a: coefficients[2], b: coefficients[1], c: coefficients[0], variable: x, steps: &steps, formulas: &formulas)
        }

        // Биквадратное уравнение.
        if degree == 4, coefficients[1].isZero, coefficients[3].isZero {
            return try biquadraticWithSteps(coefficients, variable: x, steps: &steps, formulas: &formulas, approximate: &approximate)
        }

        let extraction = try UnivariatePolynomial.extractRationalRoots(coefficients)
        var roots: [RootValue] = Set(extraction.roots).map { RootValue.rational($0) }
        let remaining = extraction.remaining
        let remainingDegree = remaining.count - 1

        if !extraction.roots.isEmpty {
            let found = Set(extraction.roots).sorted().map { fmt.rational($0) }.joined(separator: "; ")
            steps.append(
                SolutionStep(
                    l("Ищем рациональные корни", "Look for rational roots"),
                    l(
                        "Рациональный корень p/q: p — делитель свободного члена, q — делитель старшего коэффициента. Подстановкой проверяем кандидатов. Подходят: \(x) = \(found).",
                        "A rational root p/q has p dividing the constant term and q dividing the leading coefficient. Testing the candidates by substitution gives: \(x) = \(found)."
                    )))
            let factors = extraction.roots.sorted().map { root -> String in
                let factor = Polynomial(coefficients: [root.negated, .one], variable: x)
                return "(\(fmt.polynomial(factor)))"
            }.joined()
            let rest = Polynomial(coefficients: remaining, variable: x)
            if remainingDegree >= 1 {
                steps.append(
                    SolutionStep(
                        l("Разложим многочлен на множители", "Factor the polynomial"),
                        l(
                            "Делим многочлен на найденные линейные множители.",
                            "Divide the polynomial by the linear factors found."),
                        formula: "\(factors)(\(fmt.polynomial(rest))) = 0"))
            } else {
                let leading = remaining[0] == .one ? "" : fmt.rational(remaining[0])
                steps.append(
                    SolutionStep(
                        l("Разложим многочлен на множители", "Factor the polynomial"),
                        formula: "\(leading)\(factors) = 0"))
            }
        }

        if remainingDegree == 2 {
            steps.append(
                SolutionStep(
                    l("Решим оставшееся квадратное уравнение", "Solve the remaining quadratic equation"),
                    formula: "\(fmt.polynomial(Polynomial(coefficients: remaining, variable: x))) = 0"))
            roots += try quadraticWithSteps(
                a: remaining[2], b: remaining[1], c: remaining[0], variable: x, steps: &steps, formulas: &formulas)
        } else if remainingDegree > 2 {
            let numeric = Algebra.realRoots(remaining.map { $0.doubleValue })
            approximate = approximate || !numeric.isEmpty
            let rest = fmt.polynomial(Polynomial(coefficients: remaining, variable: x))
            let listed = numeric.isEmpty ? l("нет", "none") : numeric.map { fmt.approx($0) }.joined(separator: "; ")
            steps.append(
                SolutionStep(
                    l("Оставшийся множитель решаем численно", "Solve the remaining factor numerically"),
                    l(
                        "У многочлена \(rest) нет рациональных корней, поэтому его действительные корни найдены численно (делением отрезка пополам): \(listed).",
                        "The polynomial \(rest) has no rational roots, so its real roots are found numerically (bisection): \(listed)."
                    )))
            roots += numeric.map { RootValue.approx($0) }
        }
        return PolynomialRootFinder.sortedDistinct(roots)
    }

    private func quadraticWithSteps(
        a: Rational, b: Rational, c: Rational, variable x: String, steps: inout [SolutionStep], formulas: inout [String]
    ) throws -> [RootValue] {
        let discriminantFormula = "D = b² − 4ac"
        let rootsFormula = "\(x)₁,₂ = (−b ± √D)/(2a)"
        if !formulas.contains(discriminantFormula) { formulas.append(discriminantFormula) }
        if !formulas.contains(rootsFormula) { formulas.append(rootsFormula) }

        steps.append(
            SolutionStep(
                l("Определим коэффициенты", "Identify the coefficients"),
                formula: "a = \(fmt.rational(a)), b = \(fmt.rational(b)), c = \(fmt.rational(c))"))

        let discriminant = try (try b * b) - (try Rational(4) * (try a * c))
        steps.append(
            SolutionStep(
                l("Вычислим дискриминант", "Compute the discriminant"),
                formula:
                    "D = b² − 4ac = \(wrapNegative(b))² − 4·\(wrapNegative(a))·\(wrapNegative(c)) = \(fmt.rational(discriminant))"))

        let roots = try PolynomialRootFinder.quadraticRoots(a: a, b: b, c: c)
        if discriminant.isNegative {
            steps.append(
                SolutionStep(
                    l("D < 0 — действительных корней нет", "D < 0 — there are no real roots"),
                    l(
                        "Квадратный корень из отрицательного числа не является действительным числом.",
                        "The square root of a negative number is not a real number.")))
        } else if discriminant.isZero, let root = roots.first {
            steps.append(
                SolutionStep(
                    l("D = 0 — уравнение имеет один корень", "D = 0 — the equation has one root"),
                    formula: "\(x) = −b/(2a) = \(fmt.rootWithApproximation(root))"))
        } else if roots.count == 2 {
            let rootOfD: String
            if let exact = discriminant.exactRoot(2) {
                rootOfD = "√D = \(fmt.rational(exact))"
            } else {
                rootOfD = "√D = √\(fmt.rational(discriminant)) ≈ \(fmt.approx(discriminant.doubleValue.squareRoot()))"
            }
            steps.append(
                SolutionStep(
                    l("D > 0 — уравнение имеет два корня", "D > 0 — the equation has two roots"),
                    rootOfD,
                    formula: rootsFormula))
            steps.append(
                SolutionStep(
                    l("Найдём корни", "Find the roots"),
                    formula: "\(x)₁ = \(fmt.rootWithApproximation(roots[0]))\n\(x)₂ = \(fmt.rootWithApproximation(roots[1]))"))
        }
        return roots
    }

    private func biquadraticWithSteps(
        _ c: [Rational], variable x: String, steps: inout [SolutionStep], formulas: inout [String], approximate: inout Bool
    ) throws -> [RootValue] {
        let substituted = Polynomial(coefficients: [c[0], c[2], c[4]], variable: "t")
        steps.append(
            SolutionStep(
                l("Это биквадратное уравнение — сделаем замену", "This is a biquadratic equation — substitute"),
                l("Пусть t = \(x)², тогда t ≥ 0.", "Let t = \(x)², so t ≥ 0."),
                formula: "\(fmt.polynomial(substituted)) = 0"))
        let tRoots = try quadraticWithSteps(a: c[4], b: c[2], c: c[0], variable: "t", steps: &steps, formulas: &formulas)
        var roots: [RootValue] = []
        for t in tRoots {
            let tText = fmt.root(t)
            if t.double < 0 {
                steps.append(
                    SolutionStep(
                        l("Обратная замена: \(x)² = \(tText)", "Back-substitute: \(x)² = \(tText)"),
                        l("Квадрат числа не может быть отрицательным — корней нет.", "A square cannot be negative — no roots.")))
                continue
            }
            var pair: [RootValue]
            if case .rational(let value) = t {
                if value.isZero {
                    pair = [.rational(.zero)]
                } else {
                    pair = [
                        try Surd.make(rationalPart: .zero, coefficient: .minusOne, sqrtOf: value),
                        try Surd.make(rationalPart: .zero, coefficient: .one, sqrtOf: value),
                    ]
                }
            } else {
                approximate = true
                pair = [.approx(-t.double.squareRoot()), .approx(t.double.squareRoot())]
            }
            roots += pair
            steps.append(
                SolutionStep(
                    l("Обратная замена: \(x)² = \(tText)", "Back-substitute: \(x)² = \(tText)"),
                    formula: pair.map { "\(x) = \(fmt.rootWithApproximation($0))" }.joined(separator: "\n")))
        }
        return PolynomialRootFinder.sortedDistinct(roots)
    }

    // MARK: - Rational equations

    private func solveRationalEquation(
        _ function: RationalFunction, lhs: Expr, rhs: Expr, variable x: String, original: String
    ) throws -> EquationOutcome {
        var steps: [SolutionStep] = [SolutionStep(l("Запишем уравнение", "Write the equation"), formula: original)]
        guard let numerator = function.numerator.coefficients(in: x),
            let denominator = function.denominator.coefficients(in: x)
        else {
            throw MathError.unsupported(
                detail: l("Уравнение с несколькими переменными не поддерживается.", "Equations in several variables are not supported."))
        }

        let excluded = try PolynomialRootFinder.realRoots(denominator)
        let excludedText =
            excluded.isEmpty
            ? l("знаменатель не обращается в ноль", "the denominator is never zero")
            : excluded.map { "\(x) ≠ \(fmt.root($0))" }.joined(separator: "; ")
        steps.append(
            SolutionStep(
                l("Найдём область допустимых значений", "Find the domain"),
                l(
                    "Знаменатель не может быть равен нулю: \(excludedText).",
                    "The denominator cannot be zero: \(excludedText).")))

        // Сокращаем числитель на числовой множитель для аккуратной записи.
        let numeratorForm = try UnivariatePolynomial.integerForm(numerator)
        let cleanNumerator = Polynomial(coefficients: numeratorForm.coefficients.map { Rational($0) }, variable: x)
        steps.append(
            SolutionStep(
                l(
                    "Перенесём всё в одну часть и приведём к общему знаменателю",
                    "Move everything to one side and bring to a common denominator"),
                l(
                    "Дробь равна нулю, когда её числитель равен нулю, а знаменатель — нет. Приравняем числитель к нулю.",
                    "A fraction is zero when its numerator is zero and its denominator is not. Set the numerator to zero."),
                formula: "\(fmt.polynomial(cleanNumerator)) = 0"))

        let coefficients = numeratorForm.coefficients.map { Rational($0) }
        let degree = coefficients.count - 1
        var formulas: [String] = []
        var approximate = false
        var candidates: [RootValue] = []
        if degree == 0 {
            candidates = []
        } else if degree == 1 {
            let root = try coefficients[0].negated / coefficients[1]
            candidates = [.rational(root)]
            steps.append(SolutionStep(l("Решим линейное уравнение", "Solve the linear equation"), formula: "\(x) = \(fmt.rationalWithApproximation(root))"))
        } else {
            candidates = try polynomialRootsWithSteps(
                coefficients, variable: x, steps: &steps, formulas: &formulas, approximate: &approximate)
        }

        var roots: [RootValue] = []
        var extraneous: [RootValue] = []
        for candidate in candidates {
            let isExcluded = excluded.contains { abs($0.double - candidate.double) <= 1e-9 * max(1, abs(candidate.double)) }
            if isExcluded {
                extraneous.append(candidate)
            } else {
                roots.append(candidate)
            }
        }
        if !extraneous.isEmpty {
            let listed = extraneous.map { fmt.root($0) }.joined(separator: "; ")
            steps.append(
                SolutionStep(
                    l("Отбросим посторонние корни", "Discard extraneous roots"),
                    l(
                        "\(x) = \(listed) не входит в область допустимых значений (знаменатель обращается в ноль).",
                        "\(x) = \(listed) is outside the domain (the denominator becomes zero).")))
        }

        return finish(
            kind: l("Дробно-рациональное уравнение", "Rational equation"),
            roots: roots, lhs: lhs, rhs: rhs, variable: x, steps: steps, formulas: formulas, approximate: approximate,
            explanation: l(
                "В уравнении с дробями сначала находят значения, при которых знаменатель равен нулю (они запрещены), затем приравнивают числитель к нулю и отбрасывают запрещённые корни.",
                "In an equation with fractions we first find the values that make a denominator zero (they are forbidden), then set the numerator to zero and discard forbidden roots."
            ))
    }

    // MARK: - Parametric (literal) linear equations

    private func solveParametric(_ function: RationalFunction, variable x: String, original: String) throws -> EquationOutcome {
        guard let polynomial = try function.asPolynomial(), polynomial.degree(in: x) == 1 else {
            throw MathError.unsupported(
                detail: l(
                    "Уравнение с несколькими буквами решается только если оно линейно относительно \(x).",
                    "An equation with several letters is supported only when it is linear in \(x)."))
        }
        // polynomial = A·x + B
        var aTerms: [Monomial: Rational] = [:]
        var bTerms: [Monomial: Rational] = [:]
        for (monomial, coefficient) in polynomial.terms {
            if monomial.degree(in: x) == 1 {
                var powers = monomial.powers
                powers[x] = nil
                aTerms[Monomial(powers: powers)] = coefficient
            } else {
                bTerms[monomial] = coefficient
            }
        }
        let a = Polynomial(terms: aTerms)
        let minusB = Polynomial(terms: bTerms).negated
        var steps: [SolutionStep] = [SolutionStep(l("Запишем уравнение", "Write the equation"), formula: original)]
        steps.append(
            SolutionStep(
                l("Соберём слагаемые с \(x) в левой части, остальные — в правой", "Collect the terms with \(x) on the left and the rest on the right"),
                formula: "\(fmt.polynomialFactor(a))·\(x) = \(fmt.polynomial(minusB))"))

        let answer: String
        if let constant = a.constantValue {
            let result = try minusB.divided(by: constant)
            answer = "\(x) = \(fmt.polynomial(result))"
        } else {
            answer = "\(x) = \(fmt.polynomialFactor(minusB))/\(fmt.polynomialFactor(a))"
        }
        steps.append(
            SolutionStep(
                l("Разделим обе части на коэффициент при \(x)", "Divide both sides by the coefficient of \(x)"),
                a.isConstant ? "" : l("При условии \(fmt.polynomial(a)) ≠ 0.", "Provided that \(fmt.polynomial(a)) ≠ 0."),
                formula: answer))

        return EquationOutcome(
            kindTitle: l("Линейное уравнение с параметрами", "Literal linear equation"),
            set: .roots([]),
            answer: answer,
            explanation: l(
                "Остальные буквы считаем известными числами (параметрами) и выражаем \(x) через них.",
                "We treat the other letters as known numbers (parameters) and express \(x) in terms of them."),
            steps: steps,
            formulas: [],
            notes: a.isConstant ? [] : [l("Ответ верен при \(fmt.polynomial(a)) ≠ 0.", "The answer is valid when \(fmt.polynomial(a)) ≠ 0.")],
            isApproximate: false)
    }

    // MARK: - Numeric fallback

    private func solveNumerically(lhs: Expr, rhs: Expr, variable x: String, original: String) throws -> EquationOutcome {
        let difference = Expr.sub(lhs, rhs)
        guard difference.variables == [x] else {
            throw MathError.unsupported(
                detail: l(
                    "Нелинейное уравнение с несколькими переменными локальный движок не решает.",
                    "The local engine cannot solve a nonlinear equation in several variables."))
        }
        let f: (Double) -> Double = { [evaluator] value in evaluator.numeric(difference, variable: x, at: value) }

        // Периодична ли функция с периодом 2π? Тогда ищем корни на одном периоде.
        let twoPi = 2 * Double.pi
        let periodic =
            difference.containsTrigonometry
            && [0.37, 1.91, -2.3, 4.4].allSatisfy { sample in
                let a = f(sample)
                let b = f(sample + twoPi)
                return a.isNaN && b.isNaN || abs(a - b) <= 1e-9 * max(1, abs(a))
            }

        let numericRoots = periodic ? NumericRootFinder.roots(of: f, from: 0, to: twoPi, steps: 12_566, includeEnd: false) : NumericRootFinder.roots(of: f)
        var roots: [RootValue] = []
        for value in numericRoots {
            roots.append(refine(value, lhs: lhs, rhs: rhs, variable: x, allowPi: difference.containsTrigonometry))
        }
        roots = PolynomialRootFinder.sortedDistinct(roots)
        let approximate = roots.contains { !$0.isExact }

        var steps: [SolutionStep] = [SolutionStep(l("Запишем уравнение", "Write the equation"), formula: original)]
        steps.append(
            SolutionStep(
                l("Уравнение не сводится к многочлену", "The equation does not reduce to a polynomial"),
                l(
                    "Перенесём всё в левую часть: f(\(x)) = \(fmt.expr(difference)). Корни уравнения — это точки, где f(\(x)) = 0. Ищем их численно: находим промежутки, на которых f меняет знак, и уточняем корень делением отрезка пополам.",
                    "Move everything to the left: f(\(x)) = \(fmt.expr(difference)). The roots are the points where f(\(x)) = 0. We find them numerically: locate intervals where f changes sign and refine each root by bisection."
                )))

        var notes: [String] = []
        if periodic {
            notes.append(
                l(
                    "Функция периодическая: показаны корни на промежутке [0; 2π). Остальные получаются прибавлением 2πn, где n — целое число.",
                    "The function is periodic: roots on [0; 2π) are shown. All others are obtained by adding 2πn, where n is an integer."))
        } else {
            notes.append(
                l(
                    "Корни искались численно на отрезке [−1000; 1000]. Корни вне этого отрезка, если они есть, не показаны.",
                    "Roots were searched numerically on [−1000; 1000]. Roots outside this interval, if any, are not shown."))
        }

        let suffix = periodic ? " + 2πn, n ∈ ℤ" : ""
        var outcome = finish(
            kind: difference.containsTrigonometry
                ? l("Тригонометрическое уравнение", "Trigonometric equation")
                : l("Уравнение (численное решение)", "Equation (numeric solution)"),
            roots: roots, lhs: lhs, rhs: rhs, variable: x, steps: steps, formulas: [], approximate: approximate,
            explanation: l(
                "Для такого уравнения нет общей школьной формулы, поэтому корни найдены численным методом и проверены подстановкой.",
                "There is no general school formula for this equation, so the roots are found numerically and verified by substitution."),
            rootSuffix: suffix)
        outcome.notes += notes
        if roots.isEmpty {
            outcome.answer =
                periodic
                ? l("Действительных корней нет", "No real roots")
                : l("На отрезке [−1000; 1000] корней не найдено", "No roots found on [−1000; 1000]")
            outcome.isApproximate = !periodic
        }
        return outcome
    }

    /// Пытаемся превратить численный корень в точный и строго проверить его подстановкой.
    private func refine(_ value: Double, lhs: Expr, rhs: Expr, variable x: String, allowPi: Bool) -> RootValue {
        if let candidate = Algebra.rationalApproximation(value, maxDenominator: 1_000),
            let left = try? evaluator.evaluate(lhs, [x: .exact(candidate)]),
            let right = try? evaluator.evaluate(rhs, [x: .exact(candidate)]),
            left.isExact, left == right
        {
            return .rational(candidate)
        }
        if allowPi, let fraction = Algebra.rationalApproximation(value / Double.pi, maxDenominator: 12),
            let left = try? evaluator.evaluate(lhs, [x: .piMultiple(fraction)]),
            let right = try? evaluator.evaluate(rhs, [x: .piMultiple(fraction)]),
            left.isExact, left == right
        {
            return .piMultiple(fraction)
        }
        return .approx(value)
    }

    // MARK: - Finishing

    private func outcome(kind: String, set: EquationOutcome.SolutionSet, answer: String, explanation: String, steps: [SolutionStep])
        -> EquationOutcome
    {
        EquationOutcome(
            kindTitle: kind, set: set, answer: answer, explanation: explanation, steps: steps, formulas: [], notes: [],
            isApproximate: false)
    }

    /// Проверка подстановкой, формирование ответа.
    private func finish(
        kind: String, roots unsorted: [RootValue], lhs: Expr, rhs: Expr, variable x: String, steps initialSteps: [SolutionStep],
        formulas: [String], approximate: Bool, explanation: String, rootSuffix: String = ""
    ) -> EquationOutcome {
        var steps = initialSteps
        var notes: [String] = []
        var roots: [RootValue] = []

        // Каждый корень проверяем подстановкой в исходное уравнение.
        var checks: [String] = []
        for root in PolynomialRootFinder.sortedDistinct(unsorted) {
            let value: MathValue
            switch root {
            case .rational(let r): value = .exact(r)
            case .piMultiple(let r): value = .piMultiple(r)
            default: value = .approx(root.double)
            }
            guard let left = try? evaluator.evaluate(lhs, [x: value]), let right = try? evaluator.evaluate(rhs, [x: value]) else {
                notes.append(
                    l(
                        "Значение \(x) = \(fmt.root(root)) не входит в область определения исходного уравнения и отброшено.",
                        "The value \(x) = \(fmt.root(root)) is outside the domain of the original equation and was discarded."))
                continue
            }
            let scale = max(1, abs(left.double), abs(right.double))
            guard abs(left.double - right.double) <= 1e-6 * scale else {
                notes.append(
                    l(
                        "Значение \(x) ≈ \(fmt.approx(root.double)) не прошло проверку подстановкой и отброшено.",
                        "The value \(x) ≈ \(fmt.approx(root.double)) failed the substitution check and was discarded."))
                continue
            }
            roots.append(root)
            if left.isExact, right.isExact, left == right {
                checks.append("\(x) = \(fmt.root(root)): \(fmt.value(left)) = \(fmt.value(right)) ✓")
            } else {
                // Погрешность округления (порядка 10⁻¹⁶) не показываем как «значение».
                func clean(_ value: Double) -> Double { abs(value) < 1e-9 ? 0 : value }
                let leftText = fmt.approx(clean(left.double), significant: 5)
                let rightText = fmt.approx(clean(right.double), significant: 5)
                let prefix = root.isExact ? "\(x) = \(fmt.root(root))" : "\(x) ≈ \(fmt.approx(root.double))"
                checks.append("\(prefix): \(leftText) ≈ \(rightText) ✓")
            }
        }
        if !checks.isEmpty, checks.count <= 6 {
            steps.append(
                SolutionStep(
                    l("Проверка подстановкой", "Check by substitution"),
                    l(
                        "Подставим найденные значения в исходное уравнение: левая и правая части должны совпасть.",
                        "Substitute the values into the original equation: both sides must match."),
                    formula: checks.joined(separator: "\n")))
        }

        let isApproximate = approximate || roots.contains { !$0.isExact }
        let answer: String
        if roots.isEmpty {
            answer = l("Действительных корней нет", "No real roots")
        } else if roots.count == 1 {
            answer = "\(x) = \(rootAnswer(roots[0]))\(rootSuffix)"
        } else {
            answer = roots.enumerated().map { index, root in
                "\(x)\(fmt.subscript(index + 1)) = \(rootAnswer(root))\(rootSuffix)"
            }.joined(separator: "; ")
        }

        return EquationOutcome(
            kindTitle: kind,
            set: roots.isEmpty ? .none : .roots(roots),
            answer: answer,
            explanation: explanation,
            steps: steps,
            formulas: formulas,
            notes: notes,
            isApproximate: isApproximate)
    }

    private func rootAnswer(_ root: RootValue) -> String {
        switch root {
        case .rational(let r): return fmt.rationalWithApproximation(r)
        case .surd(let s): return fmt.surd(s) + " ≈ " + fmt.approx(s.double)
        case .piMultiple(let r): return fmt.piMultiple(r)
        case .approx(let d): return "≈ " + fmt.approx(d)
        }
    }
}

/// Численный поиск корней произвольной функции одной переменной.
enum NumericRootFinder {
    /// Корни на отрезке [−1000; 1000]: плотная сетка около нуля и более редкая дальше.
    static func roots(of f: (Double) -> Double) -> [Double] {
        var grid: [Double] = []
        var x = -1000.0
        while x < -50 {
            grid.append(x)
            x += 0.25
        }
        for k in -5000...5000 {
            grid.append(Double(k) / 100)
        }
        x = 50.25
        while x <= 1000 {
            grid.append(x)
            x += 0.25
        }
        return roots(of: f, grid: grid)
    }

    static func roots(of f: (Double) -> Double, from start: Double, to end: Double, steps: Int, includeEnd: Bool) -> [Double] {
        let grid = (0...steps).map { start + (end - start) * Double($0) / Double(steps) }
        let found = roots(of: f, grid: grid)
        return includeEnd ? found : found.filter { $0 < end - 1e-9 }
    }

    static func roots(of f: (Double) -> Double, grid: [Double]) -> [Double] {
        let values = grid.map(f)
        var roots: [Double] = []

        func add(_ root: Double) {
            if !roots.contains(where: { abs($0 - root) <= 1e-7 * max(1, abs(root)) }) {
                roots.append(root)
            }
        }

        for index in 0..<grid.count {
            let fa = values[index]
            guard fa.isFinite else { continue }
            if fa == 0 {
                add(grid[index])
                continue
            }
            guard index + 1 < grid.count else { continue }
            let fb = values[index + 1]
            guard fb.isFinite else { continue }

            if fb != 0, (fa < 0) != (fb < 0) {
                // Смена знака: деление отрезка пополам.
                var a = grid[index]
                var b = grid[index + 1]
                var left = fa
                for _ in 0..<100 {
                    let mid = (a + b) / 2
                    let fm = f(mid)
                    guard fm.isFinite else { break }
                    if fm == 0 {
                        a = mid
                        b = mid
                        break
                    }
                    if (fm < 0) == (left < 0) {
                        a = mid
                        left = fm
                    } else {
                        b = mid
                    }
                }
                let root = (a + b) / 2
                let residual = abs(f(root))
                // Разрыв (полюс) тоже даёт смену знака — отличаем его по величине функции.
                if residual.isFinite, residual <= 1e-6 * max(1, min(abs(fa), abs(fb))) {
                    add(root)
                }
            } else if index >= 1, values[index - 1].isFinite {
                // Касание оси без смены знака: локальный минимум |f|.
                let previous = abs(values[index - 1])
                let current = abs(fa)
                let next = abs(fb)
                if current < previous, current <= next, current < 1e-3 {
                    var a = grid[index - 1]
                    var b = grid[index + 1]
                    let ratio = (5.0.squareRoot() - 1) / 2
                    for _ in 0..<120 {
                        let c = b - ratio * (b - a)
                        let d = a + ratio * (b - a)
                        if abs(f(c)) < abs(f(d)) {
                            b = d
                        } else {
                            a = c
                        }
                    }
                    let root = (a + b) / 2
                    if abs(f(root)) <= 1e-9 {
                        add(root)
                    }
                }
            }
        }
        return roots.sorted()
    }
}
