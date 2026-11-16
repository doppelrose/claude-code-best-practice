import Foundation

/// Рекурсивный спуск по грамматике школьной математической записи.
///
/// ```
/// expr    := term (('+' | '-') term)*
/// term    := unary (('*' | '/') unary | ':' colonOperand | implicitFactor)*
/// unary   := ('-' | '+') unary | power
/// power   := postfix ('^' unary)?
/// postfix := primary ('!' | '%' | '°')*
/// primary := number | constant | variable | function | '(' expr ')' | '|' expr '|'
/// ```
///
/// Защита от переполнения стека (AUD-14): число токенов, глубина вложенности и глубина
/// итогового дерева ограничены, а длинные цепочки сложения и умножения собираются
/// сбалансированным деревом (глубина log n вместо n). Всё, что за пределами, —
/// честный отказ `MathError.tooComplex`, а не падение приложения.
struct MathParser {
    /// Не больше стольких токенов в одной части записи.
    static let maxTokens = 1000
    /// Вложенность скобок, функций, унарных знаков и степеней.
    static let maxNesting = 40
    /// Глубина итогового дерева: её обходят рекурсивно упрощение, форматирование и решатели.
    static let maxTreeDepth = 100
    /// С какой длины цепочка `a + b + …` собирается сбалансированным деревом.
    /// Короткие цепочки остаются левоассоциативными — так привычнее «по действиям».
    static let balanceThreshold = 16

    private let tokens: [MathToken]
    private var pos = 0
    private var absDepth = 0
    private var nesting = 0
    private var heuristics = Heuristics()

    /// Эвристики, применённые при чтении записи: о каждой нужно предупредить пользователя.
    struct Heuristics: Sendable, Equatable {
        /// «x2» или «(x+1)2» прочитано как степень.
        var assumedPowers = false
        /// «1 1/2» прочитано как смешанное число.
        var mixedNumbers = false
        /// «2/3 : 4/9» прочитано как деление дробей (2/3) : (4/9).
        var colonFractions = false

        var any: Bool { assumedPowers || mixedNumbers || colonFractions }

        mutating func formUnion(_ other: Heuristics) {
            assumedPowers = assumedPowers || other.assumedPowers
            mixedNumbers = mixedNumbers || other.mixedNumbers
            colonFractions = colonFractions || other.colonFractions
        }
    }

    /// Результат разбора вместе с пометками об эвристиках.
    struct Output: Sendable {
        var expr: Expr
        var heuristics: Heuristics

        var assumedPowers: Bool { heuristics.assumedPowers }
    }

    private init(tokens: [MathToken]) {
        self.tokens = tokens
    }

    static func parse(_ text: String) throws -> Expr {
        try parseDetailed(text).expr
    }

    static func parseDetailed(_ text: String) throws -> Output {
        var lexer = MathLexer(MathNormalizer.subscriptIndexedVariables(text))
        let tokens = try lexer.tokenize()
        guard !tokens.isEmpty else { throw MathError.syntax(detail: "∅") }
        guard tokens.count <= maxTokens else { throw MathError.tooComplex }
        var parser = MathParser(tokens: tokens)
        let expr = try parser.parseExpression()
        if let extra = parser.peek {
            throw MathError.syntax(detail: "«\(extra.displayText)»")
        }
        guard expr.treeDepth <= maxTreeDepth else { throw MathError.tooComplex }
        var heuristics = parser.heuristics
        heuristics.assumedPowers = heuristics.assumedPowers || lexer.assumedPowers
        heuristics.mixedNumbers = heuristics.mixedNumbers || lexer.mixedNumbers
        return Output(expr: expr, heuristics: heuristics)
    }

    /// Разбор утверждения с отношениями: `2x + 5 = 11`, `x^2 > 4`.
    static func parseStatement(_ text: String) throws -> (statement: MathStatement, assumedPowers: Bool, heuristics: Heuristics) {
        let normalized = MathNormalizer.subscriptIndexedVariables(MathNormalizer.normalize(text))
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
        var heuristics = Heuristics()
        for part in parts {
            guard !part.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw MathError.syntax(detail: "…")
            }
            let output = try parseDetailed(part)
            sides.append(output.expr)
            heuristics.formUnion(output.heuristics)
        }
        return (MathStatement(sides: sides, relations: relations), heuristics.assumedPowers, heuristics)
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

    /// Вход в очередной уровень рекурсии: скобки, функция, унарный знак, показатель степени.
    private mutating func enter() throws {
        nesting += 1
        guard nesting <= MathParser.maxNesting else { throw MathError.tooComplex }
    }

    private mutating func leave() {
        nesting -= 1
    }

    private mutating func parseExpression() throws -> Expr {
        // Цепочка слагаемых собирается итеративно, а дерево строится в конце.
        var terms = [try parseTerm()]
        var operators: [BinOp] = []
        while true {
            if isOp(peek, "+") {
                advance()
                operators.append(.add)
            } else if isOp(peek, "-") {
                advance()
                operators.append(.sub)
            } else {
                break
            }
            terms.append(try parseTerm())
            guard terms.count <= MathParser.maxTokens else { throw MathError.tooComplex }
        }
        return MathParser.sumTree(terms, operators)
    }

    /// Дерево для `t₀ op₁ t₁ op₂ t₂ …`. Короткая цепочка — левоассоциативная, как в учебнике;
    /// длинная — сбалансированная, чтобы рекурсивные обходы не переполняли стек.
    static func sumTree(_ terms: [Expr], _ operators: [BinOp]) -> Expr {
        precondition(terms.count == operators.count + 1)
        if terms.count < balanceThreshold {
            var result = terms[0]
            for (index, op) in operators.enumerated() {
                result = .bin(op, result, terms[index + 1])
            }
            return result
        }
        return balancedSum(terms[...], operators[...])
    }

