import Foundation

/// Промежуток числовой прямой. `nil` на границе означает бесконечность.
struct SolutionInterval: Sendable, Hashable {
    var lower: RootValue?
    var upper: RootValue?
    var lowerClosed: Bool
    var upperClosed: Bool

    /// Отдельная точка `{a}`.
    var isPoint: Bool {
        guard let lower, let upper else { return false }
        return lowerClosed && upperClosed && abs(lower.double - upper.double) <= 1e-12 * max(1, abs(lower.double))
    }
}

struct InequalityOutcome: Sendable {
    var kindTitle: String
    var intervals: [SolutionInterval]
    var answer: String
    var explanation: String
    var steps: [SolutionStep]
    var notes: [String]
    var isApproximate: Bool
}

/// Решение неравенств с одной переменной методом интервалов.
struct InequalitySolver: Sendable {
    let l: L10n
    let fmt: MathFormatter

    init(lang: AppLanguage, formatter: MathFormatter) {
        l = L10n(lang)
        fmt = formatter
    }

    private struct CriticalPoint {
        var value: RootValue
        var isPole: Bool
    }

    func solve(lhs: Expr, rhs: Expr, relation: Relation, variable x: String) throws -> InequalityOutcome {
        let original = "\(fmt.expr(lhs)) \(relation.rawValue) \(fmt.expr(rhs))"
        guard let function = try Algebra.rationalFunction(.sub(lhs, rhs)) else {
            if let outcome = try solveWithAbsoluteValues(lhs: lhs, rhs: rhs, relation: relation, variable: x, original: original) {
                return outcome
            }
            throw MathError.unsupported(
                detail: l(
                    "Локальный движок решает только рациональные неравенства (многочлены, дроби из многочленов и модули). Это неравенство к ним не сводится.",
                    "The local engine solves only rational inequalities (polynomials, fractions of polynomials and absolute values). This one does not reduce to that form."
                ))
        }
        let variables = Set(function.numerator.variables).union(function.denominator.variables)
        guard variables.subtracting([x]).isEmpty,
            let numerator = function.numerator.coefficients(in: x) ?? Optional([function.numerator.constantTerm]),
            let denominator = function.denominator.coefficients(in: x) ?? Optional([function.denominator.constantTerm])
        else {
            throw MathError.unsupported(
                detail: l(
                    "Неравенства с несколькими переменными не поддерживаются.",
                    "Inequalities in several variables are not supported."))
        }
        guard !UnivariatePolynomial.isZero(denominator) else { throw MathError.divisionByZero }

        var steps: [SolutionStep] = [SolutionStep(l("Запишем неравенство", "Write the inequality"), formula: original)]
        let numeratorDegree = UnivariatePolynomial.degree(numerator)
        let denominatorDegree = UnivariatePolynomial.degree(denominator)

        // Линейное неравенство — отдельное, более простое объяснение.
        if denominatorDegree == 0, numeratorDegree == 1, let polynomial = try function.asPolynomial(),
            let coefficients = polynomial.coefficients(in: x)
        {
            return try solveLinear(coefficients, relation: relation, variable: x, steps: steps)
        }

        let numeratorText = fmt.polynomial(Polynomial(coefficients: numerator, variable: x))
        let denominatorText = fmt.polynomial(Polynomial(coefficients: denominator, variable: x))
        let standard =
            denominatorDegree == 0
            ? "\(fmt.polynomial((try function.asPolynomial()) ?? function.numerator)) \(relation.rawValue) 0"
            : "(\(numeratorText))/(\(denominatorText)) \(relation.rawValue) 0"
        if standard != original {
            steps.append(
                SolutionStep(
                    l("Перенесём всё в левую часть", "Move everything to the left side"),
                    l(
                        "Справа должен остаться ноль — тогда достаточно определить знак левой части.",
                        "Zero must remain on the right — then we only need the sign of the left side."),
                    formula: standard))
        }

        let zeros = try PolynomialRootFinder.realRoots(numerator)
        let poles = denominatorDegree > 0 ? try PolynomialRootFinder.realRoots(denominator) : []

        func sign(at point: Double) -> Int {
            let n = UnivariatePolynomial.evaluate(numerator, at: point)
            let d = UnivariatePolynomial.evaluate(denominator, at: point)
            let value = n / d
            if !value.isFinite || value == 0 { return 0 }
            return value > 0 ? 1 : -1
        }

        // Критические точки: нули числителя и знаменателя.
        var points: [CriticalPoint] = poles.map { CriticalPoint(value: $0, isPole: true) }
        for zero in zeros {
            let coincides = points.contains { abs($0.value.double - zero.double) <= 1e-9 * max(1, abs(zero.double)) }
            if !coincides { points.append(CriticalPoint(value: zero, isPole: false)) }
        }
        points.sort { $0.value.double < $1.value.double }
        let approximate = points.contains { !$0.value.isExact }

        if UnivariatePolynomial.isZero(numerator) {
            // 0 ? 0
            let holds = relation.holds(sign: 0)
            steps.append(
                SolutionStep(
                    l("После упрощения левая часть равна нулю", "After simplification the left side is zero"),
                    formula: "0 \(relation.rawValue) 0"))
            let intervals = holds ? complement(of: points.filter { $0.isPole }) : []
            return finish(
                kind: l("Неравенство", "Inequality"), intervals: intervals, variable: x, steps: steps,
                approximate: approximate, relation: relation,
                explanation: holds
                    ? l("Неравенство верно при всех допустимых значениях.", "The inequality holds for all admissible values.")
                    : l("Неравенство неверно при любых значениях.", "The inequality is false for all values."))
        }

        if !zeros.isEmpty || !poles.isEmpty {
            var detail = ""
            if !zeros.isEmpty {
                detail += l("Нули числителя: ", "Zeros of the numerator: ") + zeros.map { "\(x) = \(fmt.root($0))" }.joined(separator: "; ") + ". "
            } else {
                detail += l("Числитель в ноль не обращается. ", "The numerator is never zero. ")
            }
            if !poles.isEmpty {
                detail +=
                    l("Знаменатель равен нулю при ", "The denominator is zero at ")
                    + poles.map { "\(x) = \(fmt.root($0))" }.joined(separator: "; ")
                    + l(" — эти точки исключаются.", " — these points are excluded.")
            }
            steps.append(
                SolutionStep(
                    denominatorDegree > 0
                        ? l("Найдём нули числителя и знаменателя", "Find the zeros of the numerator and the denominator")
                        : l("Найдём нули левой части", "Find the zeros of the left side"),
                    detail))
        } else {
            steps.append(
                SolutionStep(
                    l("Нулей у левой части нет", "The left side has no zeros"),
                    l(
                        "Значит, её знак один и тот же на всей числовой прямой.",
                        "So its sign is the same on the whole number line.")))
        }

        // Знаки на промежутках.
        var segments: [(interval: SolutionInterval, sign: Int)] = []
        for index in 0...points.count {
            let lower = index == 0 ? nil : points[index - 1].value
            let upper = index == points.count ? nil : points[index].value
            let sample: Double
            switch (lower, upper) {
            case (nil, nil): sample = 0
            case (nil, let u?): sample = u.double - 1
            case (let lo?, nil): sample = lo.double + 1
            case (let lo?, let u?): sample = (lo.double + u.double) / 2
            }
            segments.append(
                (SolutionInterval(lower: lower, upper: upper, lowerClosed: false, upperClosed: false), sign(at: sample)))
        }
        let signTable = segments.map { segment in
            "\(intervalText(segment.interval)): \(segment.sign > 0 ? "+" : segment.sign < 0 ? "−" : "0")"
        }.joined(separator: "\n")
        steps.append(
            SolutionStep(
                l("Определим знак на каждом промежутке", "Determine the sign on each interval"),
                l(
                    "Точки делят числовую прямую на промежутки. В каждом берём пробную точку и смотрим знак выражения.",
                    "The points split the number line into intervals. In each one we take a test point and check the sign."),
                formula: signTable))

        // Выбираем подходящие промежутки и решаем судьбу граничных точек.
        let closedAllowed = !relation.isStrict
        func isIncludedPoint(_ index: Int) -> Bool {
            closedAllowed && !points[index].isPole
        }

        var intervals: [SolutionInterval] = []
        for (index, segment) in segments.enumerated() {
            let included = relation.holds(sign: segment.sign)
            if included {
                var interval = segment.interval
                if index > 0 { interval.lowerClosed = isIncludedPoint(index - 1) }
                if index < points.count { interval.upperClosed = isIncludedPoint(index) }
                if var last = intervals.last, last.upperClosed, interval.lowerClosed,
                    let a = last.upper, let b = interval.lower, abs(a.double - b.double) <= 1e-12 * max(1, abs(a.double))
                {
                    // Соседние промежутки с общей включённой точкой склеиваются.
                    last.upper = interval.upper
                    last.upperClosed = interval.upperClosed
                    intervals[intervals.count - 1] = last
                } else {
                    intervals.append(interval)
                }
            } else if index < points.count, isIncludedPoint(index) {
                // Изолированная точка: ноль функции между двумя неподходящими промежутками.
                let nextIncluded = relation.holds(sign: segments[index + 1].sign)
                if !nextIncluded {
                    let point = points[index].value
                    intervals.append(SolutionInterval(lower: point, upper: point, lowerClosed: true, upperClosed: true))
                }
            }
        }

        let wanted: String
        switch relation {
        case .gt: wanted = l("нужны промежутки со знаком «+»", "we need the intervals marked “+”")
        case .ge: wanted = l("нужны промежутки со знаком «+» и сами нули", "we need the “+” intervals together with the zeros")
        case .lt: wanted = l("нужны промежутки со знаком «−»", "we need the intervals marked “−”")
        case .le: wanted = l("нужны промежутки со знаком «−» и сами нули", "we need the “−” intervals together with the zeros")
        case .ne: wanted = l("подходят все точки, кроме нулей", "all points except the zeros qualify")
        case .eq: wanted = ""
        }
        steps.append(
            SolutionStep(
                l("Выберем подходящие промежутки", "Choose the suitable intervals"),
                l("Знак неравенства «\(relation.rawValue)», поэтому \(wanted).", "The sign is “\(relation.rawValue)”, so \(wanted)."),
                formula: setText(intervals, variable: x)))

        let kind: String
        if denominatorDegree > 0 {
            kind = l("Дробно-рациональное неравенство", "Rational inequality")
        } else if numeratorDegree == 2 {
            kind = l("Квадратное неравенство", "Quadratic inequality")
        } else {
            kind = l("Неравенство \(numeratorDegree)-й степени", "Degree-\(numeratorDegree) inequality")
        }
        return finish(
            kind: kind, intervals: intervals, variable: x, steps: steps, approximate: approximate, relation: relation,
            explanation: l(
                "Метод интервалов: находим точки, в которых выражение равно нулю или не определено, они делят прямую на промежутки с постоянным знаком. Остаётся выбрать промежутки с нужным знаком.",
                "The interval method: find the points where the expression is zero or undefined; they split the line into intervals of constant sign. Then pick the intervals with the required sign."
            ))
    }

