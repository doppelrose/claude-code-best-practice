import XCTest
@testable import HomeworkEngine

final class MathCoreTests: XCTestCase {
    private let ru = MathFormatter(lang: .ru)
    private let evaluator = MathEvaluator()

    private func value(_ text: String) throws -> MathValue {
        try evaluator.evaluate(try MathParser.parse(text))
    }

    private func rational(_ n: Int, _ d: Int = 1) -> Rational {
        (try? Rational(n, d)) ?? .zero
    }

    func testRationalArithmetic() throws {
        XCTAssertEqual(try rational(1, 2) + rational(1, 3), rational(5, 6))
        XCTAssertEqual(try rational(3, 4) * rational(2, 3), rational(1, 2))
        XCTAssertEqual(try rational(-6, 4), rational(-3, 2))
        XCTAssertEqual(Rational(decimal: "3,5"), rational(7, 2))
        XCTAssertEqual(Rational(decimal: "0.25"), rational(1, 4))
        XCTAssertThrowsError(try Rational(1, 0))
        XCTAssertThrowsError(try Rational(Int.max) * Rational(Int.max))
        XCTAssertEqual(rational(9, 4).exactRoot(2), rational(3, 2))
        XCTAssertNil(rational(2).exactRoot(2))
    }

    func testOrderOfOperations() throws {
        XCTAssertEqual(try value("2 + 2 · 2"), .exact(Rational(6)))
        XCTAssertEqual(try value("(3,5 + 1,5) : 2"), .exact(rational(5, 2)))
        XCTAssertEqual(try value("2^3^2"), .exact(Rational(512)))
        XCTAssertEqual(try value("-3²"), .exact(Rational(-9)))
        XCTAssertEqual(try value("(-3)²"), .exact(Rational(9)))
        XCTAssertEqual(try value("1/2 + 1/3"), .exact(rational(5, 6)))
        XCTAssertEqual(try value("√16 + 3²"), .exact(Rational(13)))
        XCTAssertEqual(try value("sqrt(2)^2").double, 2, accuracy: 1e-12)
        XCTAssertEqual(try value("5!"), .exact(Rational(120)))
        XCTAssertEqual(try value("20% * 150"), .exact(Rational(30)))
        XCTAssertEqual(try value("|3 - 10|"), .exact(Rational(7)))
        XCTAssertEqual(try value("8^(1/3)"), .exact(Rational(2)))
    }

    func testImplicitMultiplicationAndFunctions() throws {
        let env: [String: MathValue] = ["x": .exact(Rational(3)), "y": .exact(Rational(2))]
        func at(_ text: String) throws -> MathValue { try evaluator.evaluate(try MathParser.parse(text), env) }
        XCTAssertEqual(try at("2x"), .exact(Rational(6)))
        XCTAssertEqual(try at("2x²"), .exact(Rational(18)))
        XCTAssertEqual(try at("x2 - 5x + 6"), .exact(Rational(0)))
        XCTAssertEqual(try at("(x + 1)(x - 1)"), .exact(Rational(8)))
        XCTAssertEqual(try at("xy"), .exact(Rational(6)))
        XCTAssertEqual(try at("2(x + y)"), .exact(Rational(10)))
        XCTAssertEqual(try at("x^2y"), .exact(Rational(18)))
    }

    func testTrigonometryIsExactAtTableAngles() throws {
        XCTAssertEqual(try value("sin(30°)"), .exact(rational(1, 2)))
        XCTAssertEqual(try value("sin 30° + cos 60°"), .exact(Rational(1)))
        XCTAssertEqual(try value("cos(pi)"), .exact(Rational(-1)))
        XCTAssertEqual(try value("tg(45°)"), .exact(Rational(1)))
        XCTAssertEqual(try value("arcsin(1/2)"), .piMultiple(rational(1, 6)))
        XCTAssertEqual(try value("sin(45°)").double, 0.5.squareRoot(), accuracy: 1e-12)
        XCTAssertThrowsError(try value("tg(90°)"))
    }