    /// `operators[i]` стоит перед `terms[i + 1]`.
    private static func balancedSum(_ terms: ArraySlice<Expr>, _ operators: ArraySlice<BinOp>) -> Expr {
        let count = terms.count
        if count == 1 { return terms[terms.startIndex] }
        if count < 4 {
            var result = terms[terms.startIndex]
            for (offset, op) in operators.enumerated() {
                result = .bin(op, result, terms[terms.startIndex + offset + 1])
            }
            return result
        }
        // Делим по «+» поближе к середине: a + (b − c) = a + b − c без перестановки знаков.
        // Если «+» нет, делим по «−» и меняем знаки правой части: a − b + c = a − (b − c).
        let middle = count / 2
        var split = middle
        var bestDistance = Int.max
        for offset in 1..<count {
            let op = operators[operators.startIndex + offset - 1]
            let distance = abs(offset - middle)
            if op == .add, distance < bestDistance {
                bestDistance = distance
                split = offset
            }
        }
        if bestDistance > count / 4 { split = middle }
        let joinOperator = operators[operators.startIndex + split - 1]
        let left = balancedSum(
            terms[terms.startIndex..<(terms.startIndex + split)],
            operators[operators.startIndex..<(operators.startIndex + split - 1)])
        var rightOperators = Array(operators[(operators.startIndex + split)...])
        if joinOperator == .sub {
            rightOperators = rightOperators.map { $0 == .add ? .sub : .add }
        }
        let right = balancedSum(terms[(terms.startIndex + split)...], rightOperators[...])
        return .bin(joinOperator, left, right)
    }

    private mutating func parseTerm() throws -> Expr {
        // Множители собираем группами «произведений»: деление остаётся левоассоциативным,
        // а длинная цепочка умножений строится сбалансированно.
        var factors = [try parseUnary()]
        var operators: [BinOp] = []
        while true {
            if isOp(peek, "*") {
                advance()
                operators.append(.mul)
                factors.append(try parseUnary())
            } else if isOp(peek, "/") {
                advance()
                operators.append(.div)
                factors.append(try parseUnary())
            } else if isOp(peek, ":") {
                advance()
                operators.append(.div)
                factors.append(try parseColonOperand())
            } else if startsImplicitFactor() {
                operators.append(.mul)
                factors.append(try parsePower())
            } else {
                break
            }
            guard factors.count <= MathParser.maxTokens else { throw MathError.tooComplex }
        }
        return MathParser.productTree(factors, operators)
    }

    static func productTree(_ factors: [Expr], _ operators: [BinOp]) -> Expr {
        precondition(factors.count == operators.count + 1)
        if factors.count < balanceThreshold || operators.contains(.div) {
            var result = factors[0]
            for (index, op) in operators.enumerated() {
                result = .bin(op, result, factors[index + 1])
            }
            return result
        }
        return balancedProduct(factors[...])
    }

    private static func balancedProduct(_ factors: ArraySlice<Expr>) -> Expr {
        if factors.count == 1 { return factors[factors.startIndex] }
        let split = factors.startIndex + factors.count / 2
        return .bin(.mul, balancedProduct(factors[factors.startIndex..<split]), balancedProduct(factors[split...]))
    }

    /// Правый операнд школьного «:»: числовая дробь `a/b` рядом с двоеточием — это одно число,
    /// `2/3 : 4/9 = (2/3) : (4/9)` (так OCR передаёт «двухэтажные» дроби).
    private mutating func parseColonOperand() throws -> Expr {
        if pos + 2 < tokens.count, isNumberToken(tokens[pos]), isOp(tokens[pos + 1], "/"), isNumberToken(tokens[pos + 2]),
            fractionEnds(at: pos + 3)
        {
            let numerator = tokens[pos]
            let denominator = tokens[pos + 2]
            pos += 3
            heuristics.colonFractions = true
            return .bin(.div, MathParser.literal(numerator), MathParser.literal(denominator))
        }
        return try parseUnary()
    }

    private func isNumberToken(_ token: MathToken) -> Bool {
        switch token {
        case .number, .real: return true
        default: return false
        }
    }

    private static func literal(_ token: MathToken) -> Expr {
        switch token {
        case .number(let value): return .num(value)
        case .real(let value): return .real(value)
        default: return .int(0)
        }
    }

    /// Закончилась ли дробь `a/b` на позиции `index` (дальше нет степени, переменной, скобки…).
    private func fractionEnds(at index: Int) -> Bool {
        guard index < tokens.count else { return true }
        switch tokens[index] {
        case .op(let c): return "+-*/:".contains(c)
        case .rparen, .comma, .bar: return true
        default: return false
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
            try enter()
            defer { leave() }
            return .neg(try parseUnary())
        }
        if isOp(peek, "+") {
            advance()
            try enter()
            defer { leave() }
            return try parseUnary()
        }
        return try parsePower()
    }

    private mutating func parsePower() throws -> Expr {
        let base = try parsePostfix()
        if isOp(peek, "^") {
            advance()
            try enter()
            defer { leave() }
            let exponent = try parseUnary()
            return .bin(.pow, base, exponent)
        }
        return base
    }

    private mutating func parsePostfix() throws -> Expr {
        var expr = try parsePrimary()
        var count = 0
        while true {
            count += 1
            guard count <= MathParser.maxNesting else { throw MathError.tooComplex }
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
        try enter()
        defer { leave() }
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
        var count = 0
        while let token = peek {
            switch token {
            case .ident, .constant:
                count += 1
                guard count <= MathParser.maxNesting else { throw MathError.tooComplex }
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