    // MARK: - Absolute values

    /// Неравенство с модулями: раскрываем модули на промежутках знакопостоянства.
    private func solveWithAbsoluteValues(lhs: Expr, rhs: Expr, relation: Relation, variable x: String, original: String) throws
        -> InequalityOutcome?
    {
        let left = PiecewiseAnalysis.rewritingSquareRootOfSquare(lhs)
        let right = PiecewiseAnalysis.rewritingSquareRootOfSquare(rhs)
        guard PiecewiseAnalysis.containsAbs(left) || PiecewiseAnalysis.containsAbs(right),
            let result = try PiecewiseAnalysis.solve(.sub(left, right), relation: relation, variable: x)
        else { return nil }

        var steps: [SolutionStep] = [SolutionStep(l("Запишем неравенство", "Write the inequality"), formula: original)]
        steps += PiecewiseAnalysis.openingSteps(
            result, lhs: left, rhs: right, relation: relation, variable: x, l: l, fmt: fmt)
        steps.append(
            SolutionStep(
                l("Объединим подходящие промежутки", "Combine the suitable intervals"),
                l(
                    "Берём промежутки и точки, где неравенство выполняется, с учётом области определения.",
                    "Take the intervals and points where the inequality holds, within the domain."),
                formula: setText(result.intervals, variable: x)))
        return finish(
            kind: l("Неравенство с модулем", "Inequality with absolute value"), intervals: result.intervals, variable: x,
            steps: steps, approximate: result.approximate, relation: relation,
            explanation: l(
                "Модуль раскрывается по определению: |a| = a при a ≥ 0 и |a| = −a при a < 0. Точки, где выражения под модулем равны нулю, делят прямую на промежутки, на каждом из которых модули раскрываются однозначно.",
                "An absolute value is opened by definition: |a| = a for a ≥ 0 and |a| = −a for a < 0. The points where the expressions inside are zero split the line into intervals, on each of which the absolute values open in one way."
            ))
    }