    func testLogarithms() throws {
        XCTAssertEqual(try value("log₂(8)"), .exact(Rational(3)))
        XCTAssertEqual(try value("log_2(8)"), .exact(Rational(3)))
        XCTAssertEqual(try value("log2(8)"), .exact(Rational(3)))
        XCTAssertEqual(try value("lg(1000)"), .exact(Rational(3)))
        XCTAssertEqual(try value("log(4; 8)"), .exact(rational(3, 2)))
        XCTAssertEqual(try value("ln(e^2)").double, 2, accuracy: 1e-12)
        XCTAssertThrowsError(try value("ln(0)"))
    }

    func testDomainErrors() {
        XCTAssertThrowsError(try value("1/0")) { XCTAssertEqual($0 as? MathError, .divisionByZero) }
        XCTAssertThrowsError(try value("√(-4)"))
        XCTAssertThrowsError(try value("2 +"))
        XCTAssertThrowsError(try value("2 3"))
        XCTAssertThrowsError(try value("(2 + 3"))
    }

    func testFormatting() throws {
        func show(_ text: String) throws -> String { ru.expr(try MathParser.parse(text)) }
        XCTAssertEqual(try show("2*x^2-5*x+6"), "2x² − 5x + 6")
        XCTAssertEqual(try show("(x+1)*(x-1)"), "(x + 1)(x − 1)")
        XCTAssertEqual(try show("sqrt(x+1)"), "√(x + 1)")
        XCTAssertEqual(try show("sqrt(16)"), "√16")
        XCTAssertEqual(try show("2*3"), "2·3")
        XCTAssertEqual(try show("a-(b-c)"), "a − (b − c)")
        XCTAssertEqual(try show("(x+1)/(x-2)"), "(x + 1)/(x − 2)")
        XCTAssertEqual(try show("2^(x+1)"), "2^(x + 1)")
        XCTAssertEqual(try show("sin(x)*cos(x)"), "sin(x)·cos(x)")
        XCTAssertEqual(try show("abs(x-3)"), "|x − 3|")
        XCTAssertEqual(ru.approx(0.1 + 0.2), "0,3")
        XCTAssertEqual(ru.approx(-1234.5678, significant: 6), "−1234,57")
        XCTAssertEqual(ru.approx(3e8), "300000000")
        XCTAssertEqual(MathFormatter(lang: .en).approx(1.5e-7), "1.5·10⁻⁷")
        XCTAssertEqual(ru.rationalWithApproximation(rational(7, 2)), "7/2 = 3,5")
        XCTAssertEqual(ru.exactDecimal(rational(-1, 8)), "−0,125")
    }

    func testFormatterOutputIsParseable() throws {
        let samples = ["2x² − 5x + 6", "(x + 1)(x − 1)/(x − 2)", "√(x + 1) + |x − 3|", "2^(x + 1) − x³", "log₂(x) + sin(x)·cos(x)"]
        for sample in samples {
            let first = try MathParser.parse(sample)
            let second = try MathParser.parse(ru.expr(first))
            let a = evaluator.numeric(first, variable: "x", at: 5.25)
            let b = evaluator.numeric(second, variable: "x", at: 5.25)
            XCTAssertEqual(a, b, accuracy: 1e-9, sample)
        }
    }

    func testPolynomialBasics() throws {
        let x = Polynomial(variable: "x")
        let one = Polynomial.one
        let square = try (try x + one).power(2)
        XCTAssertEqual(ru.polynomial(square), "x² + 2x + 1")
        let (roots, remaining) = try UnivariatePolynomial.extractRationalRoots(
            [Rational(-6), Rational(11), Rational(-6), Rational(1)])
        XCTAssertEqual(roots.sorted(), [Rational(1), Rational(2), Rational(3)])
        XCTAssertEqual(remaining, [Rational(1)])
    }
}
