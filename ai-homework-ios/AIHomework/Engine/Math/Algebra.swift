import Foundation

/// Рациональная функция `numerator / denominator`.
struct RationalFunction: Sendable, Hashable {
    var numerator: Polynomial
    var denominator: Polynomial

    init(_ numerator: Polynomial, _ denominator: Polynomial = .one) {
        self.numerator = numerator
        self.denominator = denominator
    }

    var isPolynomial: Bool { denominator.isConstant }

    /// Многочлен, если знаменатель — ненулевая константа.
    func asPolynomial() throws -> Polynomial? {
        guard let constant = denominator.constantValue else { return nil }
        guard !constant.isZero else { throw MathError.divisionByZero }
        return try numerator.divided(by: constant)
    }

    static func + (lhs: RationalFunction, rhs: RationalFunction) throws -> RationalFunction {
        if lhs.denominator == rhs.denominator {
            return RationalFunction(try lhs.numerator + rhs.numerator, lhs.denominator)
        }
        let numerator = try (try lhs.numerator * rhs.denominator) + (try rhs.numerator * lhs.denominator)
        return RationalFunction(numerator, try lhs.denominator * rhs.denominator)
    }

    static func - (lhs: RationalFunction, rhs: RationalFunction) throws -> RationalFunction {
        try lhs + RationalFunction(rhs.numerator.negated, rhs.denominator)
    }

    static func * (lhs: RationalFunction, rhs: RationalFunction) throws -> RationalFunction {
        RationalFunction(try lhs.numerator * rhs.numerator, try lhs.denominator * rhs.denominator)
    }

    static func / (lhs: RationalFunction, rhs: RationalFunction) throws -> RationalFunction {
        guard !rhs.numerator.isZero else { throw MathError.divisionByZero }
        return RationalFunction(try lhs.numerator * rhs.denominator, try lhs.denominator * rhs.numerator)
    }

    func power(_ exponent: Int) throws -> RationalFunction {
        if exponent >= 0 {
            return RationalFunction(try numerator.power(exponent), try denominator.power(exponent))
        }
        guard !numerator.isZero else { throw MathError.divisionByZero }
        return RationalFunction(try denominator.power(-exponent), try numerator.power(-exponent))
    }

    /// Сокращение: константный знаменатель «вносится» в числитель, для одной переменной
    /// числитель и знаменатель делятся на их НОД, знаменатель делается со старшим коэффициентом > 0.
    func reduced() throws -> RationalFunction {
        if let polynomial = try asPolynomial() {
            return RationalFunction(polynomial)
        }
        let variables = Set(numerator.variables).union(denominator.variables)
        guard variables.count == 1, let variable = variables.first,
            let n = numerator.coefficients(in: variable), let d = denominator.coefficients(in: variable)
        else { return self }

        let common = try UnivariatePolynomial.gcd(n, d)
        var reducedNumerator = n
        var reducedDenominator = d
        if UnivariatePolynomial.degree(common) > 0 {
            reducedNumerator = try UnivariatePolynomial.divide(n, by: common).quotient
            reducedDenominator = try UnivariatePolynomial.divide(d, by: common).quotient
        }
        // Нормируем: целые взаимно простые коэффициенты, положительный старший коэффициент знаменателя.
        let denominatorForm = try UnivariatePolynomial.integerForm(reducedDenominator)
        var scale = denominatorForm.multiplier
        if let lead = denominatorForm.coefficients.last, lead < 0 {
            scale = scale.negated
        }
        let finalNumerator = try reducedNumerator.map { try $0 * scale }
        let finalDenominator = try reducedDenominator.map { try $0 * scale }
        let result = RationalFunction(
            Polynomial(coefficients: finalNumerator, variable: variable),
            Polynomial(coefficients: finalDenominator, variable: variable)
        )
        if let polynomial = try result.asPolynomial() {
            return RationalFunction(polynomial)
        }
        return result
    }
}

/// Число вида `p + q·√n` (n > 1 свободно от квадратов) — точные корни квадратных уравнений.
struct Surd: Sendable, Hashable {
    var rationalPart: Rational
    var coefficient: Rational
    var radicand: Int

    var double: Double {
        rationalPart.doubleValue + coefficient.doubleValue * Double(radicand).squareRoot()
    }

