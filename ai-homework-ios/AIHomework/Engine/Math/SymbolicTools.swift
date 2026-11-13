import Foundation

extension Polynomial {
    /// Многочлен в виде синтаксического дерева — чтобы печатать его общим форматтером.
    var asExpr: Expr {
        var result: Expr?
        for term in orderedTerms {
            let magnitude = term.coefficient.magnitude
            var product: Expr?
            for name in term.monomial.variables {
                let power = term.monomial.degree(in: name)
                let factor: Expr = power == 1 ? .sym(name) : .bin(.pow, .sym(name), .int(power))
                product = product.map { .bin(.mul, $0, factor) } ?? factor
            }
            let body: Expr
            if let product {
                body = magnitude == .one ? product : .bin(.mul, .num(magnitude), product)
            } else {
                body = .num(magnitude)
            }
            if let current = result {
                result = term.coefficient.isNegative ? .bin(.sub, current, body) : .bin(.add, current, body)
            } else {
                result = term.coefficient.isNegative ? .neg(body) : body
            }
        }
        return result ?? .int(0)
    }
}

/// Базовые алгебраические упрощения дерева выражения.
enum SymbolicSimplifier {
    static func simplify(_ expr: Expr) -> Expr {
        // Всё, что является многочленом, приводим к каноническому виду.
        if expr.hasOperation, let polynomial = try? Algebra.polynomial(expr) {
            return polynomial.asExpr
        }
        switch expr {
        case .num, .real, .sym, .const:
            return expr
        case .neg(let inner):
            return negate(simplify(inner))
        case .fn(let function, let args):
            let simplified = args.map { simplify($0) }
            // Точное значение функции от чисел: √16 → 4.
            if simplified.allSatisfy({ $0.isConstant }),
                let value = try? MathEvaluator().evaluate(.fn(function, simplified)), let exact = value.rational
            {
                return .num(exact)
            }
            return .fn(function, simplified)
        case .bin(let op, let a, let b):
            return combine(op, simplify(a), simplify(b))
        }
    }

    private static func negate(_ expr: Expr) -> Expr {
        switch expr {
        case .num(let r): return .num(r.negated)
        case .neg(let inner): return inner
        case .bin(.sub, let a, let b): return .bin(.sub, b, a)
        default: return .neg(expr)
        }
    }

    private static func number(_ expr: Expr) -> Rational? {
        if case .num(let r) = expr { return r }
        return nil
    }

    private static func combine(_ op: BinOp, _ a: Expr, _ b: Expr) -> Expr {
        let x = number(a)
        let y = number(b)

        switch op {
        case .add:
            if let x, let y, let sum = try? x + y { return .num(sum) }
            if x?.isZero == true { return b }
            if y?.isZero == true { return a }
            if case .neg(let inner) = b { return combine(.sub, a, inner) }
            if case .neg(let inner) = a { return combine(.sub, b, inner) }
            if let y, y.isNegative { return .bin(.sub, a, .num(y.negated)) }
            return .bin(.add, a, b)

        case .sub:
            if let x, let y, let difference = try? x - y { return .num(difference) }
            if y?.isZero == true { return a }
            if x?.isZero == true { return negate(b) }
            if a == b { return .int(0) }
            if case .neg(let inner) = b { return combine(.add, a, inner) }
            if let y, y.isNegative { return .bin(.add, a, .num(y.negated)) }
            return .bin(.sub, a, b)

        case .mul:
            if let x, let y, let product = try? x * y { return .num(product) }
            if x?.isZero == true || y?.isZero == true { return .int(0) }
            if x == .one { return b }
            if y == .one { return a }
            if x == .minusOne { return negate(b) }
            if y == .minusOne { return negate(a) }
            if case .neg(let inner) = a { return negate(combine(.mul, inner, b)) }
            if case .neg(let inner) = b { return negate(combine(.mul, a, inner)) }
            // Числовой множитель — вперёд; вложенные числовые множители перемножаем.
            if y != nil, x == nil { return combine(.mul, b, a) }
            if let x, case .bin(.mul, let inner, let rest) = b, let innerNumber = number(inner), let product = try? x * innerNumber {
                return combine(.mul, .num(product), rest)
            }
            if let x, case .bin(.div, let top, let bottom) = b, let topNumber = number(top), let product = try? x * topNumber {
                return combine(.div, .num(product), bottom)
            }
            if let x, x.isNegative { return negate(.bin(.mul, .num(x.negated), b)) }
            return .bin(.mul, a, b)

        case .div:
            if let x, let y, !y.isZero, let quotient = try? x / y { return .num(quotient) }
            if x?.isZero == true, y?.isZero != true { return .int(0) }
            if y == .one { return a }
            if y == .minusOne { return negate(a) }
            if a == b, y?.isZero != true { return .int(1) }
            if case .neg(let inner) = a { return negate(combine(.div, inner, b)) }
            if case .neg(let inner) = b { return negate(combine(.div, a, inner)) }
            return .bin(.div, a, b)

        case .pow:
            if y?.isZero == true, x?.isZero != true { return .int(1) }
            if y == .one { return a }
            if x == .one { return .int(1) }
            if let x, let y, y.isInteger, abs(y.num) <= 64, !(x.isZero && y.isNegative), let power = try? x.power(y.num) {
                return .num(power)
            }
            // (u^m)^n → u^(m·n) для целых показателей
            if case .bin(.pow, let base, let inner) = a, let m = number(inner), let n = y, m.isInteger, n.isInteger,
                let product = try? m * n
            {
                return combine(.pow, base, .num(product))
            }
            return .bin(.pow, a, b)
        }
    }
}

