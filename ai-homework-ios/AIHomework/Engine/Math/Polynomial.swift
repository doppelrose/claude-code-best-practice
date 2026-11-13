import Foundation

/// Одночлен без коэффициента: произведение степеней переменных, например `x²y`.
struct Monomial: Hashable, Sendable {
    /// Показатели степеней по именам переменных (только положительные).
    let powers: [String: Int]

    static let one = Monomial(powers: [:])

    init(powers: [String: Int]) {
        self.powers = powers.filter { $0.value != 0 }
    }

    init(variable: String, power: Int = 1) {
        self.init(powers: [variable: power])
    }

    var degree: Int { powers.values.reduce(0, +) }
    var isConstant: Bool { powers.isEmpty }
    var variables: [String] { powers.keys.sorted() }

    func degree(in variable: String) -> Int {
        powers[variable] ?? 0
    }

    static func * (lhs: Monomial, rhs: Monomial) -> Monomial {
        var result = lhs.powers
        for (name, power) in rhs.powers {
            result[name, default: 0] += power
        }
        return Monomial(powers: result)
    }

    /// Порядок для вывода: сначала старшая степень, затем лексикографически.
    static func displayOrder(_ a: Monomial, _ b: Monomial) -> Bool {
        if a.degree != b.degree { return a.degree > b.degree }
        let names = Set(a.powers.keys).union(b.powers.keys).sorted()
        for name in names {
            let pa = a.degree(in: name)
            let pb = b.degree(in: name)
            if pa != pb { return pa > pb }
        }
        return false
    }
}

/// Многочлен от нескольких переменных с рациональными коэффициентами.
struct Polynomial: Hashable, Sendable {
    private(set) var terms: [Monomial: Rational]

    static let zero = Polynomial(terms: [:])
    static let one = Polynomial(constant: .one)

    init(terms: [Monomial: Rational]) {
        self.terms = terms.filter { !$0.value.isZero }
    }

    init(constant: Rational) {
        self.init(terms: [.one: constant])
    }

    init(variable: String) {
        self.init(terms: [Monomial(variable: variable): .one])
    }

    /// Одномерный многочлен по коэффициентам `c[0] + c[1]·x + c[2]·x² + …`.
    init(coefficients: [Rational], variable: String) {
        var result: [Monomial: Rational] = [:]
        for (power, coefficient) in coefficients.enumerated() where !coefficient.isZero {
            result[Monomial(powers: [variable: power])] = coefficient
        }
        self.init(terms: result)
    }

    // MARK: Properties

    var isZero: Bool { terms.isEmpty }

    var isConstant: Bool {
        terms.keys.allSatisfy { $0.isConstant }
    }

    /// Значение, если многочлен — константа.
    var constantValue: Rational? {
        guard isConstant else { return nil }
        return terms[.one] ?? .zero
    }

    var constantTerm: Rational {
        terms[.one] ?? .zero
    }

    var variables: [String] {
        Set(terms.keys.flatMap { $0.powers.keys }).sorted()
    }

    var totalDegree: Int {
        terms.keys.map { $0.degree }.max() ?? 0
    }

    func degree(in variable: String) -> Int {
        terms.keys.map { $0.degree(in: variable) }.max() ?? 0
    }

    /// Члены в порядке вывода (по убыванию степени).
    var orderedTerms: [(monomial: Monomial, coefficient: Rational)] {
        terms
            .map { (monomial: $0.key, coefficient: $0.value) }
            .sorted { Monomial.displayOrder($0.monomial, $1.monomial) }
    }

    /// Коэффициенты одномерного многочлена: индекс — степень. `nil`, если переменных больше одной.
    func coefficients(in variable: String) -> [Rational]? {
        guard variables.allSatisfy({ $0 == variable }) else { return nil }
        var result = [Rational](repeating: .zero, count: degree(in: variable) + 1)
        for (monomial, coefficient) in terms {
            result[monomial.degree(in: variable)] = coefficient
        }
        return result
    }

    /// Коэффициент при первой степени переменной и остаток — для линейных форм.
    func coefficient(ofLinear variable: String) -> Rational {
        terms[Monomial(variable: variable)] ?? .zero
    }

    // MARK: Arithmetic

    var negated: Polynomial {
        Polynomial(terms: terms.mapValues { $0.negated })
    }

    static func + (lhs: Polynomial, rhs: Polynomial) throws -> Polynomial {
        var result = lhs.terms
        for (monomial, coefficient) in rhs.terms {
            if let existing = result[monomial] {
                result[monomial] = try existing + coefficient
            } else {
                result[monomial] = coefficient
            }
        }
        return Polynomial(terms: result)
    }