    // MARK: - Linear

    private func solveLinear(_ coefficients: [Rational], relation: Relation, variable x: String, steps initial: [SolutionStep]) throws
        -> InequalityOutcome
    {
        var steps = initial
        let a = coefficients[1]
        let b = coefficients[0]
        let standard = Polynomial(coefficients: coefficients, variable: x)
        steps.append(
            SolutionStep(
                l("Перенесём всё в левую часть и приведём подобные", "Move everything to the left and combine like terms"),
                formula: "\(fmt.polynomial(standard)) \(relation.rawValue) 0"))
        steps.append(
            SolutionStep(
                l("Оставим слагаемое с \(x) слева, число перенесём вправо", "Keep the term with \(x) on the left and move the number to the right"),
                formula: "\(fmt.polynomial(Polynomial(coefficients: [.zero, a], variable: x))) \(relation.rawValue) \(fmt.rational(b.negated))"))

        let boundary = try b.negated / a
        let finalRelation = a.isNegative ? relation.flipped : relation
        steps.append(
            SolutionStep(
                l("Разделим обе части на \(fmt.rational(a))", "Divide both sides by \(fmt.rational(a))"),
                a.isNegative
                    ? l(
                        "Делим на отрицательное число — знак неравенства меняется на противоположный.",
                        "We divide by a negative number, so the inequality sign is reversed.")
                    : l("Делим на положительное число — знак неравенства сохраняется.", "We divide by a positive number, so the sign stays the same."),
                formula: "\(x) \(finalRelation.rawValue) \(fmt.rationalWithApproximation(boundary))"))

        let point = RootValue.rational(boundary)
        var intervals: [SolutionInterval]
        switch finalRelation {
        case .gt: intervals = [SolutionInterval(lower: point, upper: nil, lowerClosed: false, upperClosed: false)]
        case .ge: intervals = [SolutionInterval(lower: point, upper: nil, lowerClosed: true, upperClosed: false)]
        case .lt: intervals = [SolutionInterval(lower: nil, upper: point, lowerClosed: false, upperClosed: false)]
        case .le: intervals = [SolutionInterval(lower: nil, upper: point, lowerClosed: false, upperClosed: true)]
        case .ne:
            intervals = [
                SolutionInterval(lower: nil, upper: point, lowerClosed: false, upperClosed: false),
                SolutionInterval(lower: point, upper: nil, lowerClosed: false, upperClosed: false),
            ]
        case .eq: intervals = [SolutionInterval(lower: point, upper: point, lowerClosed: true, upperClosed: true)]
        }
        return finish(
            kind: l("Линейное неравенство", "Linear inequality"), intervals: intervals, variable: x, steps: steps,
            approximate: false, relation: relation,
            explanation: l(
                "Линейное неравенство решается как уравнение, но при умножении или делении на отрицательное число знак неравенства переворачивается.",
                "A linear inequality is solved like an equation, but multiplying or dividing by a negative number reverses the sign."
            ))
    }

