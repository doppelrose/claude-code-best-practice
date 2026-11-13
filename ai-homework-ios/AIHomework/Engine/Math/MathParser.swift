import Foundation

/// Рекурсивный спуск по грамматике школьной математической записи.
///
/// ```
/// expr    := term (('+' | '-') term)*
/// term    := unary (('*' | '/') unary | implicitFactor)*
/// unary   := ('-' | '+') unary | power
/// power   := postfix ('^' unary)?
/// postfix := primary ('!' | '%' | '°')*
/// primary := number | constant | variable | function | '(' expr ')' | '|' expr '|'
/// ```
struct MathParser {
    private let tokens: [MathToken]
    private var pos = 0
    private var absDepth = 0

    /// Результат разбора вместе с пометками об эвристиках.
    struct Output: Sendable {
        var expr: Expr
        var assumedPowers: Bool
    }

    private init(tokens: [MathToken]) {
        self.tokens = tokens
    }

    static func parse(_ text: String) throws -> Expr {
        try parseDetailed(text).expr
    }

    static func parseDetailed(_ text: String) throws -> Output {
        var lexer = MathLexer(text)
        let tokens = try lexer.tokenize()
        guard !tokens.isEmpty else { throw MathError.syntax(detail: "∅") }
        var parser = MathParser(tokens: tokens)
        let expr = try parser.parseExpression()
        if let extra = parser.peek {
            throw MathError.syntax(detail: "«\(extra.displayText)»")
        }
        return Output(expr: expr, assumedPowers: lexer.assumedPowers)
    }