    static func - (lhs: Polynomial, rhs: Polynomial) throws -> Polynomial {
        try lhs + rhs.negated
    }

    static func * (lhs: Polynomial, rhs: Polynomial) throws -> Polynomial {
        guard lhs.terms.count * rhs.terms.count <= 20_000 else { throw MathError.overflow }
        var result: [Monomial: Rational] = [:]
        for (m1, c1) in lhs.terms {
            for (m2, c2) in rhs.terms {
                let monomial = m1 * m2
                let product = try c1 * c2
                if let existing = result[monomial] {
                    result[monomial] = try existing + product
                } else {
                    result[monomial] = product
                }
            }
        }
        return Polynomial(terms: result)
    }

    func scaled(by factor: Rational) throws -> Polynomial {
        var result: [Monomial: Rational] = [:]
        for (monomial, coefficient) in terms {
            result[monomial] = try coefficient * factor
        }
        return Polynomial(terms: result)
    }

    func divided(by divisor: Rational) throws -> Polynomial {
        try scaled(by: try divisor.reciprocal())
    }

    func power(_ exponent: Int) throws -> Polynomial {
        guard exponent >= 0 else { throw MathError.unsupported(detail: "negative polynomial power") }
        guard exponent <= 64 else { throw MathError.overflow }
        var result = Polynomial.one
        for _ in 0..<exponent {
            result = try result * self
        }
        return result
    }

    func evaluate(_ values: [String: Rational]) throws -> Rational {
        var sum = Rational.zero
        for (monomial, coefficient) in terms {
            var product = coefficient
            for (name, power) in monomial.powers {
                guard let value = values[name] else {
                    throw MathError.unsupported(detail: "unbound variable \(name)")
                }
                product = try product * (try value.power(power))
            }
            sum = try sum + product
        }
        return sum
    }

    func evaluate(_ values: [String: Double]) -> Double {
        var sum = 0.0
        for (monomial, coefficient) in terms {
            var product = coefficient.doubleValue
            for (name, power) in monomial.powers {
                product *= Foundation.pow(values[name] ?? .nan, Double(power))
            }
            sum += product
        }
        return sum
    }

    /// Подстановка многочлена вместо переменной.
    func substituting(_ variable: String, with replacement: Polynomial) throws -> Polynomial {
        var result = Polynomial.zero
        for (monomial, coefficient) in terms {
            let power = monomial.degree(in: variable)
            var rest = monomial.powers
            rest[variable] = nil
            var term = Polynomial(terms: [Monomial(powers: rest): coefficient])
            if power > 0 {
                term = try term * (try replacement.power(power))
            }
            result = try result + term
        }
        return result
    }

    func derivative(in variable: String) throws -> Polynomial {
        var result: [Monomial: Rational] = [:]
        for (monomial, coefficient) in terms {
            let power = monomial.degree(in: variable)
            guard power > 0 else { continue }
            var powers = monomial.powers
            powers[variable] = power - 1
            let key = Monomial(powers: powers)
            let value = try coefficient * Rational(power)
            result[key] = try (result[key] ?? .zero) + value
        }
        return Polynomial(terms: result)
    }

    func antiderivative(in variable: String) throws -> Polynomial {
        var result: [Monomial: Rational] = [:]
        for (monomial, coefficient) in terms {
            let power = monomial.degree(in: variable)
            var powers = monomial.powers
            powers[variable] = power + 1
            result[Monomial(powers: powers)] = try coefficient / Rational(power + 1)
        }
        return Polynomial(terms: result)
    }

    // MARK: Integer normalisation

    /// Наименьший общий знаменатель коэффициентов.
    func commonDenominator() throws -> Int {
        var result = 1
        for coefficient in terms.values {
            result = try Rational.lcm(result, coefficient.den)
        }
        return result
    }

    /// НОД числителей (после приведения к целым коэффициентам).
    func numeratorGCD() -> Int {
        var result = 0
        for coefficient in terms.values {
            result = Rational.gcd(result, coefficient.num)
            if result == 0 { result = abs(coefficient.num) }
        }
        return max(result, 1)
    }
}

// MARK: - Univariate algorithms

/// Алгоритмы для многочленов от одной переменной (коэффициенты — по возрастанию степени).
enum UnivariatePolynomial {
    static func trimmed(_ coefficients: [Rational]) -> [Rational] {
        var result = coefficients
        while let last = result.last, last.isZero, result.count > 1 {
            result.removeLast()
        }
        return result.isEmpty ? [.zero] : result
    }

