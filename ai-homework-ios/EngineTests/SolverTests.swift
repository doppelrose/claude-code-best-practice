import XCTest
@testable import HomeworkEngine

final class SolverTests: XCTestCase {
    private let fmt = MathFormatter(lang: .ru)
    private var equations: EquationSolver { EquationSolver(lang: .ru, formatter: fmt) }
    private var inequalities: InequalitySolver { InequalitySolver(lang: .ru, formatter: fmt) }
    private var systems: SystemSolver { SystemSolver(lang: .ru, formatter: fmt) }

    private func solveEquation(_ text: String, _ x: String = "x") throws -> EquationOutcome {
        let statement = try MathParser.parseStatement(text).statement
        return try equations.solve(lhs: statement.sides[0], rhs: statement.sides[1], variable: x)
    }

    private func solveInequality(_ text: String) throws -> InequalityOutcome {
        let statement = try MathParser.parseStatement(text).statement
        return try inequalities.solve(lhs: statement.sides[0], rhs: statement.sides[1], relation: statement.relations[0], variable: "x")
    }

    private func solveSystem(_ texts: [String]) throws -> SystemOutcome {
        let pairs = try texts.map { text -> (lhs: Expr, rhs: Expr) in
            let statement = try MathParser.parseStatement(text).statement
            return (statement.sides[0], statement.sides[1])
        }
        return try systems.solve(pairs)
    }

    func testLinearEquations() throws {
        XCTAssertEqual(try solveEquation("2x + 5 = 11").answer, "x = 3")
        XCTAssertEqual(try solveEquation("3(x - 2) = 2x + 1").answer, "x = 7")
        XCTAssertEqual(try solveEquation("x/2 + x/3 = 5").answer, "x = 6")
        XCTAssertEqual(try solveEquation("4x = 2").answer, "x = 1/2 = 0,5")
        XCTAssertEqual(try solveEquation("2x + 1 = 2x + 1").set, .all)
        XCTAssertEqual(try solveEquation("2x + 1 = 2x + 3").set, .none)
        XCTAssertGreaterThanOrEqual(try solveEquation("2x + 5 = 11").steps.count, 4)
    }

    func testQuadraticEquations() throws {
        XCTAssertEqual(try solveEquation("x² − 5x + 6 = 0").answer, "x₁ = 2; x₂ = 3")
        XCTAssertEqual(try solveEquation("x^2 - 4x + 4 = 0").answer, "x = 2")
        XCTAssertEqual(try solveEquation("x² + 1 = 0").set, .none)
        XCTAssertEqual(try solveEquation("x² − 3x + 1 = 0").answer, "x₁ = (3 − √5)/2 ≈ 0,381966; x₂ = (3 + √5)/2 ≈ 2,61803")
        XCTAssertEqual(try solveEquation("x² = 8").answer, "x₁ = −2√2 ≈ −2,82843; x₂ = 2√2 ≈ 2,82843")
        XCTAssertEqual(try solveEquation("2x² − 10x + 12 = 0").answer, "x₁ = 2; x₂ = 3")
        XCTAssertEqual(try solveEquation("x(x − 4) = 5").answer, "x₁ = −1; x₂ = 5")
    }

    func testHigherDegreeAndRational() throws {
        XCTAssertEqual(try solveEquation("x³ − 6x² + 11x − 6 = 0").answer, "x₁ = 1; x₂ = 2; x₃ = 3")
        XCTAssertEqual(try solveEquation("x⁴ − 5x² + 4 = 0").answer, "x₁ = −2; x₂ = −1; x₃ = 1; x₄ = 2")
        XCTAssertEqual(try solveEquation("x⁴ − 5x² + 6 = 0").roots.count, 4)
        XCTAssertTrue(try solveEquation("x⁴ − 5x² + 6 = 0").answer.contains("√3"))
        XCTAssertEqual(try solveEquation("(x + 1)/(x − 2) = 3").answer, "x = 7/2 = 3,5")
        XCTAssertEqual(try solveEquation("3/x = 6").answer, "x = 1/2 = 0,5")
        XCTAssertEqual(try solveEquation("(x² − 1)/(x − 1) = 2").set, .none)
        let cubic = try solveEquation("x³ + x + 1 = 0")
        XCTAssertTrue(cubic.isApproximate)
        XCTAssertEqual(cubic.roots.first?.double ?? 0, -0.6823278038280193, accuracy: 1e-9)
    }

    func testNonPolynomialEquations() throws {
        XCTAssertEqual(try solveEquation("2^x = 8").answer, "x = 3")
        XCTAssertEqual(try solveEquation("√(x + 1) = 3").answer, "x = 8")
        XCTAssertEqual(try solveEquation("|x − 3| = 5").answer, "x₁ = −2; x₂ = 8")
        XCTAssertEqual(try solveEquation("sin(x) = 1/2").answer, "x₁ = π/6 + 2πn, n ∈ ℤ; x₂ = 5π/6 + 2πn, n ∈ ℤ")
        XCTAssertEqual(try solveEquation("lg(x) = 2").answer, "x = 100")
        XCTAssertTrue(try solveEquation("2^x = -1").roots.isEmpty)
    }

