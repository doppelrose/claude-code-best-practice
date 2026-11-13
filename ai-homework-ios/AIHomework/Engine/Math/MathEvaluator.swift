import Foundation

/// Значение выражения. Движок, пока возможно, держит результат точным.
enum MathValue: Sendable, Equatable {
    /// Точное рациональное число.
    case exact(Rational)
    /// Точное число вида `r·π` — чтобы `sin 30°` и `cos(π/3)` давали ровно `1/2`.
    case piMultiple(Rational)
    /// Приближённое вещественное число.
    case approx(Double)

    var double: Double {
        switch self {
        case .exact(let r): return r.doubleValue
        case .piMultiple(let r): return r.doubleValue * Double.pi
        case .approx(let d): return d
        }
    }

    var rational: Rational? {
        if case .exact(let r) = self { return r }
        if case .piMultiple(let r) = self, r.isZero { return .zero }
        return nil
    }

    var isExact: Bool {
        if case .approx = self { return false }
        return true
    }

    /// Литерал для подстановки значения обратно в выражение.
    var literal: Expr {
        switch self {
        case .exact(let r): return .num(r)
        case .piMultiple(let r):
            if r == .one { return .const(.pi) }
            return .bin(.mul, .num(r), .const(.pi))
        case .approx(let d): return .real(d)
        }
    }
}

/// Одно арифметическое действие: выражение с уже вычисленными операндами и его результат.
struct EvaluationStep: Sendable, Equatable {
    var operation: Expr
    var result: MathValue
}

/// Вычисление выражений.
struct MathEvaluator: Sendable {
    init() {}

    func evaluate(_ expr: Expr, _ environment: [String: MathValue] = [:]) throws -> MathValue {
        var steps: [EvaluationStep]? = nil
        return try eval(expr, environment, &steps)
    }

    /// Вычисление «по действиям» — с записью каждой операции.
    func evaluateWithSteps(_ expr: Expr, _ environment: [String: MathValue] = [:]) throws -> (value: MathValue, steps: [EvaluationStep]) {
        var steps: [EvaluationStep]? = []
        let value = try eval(expr, environment, &steps)
        return (value, steps ?? [])
    }

    /// Быстрое вещественное вычисление для численных методов. `nan`, если не определено.
    func numeric(_ expr: Expr, variable: String, at x: Double) -> Double {
        guard let value = try? evaluate(expr, [variable: .approx(x)]) else { return .nan }
        return value.double
    }

    // MARK: - Core

    private func eval(_ expr: Expr, _ env: [String: MathValue], _ steps: inout [EvaluationStep]?) throws -> MathValue {
        switch expr {
        case .num(let r):
            return .exact(r)
        case .real(let d):
            return .approx(d)
        case .const(let c):
            return c == .pi ? .piMultiple(.one) : .approx(c.value)
        case .sym(let name):
            guard let value = env[name] else {
                throw MathError.unsupported(detail: "unbound variable \(name)")
            }
            return value
        case .neg(let inner):
            return try negate(try eval(inner, env, &steps))
        case .bin(let op, let a, let b):
            let left = try eval(a, env, &steps)
            let right = try eval(b, env, &steps)
            let result = try apply(op, left, right)
            steps?.append(EvaluationStep(operation: .bin(op, left.literal, right.literal), result: result))
            return result
        case .fn(let function, let args):
            var values: [MathValue] = []
            for arg in args {
                values.append(try eval(arg, env, &steps))
            }
            let result = try apply(function, values)
            if function != .deg {
                steps?.append(EvaluationStep(operation: .fn(function, values.map { $0.literal }), result: result))
            }
            return result
        }
    }

    private func negate(_ value: MathValue) throws -> MathValue {
        switch value {
        case .exact(let r): return .exact(r.negated)
        case .piMultiple(let r): return .piMultiple(r.negated)
        case .approx(let d): return .approx(-d)
        }
    }

    private func checked(_ value: Double) throws -> MathValue {
        guard value.isFinite else {
            throw value.isNaN ? MathError.domain(detail: "NaN") : MathError.overflow
        }
        return .approx(value)
    }

