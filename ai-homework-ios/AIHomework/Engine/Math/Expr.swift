import Foundation

/// Встроенные математические функции.
enum MathFn: String, Sendable, Hashable, CaseIterable {
    case sqrt, cbrt
    case sin, cos, tan, cot
    case asin, acos, atan, acot
    case ln, lg
    /// Логарифм по основанию: аргументы `[основание, число]`.
    case log
    case abs
    /// Перевод градусов в радианы: `30°`.
    case deg
    case factorial

    /// Имя функции в отображаемой записи.
    var displayName: String {
        switch self {
        case .tan: return "tg"
        case .cot: return "ctg"
        case .asin: return "arcsin"
        case .acos: return "arccos"
        case .atan: return "arctg"
        case .acot: return "arcctg"
        default: return rawValue
        }
    }
}

enum BinOp: Sendable, Hashable {
    case add, sub, mul, div, pow
}

enum MathConst: String, Sendable, Hashable {
    case pi
    case e

    var value: Double {
        switch self {
        case .pi: return Double.pi
        case .e: return M_E
        }
    }

    var symbol: String {
        switch self {
        case .pi: return "π"
        case .e: return "e"
        }
    }
}

/// Синтаксическое дерево математического выражения.
indirect enum Expr: Hashable, Sendable {
    /// Точное рациональное число.
    case num(Rational)
    /// Приближённое вещественное число.
    case real(Double)
    /// Переменная.
    case sym(String)
    case const(MathConst)
    case neg(Expr)
    case bin(BinOp, Expr, Expr)
    case fn(MathFn, [Expr])

    static func int(_ value: Int) -> Expr { .num(Rational(value)) }

    static func add(_ a: Expr, _ b: Expr) -> Expr { .bin(.add, a, b) }
    static func sub(_ a: Expr, _ b: Expr) -> Expr { .bin(.sub, a, b) }
    static func mul(_ a: Expr, _ b: Expr) -> Expr { .bin(.mul, a, b) }
    static func div(_ a: Expr, _ b: Expr) -> Expr { .bin(.div, a, b) }
    static func pow(_ a: Expr, _ b: Expr) -> Expr { .bin(.pow, a, b) }

    /// Имена всех переменных выражения.
    var variables: Set<String> {
        switch self {
        case .num, .real, .const: return []
        case .sym(let name): return [name]
        case .neg(let inner): return inner.variables
        case .bin(_, let a, let b): return a.variables.union(b.variables)
        case .fn(_, let args): return args.reduce(into: Set<String>()) { $0.formUnion($1.variables) }
        }
    }

    var isConstant: Bool { variables.isEmpty }

    /// Содержит ли выражение хотя бы одну операцию или функцию (а не просто число/переменную).
    var hasOperation: Bool {
        switch self {
        case .num, .real, .sym, .const: return false
        case .neg(let inner): return inner.hasOperation
        case .bin, .fn: return true
        }
    }

    /// Встречаются ли тригонометрические функции (для оговорки о периодичности корней).
    var containsTrigonometry: Bool {
        switch self {
        case .num, .real, .sym, .const: return false
        case .neg(let inner): return inner.containsTrigonometry
        case .bin(_, let a, let b): return a.containsTrigonometry || b.containsTrigonometry
        case .fn(let f, let args):
            if [.sin, .cos, .tan, .cot].contains(f) { return true }
            return args.contains { $0.containsTrigonometry }
        }
    }

    /// Подстановка выражений вместо переменных.
    func substituting(_ values: [String: Expr]) -> Expr {
        switch self {
        case .num, .real, .const: return self
        case .sym(let name): return values[name] ?? self
        case .neg(let inner): return .neg(inner.substituting(values))
        case .bin(let op, let a, let b): return .bin(op, a.substituting(values), b.substituting(values))
        case .fn(let f, let args): return .fn(f, args.map { $0.substituting(values) })
        }
    }
}

/// Знак отношения между частями уравнения или неравенства.
enum Relation: String, Sendable, Hashable, CaseIterable {
    case eq = "="
    case ne = "≠"
    case lt = "<"
    case gt = ">"
    case le = "≤"
    case ge = "≥"

    var isInequality: Bool { self != .eq && self != .ne }

    /// Знак после умножения обеих частей на отрицательное число / перестановки сторон.
    var flipped: Relation {
        switch self {
        case .lt: return .gt
        case .gt: return .lt
        case .le: return .ge
        case .ge: return .le
        case .eq, .ne: return self
        }
    }

    /// Выполняется ли отношение `value ? 0` для знака числа.
    func holds(sign: Int) -> Bool {
        switch self {
        case .eq: return sign == 0
        case .ne: return sign != 0
        case .lt: return sign < 0
        case .gt: return sign > 0
        case .le: return sign <= 0
        case .ge: return sign >= 0
        }
    }

    var isStrict: Bool { self == .lt || self == .gt || self == .ne }
}

/// Утверждение: выражения, соединённые знаками отношения (`2x + 5 = 11`, `x > 3`).
struct MathStatement: Hashable, Sendable {
    var sides: [Expr]
    var relations: [Relation]

    var isPlainExpression: Bool { relations.isEmpty }

    var variables: Set<String> {
        sides.reduce(into: Set<String>()) { $0.formUnion($1.variables) }
    }
}