    static func degree(_ coefficients: [Rational]) -> Int {
        trimmed(coefficients).count - 1
    }

    static func isZero(_ coefficients: [Rational]) -> Bool {
        coefficients.allSatisfy { $0.isZero }
    }

    static func evaluate(_ coefficients: [Rational], at x: Rational) throws -> Rational {
        var result = Rational.zero
        for coefficient in coefficients.reversed() {
            result = try (try result * x) + coefficient
        }
        return result
    }

    static func evaluate(_ coefficients: [Rational], at x: Double) -> Double {
        var result = 0.0
        for coefficient in coefficients.reversed() {
            result = result * x + coefficient.doubleValue
        }
        return result
    }

    /// Деление с остатком.
    static func divide(_ dividend: [Rational], by divisor: [Rational]) throws -> (quotient: [Rational], remainder: [Rational]) {
        let d = trimmed(divisor)
        guard !isZero(d) else { throw MathError.divisionByZero }
        var remainder = trimmed(dividend)
        let divisorDegree = d.count - 1
        guard remainder.count - 1 >= divisorDegree else { return ([.zero], remainder) }
        var quotient = [Rational](repeating: .zero, count: remainder.count - divisorDegree)
        let lead = d[divisorDegree]
        var index = remainder.count - 1
        while index >= divisorDegree {
            let factor = try remainder[index] / lead
            quotient[index - divisorDegree] = factor
            if !factor.isZero {
                for k in 0...divisorDegree {
                    remainder[index - divisorDegree + k] = try remainder[index - divisorDegree + k] - (try factor * d[k])
                }
            }
            index -= 1
        }
        return (trimmed(quotient), trimmed(Array(remainder.prefix(max(divisorDegree, 1)))))
    }

    /// НОД двух многочленов (со старшим коэффициентом 1).
    static func gcd(_ a: [Rational], _ b: [Rational]) throws -> [Rational] {
        var x = trimmed(a)
        var y = trimmed(b)
        var guardCounter = 0
        while !isZero(y) {
            let remainder = try divide(x, by: y).remainder
            x = y
            y = remainder
            guardCounter += 1
            if guardCounter > 200 { throw MathError.overflow }
        }
        guard let lead = x.last, !lead.isZero else { return [.one] }
        return try x.map { try $0 / lead }
    }

    /// Приведение к целым коэффициентам без общего множителя. Возвращает множитель,
    /// на который был умножен исходный многочлен.
    static func integerForm(_ coefficients: [Rational]) throws -> (coefficients: [Int], multiplier: Rational) {
        let trimmedCoefficients = trimmed(coefficients)
        var denominator = 1
        for coefficient in trimmedCoefficients {
            denominator = try Rational.lcm(denominator, coefficient.den)
        }
        var integers: [Int] = []
        for coefficient in trimmedCoefficients {
            let scaled = try coefficient * Rational(denominator)
            integers.append(scaled.num)
        }
        var divisor = 0
        for value in integers {
            divisor = divisor == 0 ? abs(value) : Rational.gcd(divisor, value)
        }
        if divisor == 0 { divisor = 1 }
        let reduced = integers.map { $0 / divisor }
        let multiplier = try Rational(denominator, divisor)
        return (reduced, multiplier)
    }

    /// Рациональные корни по теореме о рациональных корнях (с кратностями) и остаток после деления.
    static func extractRationalRoots(_ coefficients: [Rational]) throws -> (roots: [Rational], remaining: [Rational]) {
        var current = trimmed(coefficients)
        var roots: [Rational] = []

        // Корень x = 0.
        while current.count > 1, current[0].isZero {
            roots.append(.zero)
            current.removeFirst()
        }

        var searching = current.count > 1
        while searching {
            searching = false
            let form = try integerForm(current)
            guard let constant = form.coefficients.first, let lead = form.coefficients.last,
                let numerators = IntegerMath.divisors(of: constant),
                let denominators = IntegerMath.divisors(of: lead),
                numerators.count * denominators.count <= 40_000
            else { break }

            search: for p in numerators {
                for q in denominators {
                    for sign in [1, -1] {
                        guard let candidate = try? Rational(sign * p, q) else { continue }
                        guard let value = try? evaluate(current, at: candidate), value.isZero else { continue }
                        // Делим на (x − candidate).
                        let divisor = [candidate.negated, Rational.one]
                        current = try divide(current, by: divisor).quotient
                        roots.append(candidate)
                        searching = current.count > 1
                        break search
                    }
                }
            }
        }
        return (roots, current)
    }
}