    func apply(_ op: BinOp, _ a: MathValue, _ b: MathValue) throws -> MathValue {
        switch op {
        case .add, .sub:
            if case .exact(let x) = a, case .exact(let y) = b {
                if let result = try? (op == .add ? x + y : x - y) { return .exact(result) }
            }
            if case .piMultiple(let x) = a, case .piMultiple(let y) = b {
                if let result = try? (op == .add ? x + y : x - y) { return .piMultiple(result) }
            }
            return try checked(op == .add ? a.double + b.double : a.double - b.double)

        case .mul:
            switch (a, b) {
            case (.exact(let x), .exact(let y)):
                if let result = try? x * y { return .exact(result) }
            case (.exact(let x), .piMultiple(let y)), (.piMultiple(let y), .exact(let x)):
                if let result = try? x * y { return .piMultiple(result) }
            default:
                break
            }
            return try checked(a.double * b.double)

        case .div:
            if b.double == 0 { throw MathError.divisionByZero }
            switch (a, b) {
            case (.exact(let x), .exact(let y)):
                if let result = try? x / y { return .exact(result) }
            case (.piMultiple(let x), .exact(let y)):
                if let result = try? x / y { return .piMultiple(result) }
            case (.piMultiple(let x), .piMultiple(let y)):
                if let result = try? x / y { return .exact(result) }
            default:
                break
            }
            return try checked(a.double / b.double)

        case .pow:
            return try power(a, b)
        }
    }

    private func power(_ base: MathValue, _ exponent: MathValue) throws -> MathValue {
        if case .exact(let b) = base, case .exact(let e) = exponent {
            if b.isZero {
                if e.isNegative { throw MathError.divisionByZero }
                if e.isZero { throw MathError.domain(detail: "0⁰") }
                return .exact(.zero)
            }
            if e.isInteger {
                if let result = try? b.power(e.num) { return .exact(result) }
            } else if let root = b.exactRoot(e.den), let result = try? root.power(e.num) {
                return .exact(result)
            }
            // Отрицательное основание и дробный показатель с нечётным знаменателем: (−8)^(1/3) = −2.
            if b.isNegative, !e.isInteger {
                guard e.den % 2 == 1 else {
                    throw MathError.domain(detail: "(−a)^(p/q)")
                }
                let magnitude = Foundation.pow(-b.doubleValue, e.doubleValue)
                return try checked(e.num % 2 == 0 ? magnitude : -magnitude)
            }
        }
        let b = base.double
        let e = exponent.double
        if b == 0, e < 0 { throw MathError.divisionByZero }
        if b < 0, e != e.rounded() {
            throw MathError.domain(detail: "(−a)^b")
        }
        return try checked(Foundation.pow(b, e))
    }

    func apply(_ function: MathFn, _ args: [MathValue]) throws -> MathValue {
        guard let first = args.first else { throw MathError.syntax(detail: function.displayName) }
        let x = first.double

        switch function {
        case .sqrt:
            if x < 0 { throw MathError.domain(detail: "√(a), a < 0") }
            if case .exact(let r) = first, let root = r.exactRoot(2) { return .exact(root) }
            return try checked(x.squareRoot())

        case .cbrt:
            if case .exact(let r) = first, let root = r.exactRoot(3) { return .exact(root) }
            return try checked(Foundation.cbrt(x))

        case .abs:
            switch first {
            case .exact(let r): return .exact(r.magnitude)
            case .piMultiple(let r): return .piMultiple(r.magnitude)
            case .approx(let d): return .approx(Swift.abs(d))
            }

        case .deg:
            if case .exact(let r) = first, let turns = try? r / Rational(180) {
                return .piMultiple(turns)
            }
            return try checked(x * Double.pi / 180)

        case .factorial:
            guard case .exact(let r) = first, r.isInteger, r.num >= 0 else {
                throw MathError.domain(detail: "n!")
            }
            guard r.num <= 20 else { throw MathError.overflow }
            var result = 1
            if r.num >= 2 {
                for k in 2...r.num { result *= k }
            }
            return .exact(Rational(result))

        case .ln:
            if x <= 0 { throw MathError.domain(detail: "ln(a), a ≤ 0") }
            if case .exact(let r) = first, r == .one { return .exact(.zero) }
            return try checked(Foundation.log(x))

        case .lg:
            if x <= 0 { throw MathError.domain(detail: "lg(a), a ≤ 0") }
            if case .exact(let r) = first, let exact = MathEvaluator.exactLogarithm(base: Rational(10), of: r) {
                return .exact(exact)
            }
            return try checked(Foundation.log10(x))

        case .log:
            guard args.count == 2 else { throw MathError.syntax(detail: "log") }
            let base = args[0].double
            let value = args[1].double
            if base <= 0 || base == 1 { throw MathError.domain(detail: "logₐ, a ≤ 0 ∨ a = 1") }
            if value <= 0 { throw MathError.domain(detail: "logₐ(b), b ≤ 0") }
            if case .exact(let b) = args[0], case .exact(let v) = args[1],
                let exact = MathEvaluator.exactLogarithm(base: b, of: v)
            {
                return .exact(exact)
            }
            return try checked(Foundation.log(value) / Foundation.log(base))

        case .sin, .cos, .tan, .cot:
            return try trigonometric(function, first)

        case .asin, .acos:
            if x < -1 || x > 1 { throw MathError.domain(detail: "\(function.displayName)(a), |a| > 1") }
            let result = function == .asin ? Foundation.asin(x) : Foundation.acos(x)
            return snapToPi(result, argument: first, tabular: MathEvaluator.sineTable)

        case .atan:
            return snapToPi(Foundation.atan(x), argument: first, tabular: MathEvaluator.tangentTable)

        case .acot:
            // arcctg(x) ∈ (0; π)
            return snapToPi(Double.pi / 2 - Foundation.atan(x), argument: first, tabular: MathEvaluator.tangentTable)
        }
    }