    func testParametricEquation() throws {
        XCTAssertEqual(try solveEquation("ax + b = 0").answer, "x = −b/a")
        XCTAssertEqual(try solveEquation("2x + y = 10").answer, "x = −1/2·y + 5")
    }

    func testInequalities() throws {
        XCTAssertEqual(try solveInequality("2x − 3 > 5").answer, "x > 4, то есть x ∈ (4; +∞)")
        XCTAssertEqual(try solveInequality("−2x ≥ 6").answer, "x ≤ −3, то есть x ∈ (−∞; −3]")
        XCTAssertEqual(try solveInequality("x² − 5x + 6 > 0").answer, "x ∈ (−∞; 2) ∪ (3; +∞)")
        XCTAssertEqual(try solveInequality("x² − 5x + 6 ≤ 0").answer, "2 ≤ x ≤ 3, то есть x ∈ [2; 3]")
        XCTAssertEqual(try solveInequality("x² + 1 > 0").answer, "x — любое число")
        XCTAssertEqual(try solveInequality("x² + 1 < 0").answer, "Нет решений")
        XCTAssertEqual(try solveInequality("(x − 1)² ≤ 0").answer, "x = 1")
        XCTAssertEqual(try solveInequality("(x − 1)² ≥ 0").answer, "x — любое число")
        XCTAssertEqual(try solveInequality("(x − 1)² > 0").answer, "x ∈ (−∞; 1) ∪ (1; +∞)")
        XCTAssertEqual(try solveInequality("(x + 1)/(x − 2) ≥ 0").answer, "x ∈ (−∞; −1] ∪ (2; +∞)")
    }

    func testSystems() throws {
        XCTAssertEqual(try solveSystem(["x + y = 5", "x − y = 1"]).answer, "x = 3; y = 2")
        XCTAssertEqual(try solveSystem(["2x + 3y = 12", "x − y = 1"]).answer, "x = 3; y = 2")
        XCTAssertEqual(try solveSystem(["x + y + z = 6", "x − y + z = 2", "2x + y − z = 1"]).answer, "x = 1; y = 2; z = 3")
        XCTAssertTrue(try solveSystem(["x + y = 2", "2x + 2y = 4"]).answer.contains("бесконечно"))
        XCTAssertTrue(try solveSystem(["x + y = 2", "x + y = 3"]).answer.contains("не имеет"))
        XCTAssertEqual(try solveSystem(["x + y = 5", "xy = 6"]).answer, "(x; y): (3; 2), (2; 3)")
    }

    func testDerivatives() throws {
        func derivative(_ text: String) throws -> String {
            var differentiator = Differentiator()
            return fmt.expr(try differentiator.derivative(of: try MathParser.parse(text), by: "x"))
        }
        XCTAssertEqual(try derivative("3x² + 2x − 1"), "6x + 2")
        XCTAssertEqual(try derivative("x³"), "3x²")
        XCTAssertEqual(try derivative("sin(x)"), "cos(x)")
        XCTAssertEqual(try derivative("sin(2x)"), "2cos(2x)")
        XCTAssertEqual(try derivative("e^x"), "e^x")
        XCTAssertEqual(try derivative("ln(x)"), "1/x")
        XCTAssertEqual(try derivative("x·sin(x)"), "sin(x) + x·cos(x)")
        XCTAssertEqual(try derivative("√x"), "1/(2√x)")
        XCTAssertEqual(try derivative("5"), "0")
    }

    func testFactoring() throws {
        func factor(_ text: String) throws -> String {
            let polynomial = try XCTUnwrap(try Algebra.polynomial(try MathParser.parse(text)))
            return try Factorizer(fmt: fmt).factor(polynomial, L10n(.ru)).text
        }
        XCTAssertEqual(try factor("x² − 9"), "(x + 3)(x − 3)")
        XCTAssertEqual(try factor("x² − 5x + 6"), "(x − 2)(x − 3)")
        XCTAssertEqual(try factor("2x² − 8"), "2(x + 2)(x − 2)")
        XCTAssertEqual(try factor("x² + 2x + 1"), "(x + 1)²")
        XCTAssertEqual(try factor("x³ − x"), "(x + 1)x(x − 1)")
        XCTAssertEqual(try factor("a² − b²"), "(a − b)(a + b)")
        XCTAssertEqual(try factor("a² + 2ab + b²"), "(a + b)²")
        XCTAssertEqual(try factor("6a²b − 9ab²"), "3ab(2a − 3b)")
        XCTAssertEqual(try factor("2x² − x − 1"), "(2x + 1)(x − 1)")
    }
}