    // MARK: - Formatting

    private func complement(of poles: [CriticalPoint]) -> [SolutionInterval] {
        var result: [SolutionInterval] = []
        var lower: RootValue? = nil
        for pole in poles {
            result.append(SolutionInterval(lower: lower, upper: pole.value, lowerClosed: false, upperClosed: false))
            lower = pole.value
        }
        result.append(SolutionInterval(lower: lower, upper: nil, lowerClosed: false, upperClosed: false))
        return result
    }

    func intervalText(_ interval: SolutionInterval) -> String {
        if interval.isPoint, let point = interval.lower {
            return "{\(fmt.root(point))}"
        }
        let left = interval.lower.map { fmt.root($0) } ?? "−∞"
        let right = interval.upper.map { fmt.root($0) } ?? "+∞"
        return "\(interval.lowerClosed ? "[" : "(")\(left); \(right)\(interval.upperClosed ? "]" : ")")"
    }

    func setText(_ intervals: [SolutionInterval], variable x: String) -> String {
        guard !intervals.isEmpty else { return "\(x) ∈ ∅" }
        return "\(x) ∈ " + intervals.map { intervalText($0) }.joined(separator: " ∪ ")
    }

    /// Короткая запись через знаки сравнения, если множество — один луч или отрезок.
    func comparisonText(_ intervals: [SolutionInterval], variable x: String) -> String? {
        guard intervals.count == 1, let interval = intervals.first, !interval.isPoint else { return nil }
        switch (interval.lower, interval.upper) {
        case (let lower?, nil):
            return "\(x) \(interval.lowerClosed ? "≥" : ">") \(fmt.root(lower))"
        case (nil, let upper?):
            return "\(x) \(interval.upperClosed ? "≤" : "<") \(fmt.root(upper))"
        case (let lower?, let upper?):
            return "\(fmt.root(lower)) \(interval.lowerClosed ? "≤" : "<") \(x) \(interval.upperClosed ? "≤" : "<") \(fmt.root(upper))"
        case (nil, nil):
            return nil
        }
    }

    /// Ответ для множества решений: «x — любое число», «x = 3», «x > 4, то есть …», объединение промежутков.
    func answerText(_ intervals: [SolutionInterval], variable x: String, relation: Relation? = nil) -> String {
        if intervals.isEmpty {
            return l("Нет решений", "No solutions")
        } else if intervals.count == 1, intervals[0].lower == nil, intervals[0].upper == nil {
            return l("\(x) — любое число", "\(x) is any number")
        } else if relation == .ne, let excluded = PiecewiseAnalysis.excludedPoints(intervals), !excluded.isEmpty {
            return excluded.map { "\(x) ≠ \(fmt.root($0))" }.joined(separator: "; ")
        } else if intervals.allSatisfy({ $0.isPoint }) {
            let points = intervals.compactMap { $0.lower }
            if points.count == 1 { return "\(x) = \(fmt.root(points[0]))" }
            return points.enumerated().map { "\(x)\(fmt.subscript($0.offset + 1)) = \(fmt.root($0.element))" }.joined(separator: "; ")
        } else if let comparison = comparisonText(intervals, variable: x) {
            return comparison + l(", то есть ", ", i.e. ") + setText(intervals, variable: x)
        }
        return setText(intervals, variable: x)
    }

    private func finish(
        kind: String, intervals: [SolutionInterval], variable x: String, steps: [SolutionStep], approximate: Bool,
        relation: Relation? = nil, explanation: String
    ) -> InequalityOutcome {
        let answer = answerText(intervals, variable: x, relation: relation)
        var notes: [String] = []
        if approximate {
            notes.append(
                l(
                    "Часть граничных точек найдена приближённо (численно).",
                    "Some boundary points were found approximately (numerically)."))
        }
        return InequalityOutcome(
            kindTitle: kind, intervals: intervals, answer: answer, explanation: explanation, steps: steps, notes: notes,
            isApproximate: approximate)
    }
}

// MARK: - Точные значения вида a + b·√n

extension Surd {
    /// Значение без потери точности: при `p` и `q√n` разных знаков считаем через
    /// сопряжённое `(p² − q²n)/(p − q√n)`, чтобы не вычитать близкие числа
    /// (`x² − 1000000x + 1 = 0` даёт корень ≈ 10⁻⁶).
    var preciseDouble: Double {
        let p = rationalPart
        let q = coefficient
        let plain = double
        guard !p.isZero, !q.isZero, p.signum != q.signum,
            let numerator = try? (try p * p) - (try (try q * q) * Rational(radicand))
        else { return plain }
        let denominator = p.doubleValue - q.doubleValue * Double(radicand).squareRoot()
        guard denominator != 0 else { return plain }
        let value = numerator.doubleValue / denominator
        return value.isFinite ? value : plain
    }
}