    /// Тригонометрия. По теореме Нивена рациональные значения синуса и косинуса
    /// в рациональных долях π — только 0, ±1/2, ±1, поэтому «привязка» к ним точна.
    private func trigonometric(_ function: MathFn, _ argument: MathValue) throws -> MathValue {
        let x = argument.double
        var piFraction: Rational?
        if case .piMultiple(let r) = argument { piFraction = r }
        if case .exact(let r) = argument, r.isZero { piFraction = .zero }

        if let fraction = piFraction {
            // Приводим угол к [0; 2π) в двенадцатых долях π — этого достаточно для табличных углов.
            if let twelfths = try? fraction * Rational(12), twelfths.isInteger {
                let k = ((twelfths.num % 24) + 24) % 24
                let cosIsZero = k == 6 || k == 18
                let sinIsZero = k == 0 || k == 12
                if function == .tan, cosIsZero { throw MathError.domain(detail: "tg(π/2 + πn)") }
                if function == .cot, sinIsZero { throw MathError.domain(detail: "ctg(πn)") }
            }
        }

        let raw: Double
        switch function {
        case .sin: raw = Foundation.sin(x)
        case .cos: raw = Foundation.cos(x)
        case .tan: raw = Foundation.tan(x)
        default:
            let tangent = Foundation.tan(x)
            if tangent == 0 { throw MathError.domain(detail: "ctg(πn)") }
            raw = 1 / tangent
        }

        if piFraction != nil {
            let candidates = (function == .sin || function == .cos) ? MathEvaluator.sineTable : MathEvaluator.tangentTable
            for candidate in candidates where Swift.abs(raw - candidate.doubleValue) < 1e-12 {
                return .exact(candidate)
            }
        }
        return try checked(raw)
    }

    /// Единственные рациональные значения sin/cos (и tg/ctg) в рациональных долях π.
    private static let sineTable: [Rational] = [
        .zero, .one, .minusOne, (try? Rational(1, 2)) ?? .zero, (try? Rational(-1, 2)) ?? .zero,
    ]
    private static let tangentTable: [Rational] = [.zero, .one, .minusOne]

    /// Табличные значения обратных тригонометрических функций: `arcsin(1/2) = π/6`.
    private func snapToPi(_ radians: Double, argument: MathValue, tabular: [Rational]) -> MathValue {
        guard case .exact(let value) = argument, tabular.contains(value) else { return .approx(radians) }
        let twelfths = radians / Double.pi * 12
        let rounded = twelfths.rounded()
        if Swift.abs(twelfths - rounded) < 1e-10, let fraction = try? Rational(Int(rounded), 12) {
            return fraction.isZero ? .exact(.zero) : .piMultiple(fraction)
        }
        return .approx(radians)
    }

    /// `log_base(value)`, если ответ — рациональное число с небольшим знаменателем.
    static func exactLogarithm(base: Rational, of value: Rational) -> Rational? {
        guard base.isPositive, base != .one, value.isPositive else { return nil }
        if value == .one { return .zero }
        for denominator in 1...4 {
            for numerator in -40...40 where numerator != 0 {
                guard Rational.gcd(numerator, denominator) == 1 else { continue }
                // base^(numerator/denominator) == value  ⇔  base^numerator == value^denominator
                guard let left = try? base.power(numerator), let right = try? value.power(denominator) else { continue }
                if left == right { return try? Rational(numerator, denominator) }
            }
        }
        return nil
    }
}