/// Символьное дифференцирование.
struct Differentiator {
    /// Правила, которые понадобились, — для объяснения.
    enum Rule: String, Hashable, CaseIterable, Sendable {
        case constant, power, sum, constantFactor, product, quotient, chain, exponential, logarithm, trigonometric, root
    }

    private(set) var rules: Set<Rule> = []

    mutating func derivative(of expr: Expr, by x: String) throws -> Expr {
        SymbolicSimplifier.simplify(try differentiate(expr, x))
    }

    private func dependsOn(_ expr: Expr, _ x: String) -> Bool {
        expr.variables.contains(x)
    }

    private mutating func differentiate(_ expr: Expr, _ x: String) throws -> Expr {
        guard dependsOn(expr, x) else {
            rules.insert(.constant)
            return .int(0)
        }
        switch expr {
        case .num, .real, .const:
            return .int(0)
        case .sym(let name):
            if name == x { rules.insert(.power) }
            return name == x ? .int(1) : .int(0)
        case .neg(let inner):
            return .neg(try differentiate(inner, x))

        case .bin(.add, let a, let b):
            rules.insert(.sum)
            return .bin(.add, try differentiate(a, x), try differentiate(b, x))
        case .bin(.sub, let a, let b):
            rules.insert(.sum)
            return .bin(.sub, try differentiate(a, x), try differentiate(b, x))

        case .bin(.mul, let a, let b):
            if !dependsOn(a, x) {
                rules.insert(.constantFactor)
                return .bin(.mul, a, try differentiate(b, x))
            }
            if !dependsOn(b, x) {
                rules.insert(.constantFactor)
                return .bin(.mul, b, try differentiate(a, x))
            }
            rules.insert(.product)
            return .bin(.add, .bin(.mul, try differentiate(a, x), b), .bin(.mul, a, try differentiate(b, x)))

        case .bin(.div, let a, let b):
            if !dependsOn(b, x) {
                rules.insert(.constantFactor)
                return .bin(.div, try differentiate(a, x), b)
            }
            rules.insert(.quotient)
            let numerator = Expr.bin(.sub, .bin(.mul, try differentiate(a, x), b), .bin(.mul, a, try differentiate(b, x)))
            return .bin(.div, numerator, .bin(.pow, b, .int(2)))

        case .bin(.pow, let base, let exponent):
            let baseDepends = dependsOn(base, x)
            let exponentDepends = dependsOn(exponent, x)
            if baseDepends, !exponentDepends {
                rules.insert(.power)
                let reduced: Expr
                if case .num(let n) = exponent, let lowered = try? n - .one {
                    reduced = .num(lowered)
                } else {
                    reduced = .bin(.sub, exponent, .int(1))
                }
                let outer = Expr.bin(.mul, exponent, .bin(.pow, base, reduced))
                return try chain(outer, inner: base, x)
            }
            if !baseDepends, exponentDepends {
                rules.insert(.exponential)
                let outer: Expr = base == .const(.e) ? expr : .bin(.mul, expr, .fn(.ln, [base]))
                return try chain(outer, inner: exponent, x)
            }
            // u^v = u^v·(v′·ln u + v·u′/u)
            rules.insert(.exponential)
            rules.insert(.product)
            let du = try differentiate(base, x)
            let dv = try differentiate(exponent, x)
            let inner = Expr.bin(.add, .bin(.mul, dv, .fn(.ln, [base])), .bin(.div, .bin(.mul, exponent, du), base))
            return .bin(.mul, expr, inner)

        case .fn(let function, let args):
            guard let u = args.last else { throw MathError.syntax(detail: function.displayName) }
            let outer: Expr
            switch function {
            case .sqrt:
                rules.insert(.root)
                outer = .bin(.div, .int(1), .bin(.mul, .int(2), .fn(.sqrt, [u])))
            case .cbrt:
                rules.insert(.root)
                outer = .bin(.div, .int(1), .bin(.mul, .int(3), .bin(.pow, .fn(.cbrt, [u]), .int(2))))
            case .sin:
                rules.insert(.trigonometric)
                outer = .fn(.cos, [u])
            case .cos:
                rules.insert(.trigonometric)
                outer = .neg(.fn(.sin, [u]))
            case .tan:
                rules.insert(.trigonometric)
                outer = .bin(.div, .int(1), .bin(.pow, .fn(.cos, [u]), .int(2)))
            case .cot:
                rules.insert(.trigonometric)
                outer = .neg(.bin(.div, .int(1), .bin(.pow, .fn(.sin, [u]), .int(2))))
            case .asin:
                rules.insert(.trigonometric)
                outer = .bin(.div, .int(1), .fn(.sqrt, [.bin(.sub, .int(1), .bin(.pow, u, .int(2)))]))
            case .acos:
                rules.insert(.trigonometric)
                outer = .neg(.bin(.div, .int(1), .fn(.sqrt, [.bin(.sub, .int(1), .bin(.pow, u, .int(2)))])))
            case .atan:
                rules.insert(.trigonometric)
                outer = .bin(.div, .int(1), .bin(.add, .int(1), .bin(.pow, u, .int(2))))
            case .acot:
                rules.insert(.trigonometric)
                outer = .neg(.bin(.div, .int(1), .bin(.add, .int(1), .bin(.pow, u, .int(2)))))
            case .ln:
                rules.insert(.logarithm)
                outer = .bin(.div, .int(1), u)
            case .lg:
                rules.insert(.logarithm)
                outer = .bin(.div, .int(1), .bin(.mul, u, .fn(.ln, [.int(10)])))
            case .log:
                guard args.count == 2, !dependsOn(args[0], x) else {
                    throw MathError.unsupported(detail: "log")
                }
                rules.insert(.logarithm)
                outer = .bin(.div, .int(1), .bin(.mul, u, .fn(.ln, [args[0]])))
            case .abs, .deg, .factorial:
                throw MathError.unsupported(detail: function.displayName)
            }
            return try chain(outer, inner: u, x)
        }
    }