extension RootValue {
    /// Как `double`, но без потери точности для корней с радикалом.
    var preciseDouble: Double {
        if case .surd(let s) = self { return s.preciseDouble }
        return double
    }
}

/// Число `a + b·√n` с рациональными `a`, `b` и фиксированным `n` (свободным от квадратов).
/// Позволяет точно проверить корень квадратного уравнения подстановкой.
struct QuadraticSurdNumber: Sendable, Equatable {
    var a: Rational
    var b: Rational
    let n: Int

    init(_ a: Rational, _ b: Rational = .zero, n: Int) {
        self.a = a
        self.b = b
        self.n = n
    }

    init?(_ root: RootValue) {
        switch root {
        case .rational(let r): self.init(r, n: 1)
        case .surd(let s): self.init(s.rationalPart, s.coefficient, n: s.radicand)
        default: return nil
        }
    }

    var isZero: Bool { a.isZero && b.isZero }

    func plus(_ other: QuadraticSurdNumber) throws -> QuadraticSurdNumber {
        QuadraticSurdNumber(try a + other.a, try b + other.b, n: n)
    }

    func minus(_ other: QuadraticSurdNumber) throws -> QuadraticSurdNumber {
        QuadraticSurdNumber(try a - other.a, try b - other.b, n: n)
    }

    var negated: QuadraticSurdNumber { QuadraticSurdNumber(a.negated, b.negated, n: n) }

    func times(_ other: QuadraticSurdNumber) throws -> QuadraticSurdNumber {
        let first = try (try a * other.a) + (try (try b * other.b) * Rational(n))
        let second = try (try a * other.b) + (try b * other.a)
        return QuadraticSurdNumber(first, second, n: n)
    }

    func reciprocal() throws -> QuadraticSurdNumber {
        guard !isZero else { throw MathError.divisionByZero }
        if b.isZero { return QuadraticSurdNumber(try a.reciprocal(), n: n) }
        // 1/(a + b√n) = (a − b√n)/(a² − b²n); знаменатель ≠ 0, так как √n иррационален.
        let norm = try (try a * a) - (try (try b * b) * Rational(n))
        return QuadraticSurdNumber(try a / norm, try b.negated / norm, n: n)
    }

    /// Знак числа, определённый точно.
    func sign() throws -> Int {
        let sa = a.signum
        let sb = b.signum
        if sb == 0 { return sa }
        if sa == 0 { return sb }
        if sa == sb { return sa }
        // Разные знаки: сравниваем a² и b²n.
        let left = try a * a
        let right = try (try b * b) * Rational(n)
        if left == right { return 0 }
        return left > right ? sa : sb
    }

    func power(_ exponent: Int) throws -> QuadraticSurdNumber {
        if exponent < 0 { return try power(-exponent).reciprocal() }
        var result = QuadraticSurdNumber(.one, n: n)
        for _ in 0..<exponent { result = try result.times(self) }
        return result
    }
}

/// Точное вычисление выражения из арифметики, целых степеней и модуля в точке `a + b·√n`.
enum ExactSurdEvaluator {
    enum Outcome {
        case value(QuadraticSurdNumber)
        /// Выражение в этой точке не определено (деление на ноль).
        case undefined
        /// Выражение содержит то, что так вычислить нельзя, или числа слишком велики.
        case unsupported
    }

    static func evaluate(_ expr: Expr, variable: String, at point: QuadraticSurdNumber) -> Outcome {
        do {
            guard let value = try eval(expr, variable, point) else { return .unsupported }
            return .value(value)
        } catch MathError.divisionByZero {
            return .undefined
        } catch {
            return .unsupported
        }
    }

    private static func eval(_ expr: Expr, _ x: String, _ point: QuadraticSurdNumber) throws -> QuadraticSurdNumber? {
        if expr.isConstant {
            if case .num(let r) = expr { return QuadraticSurdNumber(r, n: point.n) }
            guard let value = try? MathEvaluator().evaluate(expr), let rational = value.rational else { return nil }
            return QuadraticSurdNumber(rational, n: point.n)
        }
        switch expr {
        case .num(let r):
            return QuadraticSurdNumber(r, n: point.n)
        case .sym(let name):
            return name == x ? point : nil
        case .real, .const:
            return nil
        case .neg(let inner):
            return try eval(inner, x, point)?.negated
        case .bin(let op, let lhs, let rhs):
            if op == .pow {
                guard rhs.isConstant, let exponent = try? MathEvaluator().evaluate(rhs).rational, exponent.isInteger,
                    abs(exponent.num) <= 64, let base = try eval(lhs, x, point)
                else { return nil }
                if base.isZero, exponent.num <= 0 { throw MathError.divisionByZero }
                return try base.power(exponent.num)
            }
            guard let left = try eval(lhs, x, point), let right = try eval(rhs, x, point) else { return nil }
            switch op {
            case .add: return try left.plus(right)
            case .sub: return try left.minus(right)
            case .mul: return try left.times(right)
            case .div: return try left.times(try right.reciprocal())
            case .pow: return nil
            }
        case .fn(let function, let args):
            guard function == .abs, args.count == 1, let inner = try eval(args[0], x, point) else { return nil }
            return try inner.sign() < 0 ? inner.negated : inner
        }
    }
}

