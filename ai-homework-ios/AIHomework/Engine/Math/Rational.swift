import Foundation

/// Ошибки математического движка. Каждая превращается в понятное пользователю сообщение.
enum MathError: Error, Equatable, Sendable {
    /// Числа вышли за пределы точной 64-битной арифметики.
    case overflow
    case divisionByZero
    /// Не удалось разобрать запись. `detail` — что именно не понято.
    case syntax(detail: String)
    /// Операция не определена (корень из отрицательного, логарифм нуля и т.п.).
    case domain(detail: String)
    /// Задача корректна, но движок такой тип не решает.
    case unsupported(detail: String)

    func message(_ l: L10n) -> String {
        switch self {
        case .overflow:
            return l(
                "Числа слишком большие для точного вычисления на устройстве.",
                "The numbers are too large for exact on-device computation."
            )
        case .divisionByZero:
            return l("Деление на ноль — выражение не имеет смысла.", "Division by zero — the expression is undefined.")
        case .syntax(let detail):
            return l(
                "Не удалось разобрать запись: \(detail). Проверьте распознанный текст.",
                "Could not parse the expression: \(detail). Please check the recognized text."
            )
        case .domain(let detail):
            return l("Выражение не определено: \(detail).", "The expression is undefined: \(detail).")
        case .unsupported(let detail):
            return detail
        }
    }
}

/// Точное рациональное число `num/den` в несократимом виде, `den > 0`.
///
/// Вся школьная арифметика (дроби, корни уравнений, коэффициенты многочленов) считается
/// в рациональных числах без потери точности. Операторы — `throws`: при переполнении
/// `Int` движок не падает и не выдаёт мусор, а честно сообщает об ограничении.
struct Rational: Hashable, Sendable {
    let num: Int
    let den: Int

    static let zero = Rational(0)
    static let one = Rational(1)
    static let two = Rational(2)
    static let minusOne = Rational(-1)

    init(_ value: Int) {
        num = value
        den = 1
    }

    init(_ numerator: Int, _ denominator: Int) throws {
        guard denominator != 0 else { throw MathError.divisionByZero }
        guard numerator != Int.min, denominator != Int.min else { throw MathError.overflow }
        let divisor = Rational.gcd(numerator, denominator)
        var n = numerator / divisor
        var d = denominator / divisor
        if d < 0 {
            n = -n
            d = -d
        }
        num = n
        den = d
    }

    /// Разбор десятичной записи вида `12`, `3.5`, `0,25`. Возвращает `nil`, если число
    /// не помещается в точное представление.
    init?(decimal text: String) {
        let cleaned = text.replacingOccurrences(of: ",", with: ".")
        let parts = cleaned.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2 else { return nil }
        let intPart = String(parts[0])
        let fracPart = parts.count == 2 ? String(parts[1]) : ""
        guard !(intPart.isEmpty && fracPart.isEmpty) else { return nil }
        guard (intPart + fracPart).allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        guard intPart.count + fracPart.count <= 17, fracPart.count <= 12 else { return nil }
        guard let numerator = Int(intPart + fracPart) else { return nil }
        var denominator = 1
        for _ in 0..<fracPart.count { denominator *= 10 }
        guard let value = try? Rational(numerator, denominator) else { return nil }
        self = value
    }

    // MARK: Properties

    var isZero: Bool { num == 0 }
    var isInteger: Bool { den == 1 }
    var isNegative: Bool { num < 0 }
    var isPositive: Bool { num > 0 }
    var doubleValue: Double { Double(num) / Double(den) }
    var signum: Int { num.signum() }

    /// Конечная ли десятичная запись (знаменатель вида 2^a·5^b).
    var hasTerminatingDecimal: Bool {
        var d = den
        while d % 2 == 0 { d /= 2 }
        while d % 5 == 0 { d /= 5 }
        return d == 1
    }

    var magnitude: Rational {
        // num != Int.min гарантируется инициализатором.
        Rational(unchecked: abs(num), den)
    }

    var negated: Rational {
        Rational(unchecked: -num, den)
    }

    private init(unchecked numerator: Int, _ denominator: Int) {
        num = numerator
        den = denominator
    }

    // MARK: Arithmetic

    static func gcd(_ a: Int, _ b: Int) -> Int {
        var x = a.magnitude
        var y = b.magnitude
        while y != 0 {
            (x, y) = (y, x % y)
        }
        return x == 0 ? 1 : Int(clamping: x)
    }

    static func lcm(_ a: Int, _ b: Int) throws -> Int {
        guard a != 0, b != 0 else { return 0 }
        let (product, overflow) = (a / gcd(a, b)).multipliedReportingOverflow(by: b)
        guard !overflow, product != Int.min else { throw MathError.overflow }
        return abs(product)
    }

    private static func mul(_ a: Int, _ b: Int) throws -> Int {
        let (result, overflow) = a.multipliedReportingOverflow(by: b)
        guard !overflow, result != Int.min else { throw MathError.overflow }
        return result
    }

    private static func add(_ a: Int, _ b: Int) throws -> Int {
        let (result, overflow) = a.addingReportingOverflow(b)
        guard !overflow, result != Int.min else { throw MathError.overflow }
        return result
    }

    static func + (lhs: Rational, rhs: Rational) throws -> Rational {
        let divisor = gcd(lhs.den, rhs.den)
        let leftScale = rhs.den / divisor
        let rightScale = lhs.den / divisor
        let numerator = try add(try mul(lhs.num, leftScale), try mul(rhs.num, rightScale))
        let denominator = try mul(lhs.den, leftScale)
        return try Rational(numerator, denominator)
    }