    /// `p + q·√value` с вынесением множителя из-под корня. Возвращает рациональное число,
    /// если корень извлекается нацело.
    static func make(rationalPart: Rational, coefficient: Rational, sqrtOf value: Rational) throws -> RootValue {
        guard !value.isNegative else { throw MathError.domain(detail: "√(a), a < 0") }
        if coefficient.isZero || value.isZero { return .rational(rationalPart) }
        // √(a/b) = √(a·b)/b
        let product = try Rational(value.num) * Rational(value.den)
        guard product.isInteger else { throw MathError.overflow }
        let simplified = IntegerMath.simplifySquareRoot(product.num)
        let outside = try (try Rational(simplified.outside) / Rational(value.den)) * coefficient
        if simplified.inside == 1 {
            return .rational(try rationalPart + outside)
        }
        return .surd(Surd(rationalPart: rationalPart, coefficient: outside, radicand: simplified.inside))
    }
}

/// Корень уравнения: точный рациональный, точный с радикалом или приближённый.
enum RootValue: Sendable, Hashable {
    case rational(Rational)
    case surd(Surd)
    /// Точное значение вида `r·π` — корни тригонометрических уравнений.
    case piMultiple(Rational)
    case approx(Double)

    var double: Double {
        switch self {
        case .rational(let r): return r.doubleValue
        case .surd(let s): return s.double
        case .piMultiple(let r): return r.doubleValue * Double.pi
        case .approx(let d): return d
        }
    }

    var isExact: Bool {
        if case .approx = self { return false }
        return true
    }

    var rational: Rational? {
        if case .rational(let r) = self { return r }
        return nil
    }
}

extension MathFormatter {
    /// `(3 + √5)/2`, `−2√3`, `√2/2`.
    func surd(_ s: Surd) -> String {
        let commonDenominator = (try? Rational.lcm(s.rationalPart.den, s.coefficient.den)) ?? 1
        let p = s.rationalPart.num * (commonDenominator / s.rationalPart.den)
        let k = s.coefficient.num * (commonDenominator / s.coefficient.den)
        let root = "√\(s.radicand)"
        let radicalMagnitude = abs(k) == 1 ? root : "\(abs(k))\(root)"

        var numerator: String
        if p == 0 {
            numerator = (k < 0 ? MathFormatter.minus : "") + radicalMagnitude
        } else {
            numerator = integer(p) + (k < 0 ? " − " : " + ") + radicalMagnitude
        }
        if commonDenominator == 1 { return numerator }
        if p != 0 { numerator = "(\(numerator))" }
        return numerator + "/\(commonDenominator)"
    }

    func root(_ value: RootValue) -> String {
        switch value {
        case .rational(let r): return rational(r)
        case .surd(let s): return surd(s)
        case .piMultiple(let r): return piMultiple(r)
        case .approx(let d): return approx(d)
        }
    }

    /// Корень с приближением: `(3 + √5)/2 ≈ 2,61803`.
    func rootWithApproximation(_ value: RootValue) -> String {
        switch value {
        case .rational(let r): return rationalWithApproximation(r)
        case .surd(let s): return surd(s) + " ≈ " + approx(s.double)
        case .piMultiple(let r): return r.isZero ? "0" : piMultiple(r) + " ≈ " + approx(value.double)
        case .approx(let d): return "≈ " + approx(d)
        }
    }
}

/// Преобразование синтаксического дерева в многочлены и рациональные функции.
enum Algebra {
    /// Рациональная функция, если выражение к ней сводится; иначе `nil`.
    static func rationalFunction(_ expr: Expr) throws -> RationalFunction? {
        // Подвыражение без переменных — пробуем вычислить точно (√16, 2³, 4^(1/2)).
        if expr.isConstant {
            switch expr {
            case .num(let r):
                return RationalFunction(Polynomial(constant: r))
            default:
                // Ошибки области определения (деление на ноль, √ из отрицательного) пробрасываем.
                let value = try MathEvaluator().evaluate(expr)
                // Иррациональная константа (π, √2) — не многочлен с рациональными коэффициентами.
                guard let rational = value.rational else { return nil }
                return RationalFunction(Polynomial(constant: rational))
            }
        }

        switch expr {
        case .num(let r):
            return RationalFunction(Polynomial(constant: r))
        case .real, .const:
            return nil
        case .sym(let name):
            return RationalFunction(Polynomial(variable: name))
        case .neg(let inner):
            guard let value = try rationalFunction(inner) else { return nil }
            return RationalFunction(value.numerator.negated, value.denominator)
        case .bin(let op, let a, let b):
            if op == .pow {
                guard let base = try rationalFunction(a) else { return nil }
                guard b.isConstant, let exponentValue = try? MathEvaluator().evaluate(b),
                    let exponent = exponentValue.rational, exponent.isInteger, abs(exponent.num) <= 64
                else { return nil }
                return try base.power(exponent.num)
            }
            guard let left = try rationalFunction(a), let right = try rationalFunction(b) else { return nil }
            switch op {
            case .add: return try left + right
            case .sub: return try left - right
            case .mul: return try left * right
            case .div: return try left / right
            case .pow: return nil
            }
        case .fn:
            return nil
        }
    }