    /// Правило сложной функции: `f(u)′ = f′(u)·u′`.
    private mutating func chain(_ outer: Expr, inner: Expr, _ x: String) throws -> Expr {
        if inner == .sym(x) { return outer }
        rules.insert(.chain)
        return .bin(.mul, outer, try differentiate(inner, x))
    }

    static func ruleText(_ rule: Rule, _ l: L10n) -> String {
        switch rule {
        case .constant: return l("производная постоянной равна нулю: C′ = 0", "the derivative of a constant is zero: C′ = 0")
        case .power: return l("степенная функция: (xⁿ)′ = n·xⁿ⁻¹", "power rule: (xⁿ)′ = n·xⁿ⁻¹")
        case .sum: return l("производная суммы равна сумме производных: (u ± v)′ = u′ ± v′", "sum rule: (u ± v)′ = u′ ± v′")
        case .constantFactor: return l("постоянный множитель выносится: (C·u)′ = C·u′", "constant factor rule: (C·u)′ = C·u′")
        case .product: return l("производная произведения: (u·v)′ = u′v + uv′", "product rule: (u·v)′ = u′v + uv′")
        case .quotient: return l("производная частного: (u/v)′ = (u′v − uv′)/v²", "quotient rule: (u/v)′ = (u′v − uv′)/v²")
        case .chain: return l("сложная функция: f(u)′ = f′(u)·u′", "chain rule: f(u)′ = f′(u)·u′")
        case .exponential: return l("показательная функция: (aˣ)′ = aˣ·ln a, (eˣ)′ = eˣ", "exponential: (aˣ)′ = aˣ·ln a, (eˣ)′ = eˣ")
        case .logarithm: return l("логарифм: (ln x)′ = 1/x", "logarithm: (ln x)′ = 1/x")
        case .trigonometric:
            return l(
                "тригонометрия: (sin x)′ = cos x, (cos x)′ = −sin x, (tg x)′ = 1/cos²x",
                "trigonometry: (sin x)′ = cos x, (cos x)′ = −sin x, (tan x)′ = 1/cos²x")
        case .root: return l("корень: (√x)′ = 1/(2√x)", "root: (√x)′ = 1/(2√x)")
        }
    }
}

