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
            throw MathError.unsupported(
                detail: l(
                    "Локальный движок решает только рациональные неравенства (многочлены и дроби из многочленов). Это неравенство к ним не сводится.",
                    "The local engine solves only rational inequalities (polynomials and fractions of polynomials). This one does not reduce to that form."
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
                approximate: approximate,
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
            kind: kind, intervals: intervals, variable: x, steps: steps, approximate: approximate,
            explanation: l(
                "Метод интервалов: находим точки, в которых выражение равно нулю или не определено, они делят прямую на промежутки с постоянным знаком. Остаётся выбрать промежутки с нужным знаком.",
                "The interval method: find the points where the expression is zero or undefined; they split the line into intervals of constant sign. Then pick the intervals with the required sign."
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
            approximate: false,
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
    private func comparisonText(_ intervals: [SolutionInterval], variable x: String) -> String? {
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

    private func finish(
        kind: String, intervals: [SolutionInterval], variable x: String, steps: [SolutionStep], approximate: Bool, explanation: String
    ) -> InequalityOutcome {
        let answer: String
        if intervals.isEmpty {
            answer = l("Нет решений", "No solutions")
        } else if intervals.count == 1, intervals[0].lower == nil, intervals[0].upper == nil {
            answer = l("\(x) — любое число", "\(x) is any number")
        } else if intervals.count == 1, intervals[0].isPoint, let point = intervals[0].lower {
            answer = "\(x) = \(fmt.root(point))"
        } else if let comparison = comparisonText(intervals, variable: x) {
            answer = comparison + l(", то есть ", ", i.e. ") + setText(intervals, variable: x)
        } else {
            answer = setText(intervals, variable: x)
        }
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