    /// Многочлен, если выражение — многочлен (знаменатели только числовые).
    static func polynomial(_ expr: Expr) throws -> Polynomial? {
        guard let function = try rationalFunction(expr) else { return nil }
        return try function.asPolynomial()
    }

    /// Вещественные корни многочлена (коэффициенты по возрастанию степени).
    /// Корни ищутся между соседними критическими точками — рекурсия по производной.
    static func realRoots(_ coefficients: [Double]) -> [Double] {
        var c = coefficients
        while let last = c.last, last == 0, c.count > 1 { c.removeLast() }
        let degree = c.count - 1
        guard degree >= 1 else { return [] }
        if degree == 1 { return [-c[0] / c[1]] }
        if degree == 2 {
            let discriminant = c[1] * c[1] - 4 * c[2] * c[0]
            if discriminant < 0 { return [] }
            if discriminant == 0 { return [-c[1] / (2 * c[2])] }
            let root = discriminant.squareRoot()
            // Устойчивая к потере точности форма.
            let q = -0.5 * (c[1] + (c[1] >= 0 ? root : -root))
            return [q / c[2], c[0] / q].sorted()
        }

        func value(_ x: Double) -> Double {
            var result = 0.0
            for coefficient in c.reversed() { result = result * x + coefficient }
            return result
        }

        let lead = c[degree]
        let bound = 1 + (c.dropLast().map { abs($0 / lead) }.max() ?? 0)
        let derivative = (1...degree).map { Double($0) * c[$0] }
        let critical = realRoots(derivative).filter { abs($0) < bound }.sorted()
        let points = [-bound] + critical + [bound]
        let scale = c.map { abs($0) }.max() ?? 1
        var roots: [Double] = []

        func add(_ root: Double) {
            if !roots.contains(where: { abs($0 - root) <= 1e-9 * max(1, abs(root)) }) {
                roots.append(root)
            }
        }

        for point in critical where abs(value(point)) <= 1e-10 * scale * max(1, Foundation.pow(abs(point), Double(degree))) {
            add(point)
        }
        for index in 0..<(points.count - 1) {
            var a = points[index]
            var b = points[index + 1]
            var fa = value(a)
            let fb = value(b)
            if fa == 0 { add(a); continue }
            if fb == 0 { add(b); continue }
            guard (fa < 0) != (fb < 0) else { continue }
            for _ in 0..<200 {
                let mid = (a + b) / 2
                let fm = value(mid)
                if fm == 0 { a = mid; b = mid; break }
                if (fm < 0) == (fa < 0) {
                    a = mid
                    fa = fm
                } else {
                    b = mid
                }
                if abs(b - a) <= 1e-15 * max(1, abs(a)) { break }
            }
            add((a + b) / 2)
        }
        return roots.sorted()
    }

    /// Ближайшая «простая» дробь к вещественному числу (цепные дроби).
    static func rationalApproximation(_ value: Double, maxDenominator: Int = 10_000, tolerance: Double = 1e-9) -> Rational? {
        guard value.isFinite, abs(value) < 1e9 else { return nil }
        var x = value
        var previousNumerator = 1
        var numerator = Int(floor(x))
        var previousDenominator = 0
        var denominator = 1
        for _ in 0..<40 {
            if abs(Double(numerator) / Double(denominator) - value) <= tolerance * max(1, abs(value)) {
                return try? Rational(numerator, denominator)
            }
            let fractional = x - floor(x)
            guard fractional > 1e-14 else { break }
            x = 1 / fractional
            let term = floor(x)
            guard term < 1e9 else { break }
            let a = Int(term)
            let (n1, o1) = a.multipliedReportingOverflow(by: numerator)
            let (d1, o2) = a.multipliedReportingOverflow(by: denominator)
            if o1 || o2 { break }
            let nextNumerator = n1 &+ previousNumerator
            let nextDenominator = d1 &+ previousDenominator
            if nextDenominator > maxDenominator || nextDenominator <= 0 { break }
            previousNumerator = numerator
            numerator = nextNumerator
            previousDenominator = denominator
            denominator = nextDenominator
        }
        return nil
    }
}