/// Разложение многочленов на множители над рациональными числами.
struct Factorizer {
    let fmt: MathFormatter

    struct Result {
        var text: String
        /// Удалось ли разложить хоть на что-то нетривиальное.
        var changed: Bool
        var method: [String]
    }

    func factor(_ polynomial: Polynomial, _ l: L10n) throws -> Result {
        guard !polynomial.isZero else { return Result(text: "0", changed: false, method: []) }
        let variables = polynomial.variables
        if variables.count == 1, let x = variables.first, let coefficients = polynomial.coefficients(in: x) {
            return try factorUnivariate(coefficients, variable: x, l)
        }
        return try factorMultivariate(polynomial, l)
    }

    private func factorUnivariate(_ coefficients: [Rational], variable x: String, _ l: L10n) throws -> Result {
        let extraction = try UnivariatePolynomial.extractRationalRoots(coefficients)
        // P(x) = Π(x − rᵢ)·R(x). Переходим к целым коэффициентам: (x − p/q) = (qx − p)/q.
        var constant = Rational.one
        var factorCounts: [(text: String, count: Int)] = []
        for root in Set(extraction.roots).sorted() {
            let count = extraction.roots.filter { $0 == root }.count
            let linear = Polynomial(coefficients: [Rational(-root.num), Rational(root.den)], variable: x)
            constant = try constant / (try Rational(root.den).power(count))
            let text = root.isZero ? x : "(\(fmt.polynomial(linear)))"
            factorCounts.append((text, count))
        }
        let remainingForm = try UnivariatePolynomial.integerForm(extraction.remaining)
        var remainingIntegers = remainingForm.coefficients
        var remainingScale = try remainingForm.multiplier.reciprocal()
        if let lead = remainingIntegers.last, lead < 0 {
            remainingIntegers = remainingIntegers.map { -$0 }
            remainingScale = remainingScale.negated
        }
        constant = try constant * remainingScale
        let remaining = Polynomial(coefficients: remainingIntegers.map { Rational($0) }, variable: x)

        var text = ""
        if constant == .minusOne {
            text = MathFormatter.minus
        } else if constant != .one {
            text = fmt.rational(constant)
            if text.contains("/") { text = "(\(text))" }
        }
        for factor in factorCounts {
            text += factor.count > 1 ? factor.text + fmt.superscript(factor.count) : factor.text
        }
        let remainingDegree = remaining.degree(in: x)
        if remainingDegree >= 1 {
            text += "(\(fmt.polynomial(remaining)))"
        } else if text.isEmpty || text == MathFormatter.minus {
            text += "1"
        }

        let pieces = factorCounts.reduce(0) { $0 + $1.count } + (remainingDegree >= 1 ? 1 : 0)
        let changed = pieces >= 2 || (constant != .one && pieces >= 1 && constant != .minusOne)
        var method: [String] = []
        if !extraction.roots.isEmpty {
            method.append(
                l(
                    "Находим рациональные корни многочлена: \(Set(extraction.roots).sorted().map { fmt.rational($0) }.joined(separator: "; ")). Каждому корню r соответствует множитель (\(x) − r).",
                    "Find the rational roots of the polynomial: \(Set(extraction.roots).sorted().map { fmt.rational($0) }.joined(separator: "; ")). Each root r gives a factor (\(x) − r)."
                ))
        }
        if remainingDegree >= 2 {
            method.append(
                l(
                    "Множитель \(fmt.polynomial(remaining)) не имеет рациональных корней, поэтому дальше не раскладывается на множители с рациональными коэффициентами первой степени.",
                    "The factor \(fmt.polynomial(remaining)) has no rational roots, so it has no further linear factors with rational coefficients."
                ))
        }
        return Result(text: text, changed: changed, method: method)
    }