// MARK: - Выражения с модулем

/// Точный разбор выражений, составленных из рациональных выражений одной переменной и модулей.
///
/// Нули подмодульных выражений и нули/полюса рациональных функций, получающихся при раскрытии
/// модулей, делят прямую на промежутки. На каждом из них все модули раскрываются с постоянным
/// знаком, поэтому выражение — одна рациональная функция без нулей внутри промежутка: её знак
/// постоянен или она тождественно равна нулю. Знак определяется точным вычислением в одной точке.
enum PiecewiseAnalysis {
    struct Segment {
        var interval: SolutionInterval
        var sample: Rational?
        var sign: Int?
    }

    struct Result {
        var intervals: [SolutionInterval]
        var approximate: Bool
        /// Нули выражений под модулем.
        var argumentZeros: [RootValue]
        var segments: [Segment]
    }

    /// `√(u²)` → `|u|`.
    static func rewritingSquareRootOfSquare(_ expr: Expr) -> Expr {
        switch expr {
        case .num, .real, .sym, .const: return expr
        case .neg(let inner): return .neg(rewritingSquareRootOfSquare(inner))
        case .bin(let op, let a, let b): return .bin(op, rewritingSquareRootOfSquare(a), rewritingSquareRootOfSquare(b))
        case .fn(let function, let args):
            let rewritten = args.map(rewritingSquareRootOfSquare)
            if function == .sqrt, rewritten.count == 1, case .bin(.pow, let base, .num(let two)) = rewritten[0],
                two == Rational(2), !base.isConstant
            {
                return .fn(.abs, [base])
            }
            return .fn(function, rewritten)
        }
    }

    static func containsAbs(_ expr: Expr) -> Bool {
        switch expr {
        case .num, .real, .sym, .const: return false
        case .neg(let inner): return containsAbs(inner)
        case .bin(_, let a, let b): return containsAbs(a) || containsAbs(b)
        case .fn(let function, let args): return function == .abs || args.contains(where: containsAbs)
        }
    }

    /// Только арифметика, целые степени и модуль; константы — рациональные.
    static func isSupported(_ expr: Expr, variable x: String) -> Bool {
        if expr.isConstant { return ((try? Algebra.rationalFunction(expr)) ?? nil) != nil }
        switch expr {
        case .num: return true
        case .sym(let name): return name == x
        case .real, .const: return false
        case .neg(let inner): return isSupported(inner, variable: x)
        case .bin(let op, let a, let b):
            if op == .pow {
                guard b.isConstant, let exponent = try? MathEvaluator().evaluate(b).rational, exponent.isInteger,
                    abs(exponent.num) <= 64
                else { return false }
                return isSupported(a, variable: x)
            }
            return isSupported(a, variable: x) && isSupported(b, variable: x)
        case .fn(let function, let args):
            return function == .abs && args.count == 1 && isSupported(args[0], variable: x)
        }
    }

    /// Аргумент самого внутреннего модуля.
    static func innermostAbsArgument(_ expr: Expr) -> Expr? {
        switch expr {
        case .num, .real, .sym, .const: return nil
        case .neg(let inner): return innermostAbsArgument(inner)
        case .bin(_, let a, let b): return innermostAbsArgument(a) ?? innermostAbsArgument(b)
        case .fn(let function, let args):
            for arg in args {
                if let inner = innermostAbsArgument(arg) { return inner }
            }
            return function == .abs && args.count == 1 ? args[0] : nil
        }
    }

    static func replacing(_ expr: Expr, _ node: Expr, with replacement: Expr) -> Expr {
        if expr == node { return replacement }
        switch expr {
        case .num, .real, .sym, .const: return expr
        case .neg(let inner): return .neg(replacing(inner, node, with: replacement))
        case .bin(let op, let a, let b): return .bin(op, replacing(a, node, with: replacement), replacing(b, node, with: replacement))
        case .fn(let function, let args): return .fn(function, args.map { replacing($0, node, with: replacement) })
        }
    }

    /// Выражение с раскрытыми модулями — каким оно является около рациональной точки `sample`.
    static func opened(_ expr: Expr, variable x: String, at sample: Rational) -> Expr? {
        var current = expr
        var guardCounter = 0
        while let argument = innermostAbsArgument(current) {
            guardCounter += 1
            guard guardCounter <= 64, let value = try? MathEvaluator().evaluate(argument, [x: .exact(sample)]),
                let rational = value.rational
            else { return nil }
            current = replacing(current, .fn(.abs, [argument]), with: rational.isNegative ? .neg(argument) : argument)
        }
        return current
    }

    /// Нули знаменателей (деление и отрицательные степени) — точки вне области определения.
    static func divisorZeros(_ expr: Expr, variable x: String) -> [RootValue] {
        var result: [RootValue] = []
        func zeros(of e: Expr) {
            guard let function = (try? Algebra.rationalFunction(e)) ?? nil,
                let coefficients = function.numerator.coefficients(in: x),
                UnivariatePolynomial.degree(coefficients) > 0,
                let roots = try? PolynomialRootFinder.realRoots(coefficients)
            else { return }
            result += roots
        }
        func walk(_ e: Expr) {
            switch e {
            case .num, .real, .sym, .const: break
            case .neg(let inner): walk(inner)
            case .bin(let op, let a, let b):
                walk(a)
                walk(b)
                if op == .div { zeros(of: b) }
                if op == .pow, b.isConstant, let exponent = try? MathEvaluator().evaluate(b).rational, exponent.isNegative {
                    zeros(of: a)
                }
            case .fn(_, let args): args.forEach(walk)
            }
        }
        walk(expr)
        return result
    }