    /// Разбор утверждения с отношениями: `2x + 5 = 11`, `x^2 > 4`.
    static func parseStatement(_ text: String) throws -> (statement: MathStatement, assumedPowers: Bool) {
        let normalized = MathNormalizer.normalize(text)
        var parts: [String] = []
        var relations: [Relation] = []
        var current = ""
        for c in normalized {
            if let relation = Relation(rawValue: String(c)) {
                parts.append(current)
                relations.append(relation)
                current = ""
            } else {
                current.append(c)
            }
        }
        parts.append(current)

        var sides: [Expr] = []
        var assumed = false
        for part in parts {
            guard !part.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw MathError.syntax(detail: "…")
            }
            let output = try parseDetailed(part)
            sides.append(output.expr)
            assumed = assumed || output.assumedPowers
        }
        return (MathStatement(sides: sides, relations: relations), assumed)
    }

    // MARK: - Token helpers

    private var peek: MathToken? {
        pos < tokens.count ? tokens[pos] : nil
    }

    private var previous: MathToken? {
        pos > 0 ? tokens[pos - 1] : nil
    }

    private mutating func advance() {
        pos += 1
    }

    private func isOp(_ token: MathToken?, _ c: Character) -> Bool {
        if case .op(let value)? = token { return value == c }
        return false
    }

    private mutating func expect(_ token: MathToken, _ description: String) throws {
        guard peek == token else {
            throw MathError.syntax(detail: "«\(description)»")
        }
        advance()
    }

    // MARK: - Grammar

    private mutating func parseExpression() throws -> Expr {
        var left = try parseTerm()
        while true {
            if isOp(peek, "+") {
                advance()
                left = .bin(.add, left, try parseTerm())
            } else if isOp(peek, "-") {
                advance()
                left = .bin(.sub, left, try parseTerm())
            } else {
                return left
            }
        }
    }

    private mutating func parseTerm() throws -> Expr {
        var left = try parseUnary()
        while true {
            if isOp(peek, "*") {
                advance()
                left = .bin(.mul, left, try parseUnary())
            } else if isOp(peek, "/") {
                advance()
                left = .bin(.div, left, try parseUnary())
            } else if startsImplicitFactor() {
                left = .bin(.mul, left, try parsePower())
            } else {
                return left
            }
        }
    }

    /// Неявное умножение: `2x`, `3(x + 1)`, `(a + b)(a − b)`, `2sin(x)`.
    private func startsImplicitFactor() -> Bool {
        guard let token = peek else { return false }
        switch token {
        case .ident, .function, .constant, .lparen, .exp:
            return true
        case .number, .real:
            // «2 3» — не произведение, а ошибка записи.
            switch previous {
            case .number, .real: return false
            default: return true
            }
        case .bar:
            return absDepth == 0
        default:
            return false
        }
    }

    private mutating func parseUnary() throws -> Expr {
        if isOp(peek, "-") {
            advance()
            return .neg(try parseUnary())
        }
        if isOp(peek, "+") {
            advance()
            return try parseUnary()
        }
        return try parsePower()
    }

    private mutating func parsePower() throws -> Expr {
        let base = try parsePostfix()
        if isOp(peek, "^") {
            advance()
            let exponent = try parseUnary()
            return .bin(.pow, base, exponent)
        }
        return base
    }

    private mutating func parsePostfix() throws -> Expr {
        var expr = try parsePrimary()
        while true {
            if isOp(peek, "!") {
                advance()
                expr = .fn(.factorial, [expr])
            } else if isOp(peek, "%") {
                advance()
                expr = .bin(.div, expr, .int(100))
            } else if peek == .degree {
                advance()
                expr = .fn(.deg, [expr])
            } else {
                return expr
            }
        }
    }

    private mutating func parsePrimary() throws -> Expr {
        guard let token = peek else {
            throw MathError.syntax(detail: "…")
        }
        advance()
        switch token {
        case .number(let value):
            return .num(value)
        case .real(let value):
            return .real(value)
        case .constant(let constant):
            return .const(constant)
        case .ident(let name):
            return .sym(name)
        case .lparen:
            let savedDepth = absDepth
            absDepth = 0
            let inner = try parseExpression()
            try expect(.rparen, ")")
            absDepth = savedDepth
            return inner
        case .bar:
            absDepth += 1
            let inner = try parseExpression()
            try expect(.bar, "|")
            absDepth -= 1
            return .fn(.abs, [inner])
        case .function(let function):
            return try parseFunction(function)
        case .exp:
            let argument = try parseFunctionArguments()
            guard argument.count == 1 else { throw MathError.syntax(detail: "exp") }
            return .bin(.pow, .const(.e), argument[0])
        default:
            throw MathError.syntax(detail: "«\(token.displayText)»")
        }
    }

    private mutating func parseFunction(_ function: MathFn) throws -> Expr {
        // sin²x, cos^2(x)
        var exponent: Expr?
        if isOp(peek, "^") {
            advance()
            exponent = try parsePrimary()
        }

        var base: Expr?
        if function == .log, case .logBase(let value)? = peek {
            advance()
            base = .num(value)
        }

        var arguments = try parseFunctionArguments()

        var result: Expr
        if function == .log {
            if let base {
                guard arguments.count == 1 else { throw MathError.syntax(detail: "log") }
                result = .fn(.log, [base, arguments[0]])
            } else if arguments.count == 2 {
                result = .fn(.log, arguments)
            } else if arguments.count == 1 {
                // Школьное соглашение: log без основания — десятичный.
                result = .fn(.lg, arguments)
            } else {
                throw MathError.syntax(detail: "log")
            }
        } else {
            guard arguments.count == 1 else { throw MathError.syntax(detail: function.displayName) }
            result = .fn(function, [arguments.removeFirst()])
        }

        if let exponent {
            result = .bin(.pow, result, exponent)
        }
        return result
    }

    /// Аргументы функции: в скобках через запятую либо «короткая» запись без скобок
    /// (`sin 2x`, `√16`, `ln x`).
    private mutating func parseFunctionArguments() throws -> [Expr] {
        if peek == .lparen {
            advance()
            let savedDepth = absDepth
            absDepth = 0
            var arguments = [try parseExpression()]
            while peek == .comma {
                advance()
                arguments.append(try parseExpression())
            }
            try expect(.rparen, ")")
            absDepth = savedDepth
            return arguments
        }

        // Без скобок аргумент — число и «прилипшие» к нему переменные: sin 2x, √2x.
        var argument = try parsePower()
        while let token = peek {
            switch token {
            case .ident, .constant:
                argument = .bin(.mul, argument, try parsePower())
                continue
            default:
                break
            }
            break
        }
        return [argument]
    }
}