    private func factorMultivariate(_ polynomial: Polynomial, _ l: L10n) throws -> Result {
        var method: [String] = []
        // Общий множитель: НОД коэффициентов и наименьшие степени переменных.
        let denominator = try polynomial.commonDenominator()
        let integerPolynomial = try polynomial.scaled(by: Rational(denominator))
        var content = integerPolynomial.numeratorGCD()
        if let first = integerPolynomial.orderedTerms.first, first.coefficient.isNegative { content = -content }
        var commonPowers: [String: Int] = [:]
        for name in integerPolynomial.variables {
            commonPowers[name] = integerPolynomial.terms.keys.map { $0.degree(in: name) }.min() ?? 0
        }
        let commonMonomial = Monomial(powers: commonPowers)

        var reducedTerms: [Monomial: Rational] = [:]
        for (monomial, coefficient) in integerPolynomial.terms {
            var powers = monomial.powers
            for (name, power) in commonPowers where power > 0 {
                powers[name] = (powers[name] ?? 0) - power
            }
            reducedTerms[Monomial(powers: powers)] = try coefficient / Rational(content)
        }
        let reduced = Polynomial(terms: reducedTerms)
        let outer = try Rational(content, denominator)

        var prefix = ""
        if outer == .minusOne {
            prefix = MathFormatter.minus
        } else if outer != .one {
            prefix = fmt.rational(outer)
            if prefix.contains("/") { prefix = "(\(prefix))" }
        }
        prefix += fmt.monomial(commonMonomial)
        if !prefix.isEmpty, prefix != MathFormatter.minus || !commonMonomial.isConstant {
            if outer != .one || !commonMonomial.isConstant {
                method.append(l("Выносим общий множитель за скобки.", "Take the common factor out of the brackets."))
            }
        }

        var inner: String?
        if let special = try specialProduct(reduced, l, &method) {
            inner = special
        }
        let changedByCommon = outer != .one || !commonMonomial.isConstant
        if let inner {
            return Result(text: prefix + inner, changed: true, method: method)
        }
        let body = reduced.terms.count > 1 ? "(\(fmt.polynomial(reduced)))" : fmt.polynomial(reduced)
        if !changedByCommon {
            return Result(text: fmt.polynomial(polynomial), changed: false, method: [])
        }
        let text = reduced == .one ? (prefix.isEmpty ? "1" : prefix) : prefix + body
        return Result(text: text, changed: true, method: method)
    }

    /// Точный квадратный корень одночлена с коэффициентом, если он существует.
    private func squareRoot(of monomial: Monomial, coefficient: Rational) -> Polynomial? {
        guard coefficient.isPositive, let root = coefficient.exactRoot(2) else { return nil }
        var powers: [String: Int] = [:]
        for (name, power) in monomial.powers {
            guard power % 2 == 0 else { return nil }
            powers[name] = power / 2
        }
        return Polynomial(terms: [Monomial(powers: powers): root])
    }

    /// Формулы сокращённого умножения: разность квадратов и квадрат суммы/разности.
    private func specialProduct(_ polynomial: Polynomial, _ l: L10n, _ method: inout [String]) throws -> String? {
        let terms = polynomial.orderedTerms
        if terms.count == 2 {
            // a² − b²
            let positive = terms.filter { $0.coefficient.isPositive }
            let negative = terms.filter { $0.coefficient.isNegative }
            guard positive.count == 1, negative.count == 1,
                let a = squareRoot(of: positive[0].monomial, coefficient: positive[0].coefficient),
                let b = squareRoot(of: negative[0].monomial, coefficient: negative[0].coefficient.negated)
            else { return nil }
            method.append(l("Применяем формулу разности квадратов: a² − b² = (a − b)(a + b).", "Apply the difference of squares: a² − b² = (a − b)(a + b)."))
            return "(\(fmt.polynomial(try a - b)))(\(fmt.polynomial(try a + b)))"
        }
        if terms.count == 3 {
            // a² ± 2ab + b²
            for i in 0..<3 {
                for j in (i + 1)..<3 {
                    let k = 3 - i - j
                    guard let a = squareRoot(of: terms[i].monomial, coefficient: terms[i].coefficient),
                        let b = squareRoot(of: terms[j].monomial, coefficient: terms[j].coefficient)
                    else { continue }
                    let cross = try (try a * b).scaled(by: .two)
                    let middle = Polynomial(terms: [terms[k].monomial: terms[k].coefficient])
                    if middle == cross {
                        method.append(l("Применяем формулу квадрата суммы: a² + 2ab + b² = (a + b)².", "Apply the square of a sum: a² + 2ab + b² = (a + b)²."))
                        return "(\(fmt.polynomial(try a + b)))²"
                    }
                    if middle == cross.negated {
                        method.append(l("Применяем формулу квадрата разности: a² − 2ab + b² = (a − b)².", "Apply the square of a difference: a² − 2ab + b² = (a − b)²."))
                        return "(\(fmt.polynomial(try a - b)))²"
                    }
                }
            }
        }
        return nil
    }
}