    /// Шаги объяснения: нули подмодульных выражений и раскрытие модулей на каждом промежутке.
    static func openingSteps(
        _ result: Result, lhs: Expr, rhs: Expr, relation: Relation, variable x: String, l: L10n, fmt: MathFormatter
    ) -> [SolutionStep] {
        var steps: [SolutionStep] = []
        let zerosText =
            result.argumentZeros.isEmpty
            ? l("Выражения под модулем не меняют знак.", "The expressions inside the absolute values never change sign.")
            : result.argumentZeros.map { "\(x) = \(fmt.root($0))" }.joined(separator: "; ")
        steps.append(
            SolutionStep(
                l("Найдём, где выражения под модулем равны нулю", "Find where the expressions inside the absolute values vanish"),
                zerosText))
        guard result.segments.count <= 8 else { return steps }
        let solver = InequalitySolver(lang: l.lang, formatter: fmt)
        func shown(_ e: Expr) -> String {
            if let polynomial = (try? Algebra.polynomial(e)) ?? nil { return fmt.polynomial(polynomial) }
            return fmt.expr(e)
        }
        var lines: [String] = []
        for segment in result.segments {
            guard let sample = segment.sample, let left = opened(lhs, variable: x, at: sample),
                let right = opened(rhs, variable: x, at: sample)
            else { return steps }
            lines.append("\(solver.intervalText(segment.interval)): \(shown(left)) \(relation.rawValue) \(shown(right))")
        }
        steps.append(
            SolutionStep(
                l("Раскроем модули на каждом промежутке", "Open the absolute values on each interval"),
                l(
                    "|a| = a при a ≥ 0 и |a| = −a при a < 0. Решаем получившееся на каждом промежутке и проверяем граничные точки.",
                    "|a| = a for a ≥ 0 and |a| = −a for a < 0. Solve what we get on each interval and check the boundary points."),
                formula: lines.joined(separator: "\n")))
        return steps
    }

    /// Множество решений `f relation 0`; `nil`, если выражение не из поддерживаемого класса.
    static func solve(_ f: Expr, relation: Relation, variable x: String) throws -> Result? {
        guard isSupported(f, variable: x) else { return nil }

        // Раскрываем модули всеми способами: листья — выражения без модулей.
        var pending: [Expr] = [f]
        var leaves: [Expr] = []
        var arguments: Set<Expr> = []
        while let expr = pending.popLast() {
            if let argument = innermostAbsArgument(expr) {
                arguments.insert(argument)
                let node = Expr.fn(.abs, [argument])
                pending.append(replacing(expr, node, with: argument))
                pending.append(replacing(expr, node, with: .neg(argument)))
                guard pending.count + leaves.count <= 256 else { return nil }
            } else {
                leaves.append(expr)
            }
        }

        var argumentZeros: [RootValue] = []
        var points: [RootValue] = []
        func roots(of polynomial: Polynomial) throws -> [RootValue]? {
            guard Set(polynomial.variables).isSubset(of: [x]) else { return nil }
            let coefficients = polynomial.coefficients(in: x) ?? [polynomial.constantTerm]
            guard UnivariatePolynomial.degree(coefficients) > 0 else { return [] }
            return try PolynomialRootFinder.realRoots(coefficients)
        }
        for argument in arguments {
            guard let function = try Algebra.rationalFunction(argument),
                let zeros = try roots(of: function.numerator), let poles = try roots(of: function.denominator)
            else { return nil }
            argumentZeros += zeros
            points += zeros + poles
        }
        for leaf in leaves {
            guard let function = try Algebra.rationalFunction(leaf),
                let zeros = try roots(of: function.numerator), let poles = try roots(of: function.denominator)
            else { return nil }
            points += zeros + poles + divisorZeros(leaf, variable: x)
        }
        points = PolynomialRootFinder.sortedDistinct(points)
        argumentZeros = PolynomialRootFinder.sortedDistinct(argumentZeros)
        guard points.count <= 200 else { return nil }
        var approximate = points.contains { !$0.isExact }

        let evaluator = MathEvaluator()
        func numericSign(at value: Double) -> Int? {
            let result = evaluator.numeric(f, variable: x, at: value)
            guard result.isFinite else { return nil }
            if abs(result) <= 1e-9 * max(1, abs(value)) { return 0 }
            return result > 0 ? 1 : -1
        }
        /// Знак в рациональной точке; `nil` — выражение не определено.
        func sign(at value: Rational) -> Int? {
            do {
                let result = try evaluator.evaluate(f, [x: .exact(value)])
                if let rational = result.rational { return rational.signum }
                approximate = true
                return numericSign(at: value.doubleValue)
            } catch MathError.overflow {
                approximate = true
                return numericSign(at: value.doubleValue)
            } catch {
                return nil
            }
        }
        func sign(atPoint point: RootValue) -> Int? {
            if case .rational(let r) = point { return sign(at: r) }
            if let surd = QuadraticSurdNumber(point) {
                switch ExactSurdEvaluator.evaluate(f, variable: x, at: surd) {
                case .value(let value):
                    if let s = try? value.sign() { return s }
                case .undefined:
                    return nil
                case .unsupported:
                    break
                }
            }
            approximate = true
            return numericSign(at: point.preciseDouble)
        }

        // Пробные точки внутри промежутков.
        var segments: [Segment] = []
        for index in 0...points.count {
            let lower = index == 0 ? nil : points[index - 1]
            let upper = index == points.count ? nil : points[index]
            let sample = rationalInside(lower, upper)
            let segmentSign: Int?
            if let sample {
                segmentSign = sign(at: sample)
            } else {
                approximate = true
                let lo = lower?.preciseDouble ?? ((upper?.preciseDouble ?? 0) - 2)
                let hi = upper?.preciseDouble ?? (lo + 2)
                segmentSign = numericSign(at: (lo + hi) / 2)
            }
            segments.append(
                Segment(
                    interval: SolutionInterval(lower: lower, upper: upper, lowerClosed: false, upperClosed: false),
                    sample: sample, sign: segmentSign))
        }
        let pointIncluded = points.map { point -> Bool in
            guard let s = sign(atPoint: point) else { return false }
            return relation.holds(sign: s)
        }
        let segmentIncluded = segments.map { segment -> Bool in
            guard let s = segment.sign else { return false }
            return relation.holds(sign: s)
        }
        return Result(
            intervals: assemble(points: points, segmentIncluded: segmentIncluded, pointIncluded: pointIncluded),
            approximate: approximate, argumentZeros: argumentZeros, segments: segments)
    }

