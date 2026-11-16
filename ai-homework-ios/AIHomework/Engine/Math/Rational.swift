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
    /// Запись слишком длинная или слишком глубоко вложенная для разбора на устройстве.
    case tooComplex

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
        case .tooComplex:
            return l(
                "Запись слишком длинная или в ней слишком много вложенных скобок — такое выражение не разбирается на устройстве. Сократите запись или разбейте задание на части.",
                "The expression is too long or nested too deeply to be parsed on the device. Shorten it or split the task into parts."
            )
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

/// Длинное целое без внешних зависимостей — для точных ответов вроде `2^100` и `10^20 + 1` (AUD-59).
///
/// Умеет только то, что нужно школьной арифметике: сложение, вычитание, умножение, степень
/// и десятичную запись. Число цифр ограничено, чтобы вычисление не «висело».
struct BigInteger: Equatable, Sendable, CustomStringConvertible {
    /// «Цифры» по основанию 10⁹, младшие первыми; без ведущих нулей (у нуля — пустой массив).
    private(set) var limbs: [UInt32]
    private(set) var isNegative: Bool

    private static let base: UInt64 = 1_000_000_000

    init(_ value: Int) {
        isNegative = value < 0
        var magnitude = value.magnitude
        var limbs: [UInt32] = []
        while magnitude > 0 {
            limbs.append(UInt32(magnitude % UInt(BigInteger.base)))
            magnitude /= UInt(BigInteger.base)
        }
        self.limbs = limbs
    }

    private init(limbs: [UInt32], isNegative: Bool) {
        var trimmed = limbs
        while trimmed.last == 0 { trimmed.removeLast() }
        self.limbs = trimmed
        self.isNegative = trimmed.isEmpty ? false : isNegative
    }

    var isZero: Bool { limbs.isEmpty }

    /// Количество десятичных цифр (у нуля — 1).
    var digitCount: Int {
        guard let top = limbs.last else { return 1 }
        return (limbs.count - 1) * 9 + String(top).count
    }

    /// Значение как `Int`, если помещается.
    var intValue: Int? {
        var result = 0
        for limb in limbs.reversed() {
            let (scaled, o1) = result.multipliedReportingOverflow(by: Int(BigInteger.base))
            let (sum, o2) = scaled.addingReportingOverflow(Int(limb))
            if o1 || o2 { return nil }
            result = sum
        }
        return isNegative ? -result : result
    }

    var description: String {
        guard let top = limbs.last else { return "0" }
        var text = String(top)
        for limb in limbs.dropLast().reversed() {
            let digits = String(limb)
            text += String(repeating: "0", count: 9 - digits.count) + digits
        }
        return (isNegative ? "-" : "") + text
    }

    var negated: BigInteger { BigInteger(limbs: limbs, isNegative: !isNegative) }
    var magnitude: BigInteger { BigInteger(limbs: limbs, isNegative: false) }

    private static func compareMagnitudes(_ a: [UInt32], _ b: [UInt32]) -> Int {
        if a.count != b.count { return a.count < b.count ? -1 : 1 }
        for index in stride(from: a.count - 1, through: 0, by: -1) where a[index] != b[index] {
            return a[index] < b[index] ? -1 : 1
        }
        return 0
    }

    private static func addMagnitudes(_ a: [UInt32], _ b: [UInt32]) -> [UInt32] {
        var result: [UInt32] = []
        result.reserveCapacity(max(a.count, b.count) + 1)
        var carry: UInt64 = 0
        for index in 0..<max(a.count, b.count) {
            let sum = UInt64(index < a.count ? a[index] : 0) + UInt64(index < b.count ? b[index] : 0) + carry
            result.append(UInt32(sum % base))
            carry = sum / base
        }
        if carry > 0 { result.append(UInt32(carry)) }
        return result
    }

    /// `a − b` при `|a| ≥ |b|`.
    private static func subtractMagnitudes(_ a: [UInt32], _ b: [UInt32]) -> [UInt32] {
        var result: [UInt32] = []
        result.reserveCapacity(a.count)
        var borrow: Int64 = 0
        for index in 0..<a.count {
            var difference = Int64(a[index]) - Int64(index < b.count ? b[index] : 0) - borrow
            if difference < 0 {
                difference += Int64(base)
                borrow = 1
            } else {
                borrow = 0
            }
            result.append(UInt32(difference))
        }
        return result
    }

    static func + (lhs: BigInteger, rhs: BigInteger) -> BigInteger {
        if lhs.isNegative == rhs.isNegative {
            return BigInteger(limbs: addMagnitudes(lhs.limbs, rhs.limbs), isNegative: lhs.isNegative)
        }
        let order = compareMagnitudes(lhs.limbs, rhs.limbs)
        if order == 0 { return BigInteger(0) }
        return order > 0
            ? BigInteger(limbs: subtractMagnitudes(lhs.limbs, rhs.limbs), isNegative: lhs.isNegative)
            : BigInteger(limbs: subtractMagnitudes(rhs.limbs, lhs.limbs), isNegative: rhs.isNegative)
    }

    static func - (lhs: BigInteger, rhs: BigInteger) -> BigInteger {
        lhs + rhs.negated
    }

    static func * (lhs: BigInteger, rhs: BigInteger) -> BigInteger {
        guard !lhs.isZero, !rhs.isZero else { return BigInteger(0) }
        var result = [UInt64](repeating: 0, count: lhs.limbs.count + rhs.limbs.count + 1)
        for (i, a) in lhs.limbs.enumerated() {
            var carry: UInt64 = 0
            for (j, b) in rhs.limbs.enumerated() {
                let current = result[i + j] + UInt64(a) * UInt64(b) + carry
                result[i + j] = current % base
                carry = current / base
            }
            var k = i + rhs.limbs.count
            while carry > 0 {
                let current = result[k] + carry
                result[k] = current % base
                carry = current / base
                k += 1
            }
        }
        return BigInteger(limbs: result.map { UInt32($0) }, isNegative: lhs.isNegative != rhs.isNegative)
    }

    /// Неотрицательная целая степень; `overflow`, если в результате больше `maxDigits` цифр.
    func power(_ exponent: Int, maxDigits: Int) throws -> BigInteger {
        guard exponent >= 0 else { throw MathError.overflow }
        if exponent == 0 { return BigInteger(1) }
        if isZero { return self }
        // Оценка числа цифр заранее: 2^(2^30) не считаем, а сразу отказываем.
        guard Double(exponent) * log10Magnitude <= Double(maxDigits) + 1 else { throw MathError.overflow }
        var result = BigInteger(1)
        var base = self
        var e = exponent
        while e > 0 {
            if e & 1 == 1 {
                result = result * base
                guard result.digitCount <= maxDigits else { throw MathError.overflow }
            }
            e >>= 1
            if e > 0 {
                base = base * base
                guard base.digitCount <= maxDigits * 2 else { throw MathError.overflow }
            }
        }
        return result
    }

    /// Приближённый десятичный логарифм модуля (только для оценки размера степени).
    private var log10Magnitude: Double {
        var value = 0.0
        for limb in limbs.reversed().prefix(2) { value = value * Double(BigInteger.base) + Double(limb) }
        return Foundation.log10(max(value, 1)) + 9 * Double(max(limbs.count - 2, 0))
    }
}
