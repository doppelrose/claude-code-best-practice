import Foundation

/// Превращает числа, выражения и многочлены в аккуратную «учебниковую» запись:
/// `2x² − 5x + 6`, `√(x + 1)`, `3,5`, `(3 + √5)/2`.
///
/// Запись остаётся разбираемой парсером — это используется при проверке и отрисовке формул.
struct MathFormatter: Sendable {
    let lang: AppLanguage
    /// Показывать конечные дроби десятичными (`0,5` вместо `1/2`) — если так было в условии.
    var preferDecimals = false

    init(lang: AppLanguage, preferDecimals: Bool = false) {
        self.lang = lang
        self.preferDecimals = preferDecimals
    }

    static let minus = "−"

    // MARK: - Numbers

    private static let superscriptDigits: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻",
    ]
    private static let subscriptDigits: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
    ]

    func superscript(_ value: Int) -> String {
        String(String(value).map { MathFormatter.superscriptDigits[$0] ?? $0 })
    }

    func `subscript`(_ value: Int) -> String {
        String(String(value).map { MathFormatter.subscriptDigits[$0] ?? $0 })
    }

    func integer(_ value: Int) -> String {
        value < 0 ? MathFormatter.minus + String(value.magnitude) : String(value)
    }

    /// Точная десятичная запись, если она конечна и не слишком длинна.
    func exactDecimal(_ r: Rational, maxFractionDigits: Int = 8) -> String? {
        guard r.hasTerminatingDecimal else { return nil }
        var scale = 1
        var digits = 0
        while scale % r.den != 0 {
            let (next, overflow) = scale.multipliedReportingOverflow(by: 10)
            if overflow { return nil }
            scale = next
            digits += 1
            if digits > maxFractionDigits { return nil }
        }
        let (scaled, overflow) = r.num.multipliedReportingOverflow(by: scale / r.den)
        if overflow { return nil }
        var text = String(scaled.magnitude)
        if digits > 0 {
            while text.count <= digits { text = "0" + text }
            let split = text.index(text.endIndex, offsetBy: -digits)
            text = String(text[..<split]) + lang.decimalSeparator + String(text[split...])
        }
        return (scaled < 0 ? MathFormatter.minus : "") + text
    }

    /// Рациональное число: целое, десятичная или обыкновенная дробь.
    func rational(_ r: Rational) -> String {
        if r.isInteger { return integer(r.num) }
        if preferDecimals, let decimal = exactDecimal(r) { return decimal }
        return integer(r.num) + "/" + String(r.den)
    }

    /// Обыкновенная дробь независимо от `preferDecimals`.
    func fraction(_ r: Rational) -> String {
        r.isInteger ? integer(r.num) : integer(r.num) + "/" + String(r.den)
    }

    /// Приближённое число с заданным количеством значащих цифр.
    func approx(_ value: Double, significant: Int = 6) -> String {
        guard value.isFinite else {
            if value.isNaN { return "—" }
            return value > 0 ? "∞" : MathFormatter.minus + "∞"
        }
        if value == 0 { return "0" }
        let magnitude = abs(value)
        if magnitude >= 1e12 || magnitude < 1e-5 {
            let exponent = Int(floor(log10(magnitude)))
            let mantissa = value / Foundation.pow(10, Double(exponent))
            let mantissaText = fixed(mantissa, decimals: max(significant - 1, 0))
            if mantissaText == "1" { return "10" + superscript(exponent) }
            if mantissaText == MathFormatter.minus + "1" { return MathFormatter.minus + "10" + superscript(exponent) }
            return mantissaText + "·10" + superscript(exponent)
        }
        let leading = Int(floor(log10(magnitude)))
        let decimals = min(max(significant - 1 - leading, 0), 12)
        return fixed(value, decimals: decimals)
    }

    private func fixed(_ value: Double, decimals: Int) -> String {
        var text = String(format: "%.\(decimals)f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        if text == "-0" { text = "0" }
        text = text.replacingOccurrences(of: ".", with: lang.decimalSeparator)
        if text.hasPrefix("-") { text = MathFormatter.minus + String(text.dropFirst()) }
        return text
    }

    func value(_ value: MathValue) -> String {
        switch value {
        case .exact(let r): return rational(r)
        case .piMultiple(let r): return piMultiple(r)
        case .approx(let d): return approx(d)
        }
    }

    /// Число вида `r·π`: `π/6`, `5π/6`, `2π`.
    func piMultiple(_ r: Rational) -> String {
        if r.isZero { return "0" }
        let sign = r.isNegative ? MathFormatter.minus : ""
        let numerator = abs(r.num) == 1 ? "π" : "\(abs(r.num))π"
        return sign + (r.den == 1 ? numerator : "\(numerator)/\(r.den)")
    }

    /// Значение вместе с десятичным приближением: `7/2 = 3,5`, `1/3 ≈ 0,333333`, `π/6 ≈ 0,523599`.
    func valueWithApproximation(_ value: MathValue) -> String {
        switch value {
        case .exact(let r):
            return rationalWithApproximation(r)
        case .piMultiple(let r):
            return r.isZero ? "0" : piMultiple(r) + " ≈ " + approx(value.double)
        case .approx(let d):
            return "≈ " + approx(d)
        }
    }

    func rationalWithApproximation(_ r: Rational) -> String {
        if r.isInteger { return integer(r.num) }
        let fractionText = fraction(r)
        if let decimal = exactDecimal(r, maxFractionDigits: 6) {
            return preferDecimals ? decimal : fractionText + " = " + decimal
        }
        return fractionText + " ≈ " + approx(r.doubleValue)
    }

    // MARK: - Expressions

    private enum Precedence: Int, Comparable {
        case sum = 0
        case negation = 1
        case product = 2
        case power = 3
        case atom = 4

        static func < (lhs: Precedence, rhs: Precedence) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private struct Rendered {
        var text: String
        var precedence: Precedence

        func wrapped(min: Precedence) -> String {
            precedence < min ? "(\(text))" : text
        }
    }

    func expr(_ expression: Expr) -> String {
        render(expression).text
    }

    func statement(_ statement: MathStatement) -> String {
        var text = expr(statement.sides[0])
        for (index, relation) in statement.relations.enumerated() {
            text += " \(relation.rawValue) " + expr(statement.sides[index + 1])
        }
        return text
    }

    private func render(_ expression: Expr) -> Rendered {
        switch expression {
        case .num(let r):
            let text = rational(r)
            if r.isNegative { return Rendered(text: text, precedence: .negation) }
            return Rendered(text: text, precedence: text.contains("/") ? .product : .atom)

        case .real(let d):
            return Rendered(text: approx(d, significant: 10), precedence: d < 0 ? .negation : .atom)

        case .sym(let name):
            return Rendered(text: name, precedence: .atom)

        case .const(let constant):
            return Rendered(text: constant.symbol, precedence: .atom)

        case .neg(let inner):
            return Rendered(text: MathFormatter.minus + render(inner).wrapped(min: .product), precedence: .negation)

        case .bin(.add, let a, let b):
            let left = render(a).text
            if case .neg(let inner) = b {
                return Rendered(text: left + " − " + render(inner).wrapped(min: .product), precedence: .sum)
            }
            if case .num(let r) = b, r.isNegative {
                return Rendered(text: left + " − " + rational(r.negated), precedence: .sum)
            }
            return Rendered(text: left + " + " + render(b).text, precedence: .sum)

        case .bin(.sub, let a, let b):
            return Rendered(text: render(a).text + " − " + render(b).wrapped(min: .product), precedence: .sum)

        case .bin(.mul, let a, let b):
            // (−2)·x → −2x
            if case .num(let r) = a, r.isNegative, r != .minusOne {
                let positive = render(.bin(.mul, .num(r.negated), b))
                return Rendered(text: MathFormatter.minus + positive.text, precedence: .negation)
            }
            if case .num(let r) = a, r == .minusOne {
                return Rendered(text: MathFormatter.minus + render(b).wrapped(min: .product), precedence: .negation)
            }
            let left = render(a).wrapped(min: .product)
            let right = render(b).wrapped(min: .product)
            let separator = needsMultiplicationSign(left: a, leftText: left, right: b, rightText: right) ? "·" : ""
            return Rendered(text: left + separator + right, precedence: .product)

        case .bin(.div, let a, let b):
            let left = render(a).wrapped(min: .product)
            let right = render(b).wrapped(min: .power)
            return Rendered(text: left + "/" + right, precedence: .product)

        case .bin(.pow, let base, let exponent):
            let baseText = render(base).wrapped(min: .atom)
            if case .num(let r) = exponent, r.isInteger, r.num >= 0, r.num < 100 {
                return Rendered(text: baseText + superscript(r.num), precedence: .power)
            }
            return Rendered(text: baseText + "^" + render(exponent).wrapped(min: .atom), precedence: .power)

        case .fn(let function, let args):
            return renderFunction(function, args)
        }
    }

    private func renderFunction(_ function: MathFn, _ args: [Expr]) -> Rendered {
        guard let first = args.first else { return Rendered(text: function.displayName, precedence: .atom) }
        switch function {
        case .sqrt, .cbrt:
            let sign = function == .sqrt ? "√" : "∛"
            let inner = render(first)
            let simple = inner.precedence == .atom && !inner.text.contains("(")
            return Rendered(text: sign + (simple ? inner.text : "(\(inner.text))"), precedence: .power)
        case .abs:
            return Rendered(text: "|" + render(first).text + "|", precedence: .atom)
        case .deg:
            return Rendered(text: render(first).wrapped(min: .atom) + "°", precedence: .power)
        case .factorial:
            return Rendered(text: render(first).wrapped(min: .atom) + "!", precedence: .power)
        case .log:
            guard args.count == 2 else { return Rendered(text: "log(" + render(first).text + ")", precedence: .atom) }
            if case .num(let base) = args[0], base.isInteger, base.num > 0 {
                return Rendered(text: "log" + `subscript`(base.num) + "(" + render(args[1]).text + ")", precedence: .atom)
            }
            return Rendered(text: "log(" + render(args[0]).text + "; " + render(args[1]).text + ")", precedence: .atom)
        default:
            return Rendered(text: function.displayName + "(" + render(first).text + ")", precedence: .atom)
        }
    }

    /// Последний множитель произведения — по нему решаем, нужен ли знак умножения.
    private func lastFactor(_ expression: Expr) -> Expr {
        if case .bin(.mul, _, let b) = expression { return lastFactor(b) }
        return expression
    }

    private func needsMultiplicationSign(left: Expr, leftText: String, right: Expr, rightText: String) -> Bool {
        guard let first = rightText.first, let last = leftText.last else { return true }
        // Справа число или минус: 2·3, x·2
        if first.isNumber || first == "−" || first == "-" { return true }

        let tail = lastFactor(left)
        // Слева дробь или функция: 1/2·x, sin(x)·x
        switch tail {
        case .bin(.div, _, _): return true
        case .num(let r) where !r.isInteger && leftText.contains("/"): return true
        case .fn(let f, _) where f != .abs: return true
        default: break
        }

        // Справа именованная функция: «2sin(x)» допустимо, «x·sin(x)» читается лучше.
        if case .fn(let f, _) = right, f != .sqrt, f != .cbrt, f != .abs {
            if case .num = tail { return false }
            return true
        }
        _ = last
        return false
    }

    // MARK: - Polynomials

    func monomial(_ monomial: Monomial) -> String {
        monomial.variables.map { name in
            let power = monomial.degree(in: name)
            return power == 1 ? name : name + superscript(power)
        }.joined()
    }

    func polynomial(_ polynomial: Polynomial) -> String {
        let terms = polynomial.orderedTerms
        guard !terms.isEmpty else { return "0" }
        var text = ""
        for (index, term) in terms.enumerated() {
            let coefficient = term.coefficient
            let magnitude = coefficient.magnitude
            let variablePart = monomial(term.monomial)

            var body: String
            if variablePart.isEmpty {
                body = rational(magnitude)
            } else if magnitude == .one {
                body = variablePart
            } else {
                let coefficientText = rational(magnitude)
                body = coefficientText.contains("/") ? coefficientText + "·" + variablePart : coefficientText + variablePart
            }

            if index == 0 {
                text = (coefficient.isNegative ? MathFormatter.minus : "") + body
            } else {
                text += (coefficient.isNegative ? " − " : " + ") + body
            }
        }
        return text
    }

    /// Многочлен в скобках, если в нём больше одного члена, — для записи произведений.
    func polynomialFactor(_ polynomial: Polynomial) -> String {
        let text = self.polynomial(polynomial)
        return polynomial.terms.count > 1 ? "(\(text))" : text
    }
}