    /// Рациональная точка строго внутри промежутка.
    static func rationalInside(_ lower: RootValue?, _ upper: RootValue?) -> Rational? {
        switch (lower, upper) {
        case (nil, nil):
            return .zero
        case (nil, let u?):
            if let r = u.rational, let value = try? r - .one { return value }
            let value = (u.preciseDouble - 1).rounded(.down)
            return abs(value) < 9e15 ? Rational(Int(value)) : nil
        case (let lo?, nil):
            if let r = lo.rational, let value = try? r + .one { return value }
            let value = (lo.preciseDouble + 1).rounded(.up)
            return abs(value) < 9e15 ? Rational(Int(value)) : nil
        case (let lo?, let u?):
            if let a = lo.rational, let b = u.rational, let sum = try? a + b, let mid = try? sum / .two { return mid }
            let a = lo.preciseDouble
            let b = u.preciseDouble
            let mid = (a + b) / 2
            var candidate: Rational?
            if b - a > 2, abs(mid) < 9e15 {
                candidate = Rational(Int(mid.rounded()))
            } else {
                candidate = Algebra.rationalApproximation(
                    mid, maxDenominator: 1_000_000, tolerance: (b - a) / (4 * max(1, abs(mid))))
            }
            guard let candidate, candidate.doubleValue > a, candidate.doubleValue < b else { return nil }
            return candidate
        }
    }

    /// Склеивает подходящие промежутки и точки в объединение промежутков.
    static func assemble(points: [RootValue], segmentIncluded: [Bool], pointIncluded: [Bool]) -> [SolutionInterval] {
        var result: [SolutionInterval] = []
        var current: SolutionInterval?
        // Атомы по порядку: промежуток 0, точка 0, промежуток 1, …, точка k−1, промежуток k.
        for index in 0...points.count {
            // Промежуток index.
            if segmentIncluded[index] {
                if current == nil {
                    current = SolutionInterval(
                        lower: index == 0 ? nil : points[index - 1], upper: nil, lowerClosed: false, upperClosed: false)
                }
            } else if var run = current {
                // Предыдущий атом — включённая точка index − 1.
                run.upper = points[index - 1]
                run.upperClosed = true
                result.append(run)
                current = nil
            }
            guard index < points.count else { break }
            // Точка index.
            if pointIncluded[index] {
                if current == nil {
                    current = SolutionInterval(lower: points[index], upper: nil, lowerClosed: true, upperClosed: false)
                }
            } else if var run = current {
                run.upper = points[index]
                // Предыдущий атом — включённый промежуток index.
                run.upperClosed = false
                result.append(run)
                current = nil
            }
        }
        if let run = current { result.append(run) }
        return result
    }

    /// Точки, которые нужно выкинуть из прямой, чтобы получить это множество; `nil` — если оно не такое.
    static func excludedPoints(_ intervals: [SolutionInterval]) -> [RootValue]? {
        guard let first = intervals.first, let last = intervals.last, first.lower == nil, last.upper == nil else { return nil }
        var points: [RootValue] = []
        for (index, interval) in intervals.enumerated() {
            guard !interval.lowerClosed, !interval.upperClosed else { return nil }
            if index + 1 < intervals.count {
                guard let upper = interval.upper, let next = intervals[index + 1].lower,
                    upper == next || abs(upper.preciseDouble - next.preciseDouble) <= 1e-12 * max(1, abs(upper.preciseDouble))
                else { return nil }
                points.append(upper)
            }
        }
        return points
    }
}