    static func - (lhs: Rational, rhs: Rational) throws -> Rational {
        try lhs + rhs.negated
    }

    static func * (lhs: Rational, rhs: Rational) throws -> Rational {
        // Сокращаем крест-накрест до умножения, чтобы реже переполняться.
        let g1 = gcd(lhs.num, rhs.den)
        let g2 = gcd(rhs.num, lhs.den)
        let numerator = try mul(lhs.num / g1, rhs.num / g2)
        let denominator = try mul(lhs.den / g2, rhs.den / g1)
        return try Rational(numerator, denominator)
    }

    static func / (lhs: Rational, rhs: Rational) throws -> Rational {
        guard !rhs.isZero else { throw MathError.divisionByZero }
        return try lhs * rhs.reciprocal()
    }

    static prefix func - (value: Rational) -> Rational {
        value.negated
    }

    func reciprocal() throws -> Rational {
        guard !isZero else { throw MathError.divisionByZero }
        return try Rational(den, num)
    }

    /// Целая степень (в том числе отрицательная).
    func power(_ exponent: Int) throws -> Rational {
        if exponent == 0 { return .one }
        if exponent < 0 {
            guard exponent != Int.min else { throw MathError.overflow }
            return try reciprocal().power(-exponent)
        }
        guard exponent <= 4096 else { throw MathError.overflow }
        var result = Rational.one
        var base = self
        var e = exponent
        while e > 0 {
            if e & 1 == 1 { result = try result * base }
            e >>= 1
            if e > 0 { base = try base * base }
        }
        return result
    }

    /// Точный корень n-й степени, если он рационален.
    func exactRoot(_ degree: Int) -> Rational? {
        guard degree >= 2 else { return degree == 1 ? self : nil }
        if isNegative {
            guard degree % 2 == 1, let root = magnitude.exactRoot(degree) else { return nil }
            return root.negated
        }
        guard let n = Rational.integerRoot(num, degree), let d = Rational.integerRoot(den, degree) else {
            return nil
        }
        return try? Rational(n, d)
    }

    /// Целый корень n-й степени из неотрицательного целого, если он точный.
    static func integerRoot(_ value: Int, _ degree: Int) -> Int? {
        guard value >= 0, degree >= 1 else { return nil }
        if value < 2 || degree == 1 { return value }
        let estimate = Int(pow(Double(value), 1.0 / Double(degree)).rounded())
        for candidate in max(0, estimate - 1)...(estimate + 1) {
            var product = 1
            var overflowed = false
            for _ in 0..<degree {
                let (next, overflow) = product.multipliedReportingOverflow(by: candidate)
                if overflow {
                    overflowed = true
                    break
                }
                product = next
            }
            if !overflowed, product == value { return candidate }
        }
        return nil
    }
}

extension Rational: Comparable {
    static func < (lhs: Rational, rhs: Rational) -> Bool {
        let (left, o1) = lhs.num.multipliedReportingOverflow(by: rhs.den)
        let (right, o2) = rhs.num.multipliedReportingOverflow(by: lhs.den)
        if o1 || o2 { return lhs.doubleValue < rhs.doubleValue }
        return left < right
    }
}

extension Rational: CustomStringConvertible {
    /// Отладочная ASCII-запись. Для показа пользователю используйте `MathFormatter`.
    var description: String {
        den == 1 ? "\(num)" : "\(num)/\(den)"
    }
}

/// Вспомогательная целочисленная арифметика для задач на делимость.
enum IntegerMath {
    /// Разложение на простые множители: `360 → [(2, 3), (3, 2), (5, 1)]`.
    static func primeFactors(_ value: Int) -> [(prime: Int, power: Int)] {
        var n = abs(value)
        guard n > 1 else { return [] }
        var result: [(prime: Int, power: Int)] = []
        var divisor = 2
        while divisor * divisor <= n {
            if n % divisor == 0 {
                var count = 0
                while n % divisor == 0 {
                    n /= divisor
                    count += 1
                }
                result.append((divisor, count))
            }
            divisor += divisor == 2 ? 1 : 2
        }
        if n > 1 { result.append((n, 1)) }
        return result
    }

    /// Все положительные делители числа (для теоремы о рациональных корнях).
    /// Возвращает `nil`, если число слишком велико для перебора.
    static func divisors(of value: Int, limit: Int = 4_000) -> [Int]? {
        let n = abs(value)
        guard n > 0, n <= 1_000_000_000_000 else { return nil }
        var result = [1]
        for factor in primeFactors(n) {
            var extended: [Int] = []
            var multiplier = 1
            for _ in 0...factor.power {
                extended.append(contentsOf: result.map { $0 * multiplier })
                multiplier *= factor.prime
            }
            result = extended
            if result.count > limit { return nil }
        }
        return result.sorted()
    }

    /// Представление `√n = outside · √inside`, где `inside` свободно от квадратов.
    static func simplifySquareRoot(_ n: Int) -> (outside: Int, inside: Int) {
        guard n > 0 else { return (0, 0) }
        var outside = 1
        var inside = 1
        for factor in primeFactors(n) {
            for _ in 0..<(factor.power / 2) { outside *= factor.prime }
            if factor.power % 2 == 1 { inside *= factor.prime }
        }
        return (outside, inside)
    }
}
