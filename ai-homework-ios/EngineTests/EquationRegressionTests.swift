import Foundation
import XCTest
@testable import HomeworkEngine

/// Регрессионные тесты на неверные ответы из аудита (AUD-01…AUD-04, AUD-57):
/// входы взяты из `audit/software-tester.md` («Проверочные задания») и
/// `audit/ai-ml-engineer.md` («Входы для проверочных тестов»).
final class EquationRegressionTests: XCTestCase {
    private let fmt = MathFormatter(lang: .ru)
    private var equations: EquationSolver { EquationSolver(lang: .ru, formatter: fmt) }
    private var inequalities: InequalitySolver { InequalitySolver(lang: .ru, formatter: fmt) }
    private var systems: SystemSolver { SystemSolver(lang: .ru, formatter: fmt) }

    private func solveEquation(_ text: String, _ x: String = "x") throws -> EquationOutcome {
        let statement = try MathParser.parseStatement(text).statement
        return try equations.solve(lhs: statement.sides[0], rhs: statement.sides[1], variable: x)
    }

    private func solveInequality(_ text: String, _ relation: Relation? = nil) throws -> InequalityOutcome {
        let statement = try MathParser.parseStatement(text).statement
        return try inequalities.solve(
            lhs: statement.sides[0], rhs: statement.sides[1], relation: relation ?? statement.relations[0], variable: "x")
    }

    private func solveSystem(_ texts: [String]) throws -> SystemOutcome {
        let pairs = try texts.map { text -> (lhs: Expr, rhs: Expr) in
            let statement = try MathParser.parseStatement(text).statement
            return (statement.sides[0], statement.sides[1])
        }
        return try systems.solve(pairs)
    }

    /// Точный ответ: проверяем и текст, и метку «точно».
    private func assertExact(_ text: String, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        do {
            let outcome = try solveEquation(text)
            XCTAssertEqual(outcome.answer, expected, text, file: file, line: line)
            XCTAssertFalse(outcome.isApproximate, "\(text) should be exact", file: file, line: line)
        } catch {
            XCTFail("\(text): \(error)", file: file, line: line)
        }
    }

    // MARK: - AUD-01. Дробно-рациональные тождества

    func testRationalIdentitiesKeepDomain() {
        assertExact("x/x = 1", "x — любое число, кроме 0")
        assertExact("(x - 1)/(x - 1) = 1", "x — любое число, кроме 1")
        assertExact("(x^2 - 9)/(x - 3) = x + 3", "x — любое число, кроме 3")
        assertExact("(x + 2)/(x + 2) = 1", "x — любое число, кроме −2")
        assertExact("(x^2 - 1)/(x + 1) = x - 1", "x — любое число, кроме −1")
        assertExact("x/(x - 1) = 1/(x - 1) + 1", "x — любое число, кроме 1")
        assertExact("x/(x^2 - 4) = x/(x^2 - 4)", "x — любое число, кроме −2; 2")
        // Знаменатель, который «исчезает» при упрощении, всё равно сужает ОДЗ.
        assertExact("1/(1/x) = x", "x — любое число, кроме 0")
    }

    func testRationalIdentityEnglish() throws {
        let statement = try MathParser.parseStatement("x/x = 1").statement
        let outcome = try EquationSolver(lang: .en, formatter: MathFormatter(lang: .en))
            .solve(lhs: statement.sides[0], rhs: statement.sides[1], variable: "x")
        XCTAssertEqual(outcome.answer, "x is any number except 0")
    }

    func testRationalEquationsWithoutRootsStayEmpty() {
        assertExact("x/(x - 1) = 1/(x - 1)", "Действительных корней нет")
        assertExact("(x^2 - 1)/(x - 1) = 2", "Действительных корней нет")
        assertExact("(x^2 - 4)/(x - 2) = 4", "Действительных корней нет")
        assertExact("(x - 1)^2/(x - 1) = 0", "Действительных корней нет")
        assertExact("1/(x - 2) = 0", "Действительных корней нет")
        assertExact("1/(x^2 - 4) = 1/(x - 2)", "x = −1")
    }

    func testRationalIdentityThroughMathSolver() {
        let solution = MathSolver(lang: .ru).solve("(x - 1)/(x - 1) = 1")
        XCTAssertEqual(solution?.answer, "x — любое число, кроме 1")
        XCTAssertEqual(solution?.reliability, .exact)
    }

    // MARK: - AUD-02. Тождества на промежутке

    func testIdentitiesOnHalfLine() {
        assertExact("|x| = x", "x ≥ 0, то есть x ∈ [0; +∞)")
        assertExact("sqrt(x^2) = x", "x ≥ 0, то есть x ∈ [0; +∞)")
        assertExact("|x - 1| = x - 1", "x ≥ 1, то есть x ∈ [1; +∞)")
        assertExact("sqrt(x) = sqrt(x)", "x ≥ 0, то есть x ∈ [0; +∞)")
        assertExact("|x| = -x", "x ≤ 0, то есть x ∈ (−∞; 0]")
        assertExact("|x| + |x - 2| = 2", "0 ≤ x ≤ 2, то есть x ∈ [0; 2]")
    }

    func testTrigonometricIdentity() throws {
        let start = Date()
        let outcome = try solveEquation("sin(x)^2 + cos(x)^2 = 1")
        XCTAssertEqual(outcome.answer, "x — любое число")
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0)
    }

    /// Тождество, проверенное численно, не должно терять ограничения области определения.
    func testNumericIdentityKeepsDomainCaveat() throws {
        let outcome = try solveEquation("tan(x)*cot(x) = 1")
        XCTAssertNotEqual(outcome.answer, "x — любое число")
        XCTAssertTrue(outcome.isApproximate)
    }

    func testPathologicalInputsAreFastAndShort() {
        for text in ["|x| = x", "sqrt(x^2) = x", "|x - 1| = x - 1", "sqrt(x) = sqrt(x)", "sin(x)^2 + cos(x)^2 = 1"] {
            let start = Date()
            let outcome = try? solveEquation(text)
            XCTAssertLessThan(Date().timeIntervalSince(start), 1.0, text)
            XCTAssertLessThan(outcome?.answer.count ?? 0, 200, text)
        }
    }

    /// Равенство выполняется на целых промежутках, которые локальный движок не умеет описать:
    /// честный отказ или короткий приближённый ответ — но не список из тысяч «корней».
    func testIntervalSolutionsWithoutClosedFormAreNotListed() {
        for text in ["|sin(x)| = sin(x)", "sin(1/x) = 0"] {
            let start = Date()
            if let outcome = try? solveEquation(text) {
                XCTAssertLessThan(outcome.answer.count, 400, text)
                XCTAssertTrue(outcome.isApproximate, text)
            }
            XCTAssertLessThan(Date().timeIntervalSince(start), 1.5, text)
        }
    }

    func testIdentityThroughMathSolverIsNotHugeList() {
        let solution = MathSolver(lang: .ru).solve("|x| = x")
        XCTAssertEqual(solution?.answer, "x ≥ 0, то есть x ∈ [0; +∞)")
        XCTAssertEqual(solution?.reliability, .exact)
    }

    // MARK: - AUD-03. Корни вне [−1000; 1000] и метка «точно»

    func testAbsoluteValueEquationsAreSolvedAnalytically() {
        assertExact("|x - 1500| = 1000", "x₁ = 500; x₂ = 2500")
        assertExact("|x| = 2000", "x₁ = −2000; x₂ = 2000")
        assertExact("|x - 1500| = 0", "x = 1500")
        assertExact("|x - 3| = 5", "x₁ = −2; x₂ = 8")
        assertExact("|x| = -2", "Действительных корней нет")
        assertExact("|2x - 1| = |x + 4|", "x₁ = −1; x₂ = 5")
        assertExact("||x| - 1| = 2", "x₁ = −3; x₂ = 3")
        assertExact("|x^2 - 5| = 4", "x₁ = −3; x₂ = −1; x₃ = 1; x₄ = 3")
    }

    func testRadicalEquationsAreSolvedAnalytically() {
        assertExact("sqrt(x) = 40", "x = 1600")
        assertExact("sqrt(x) = -3", "Действительных корней нет")
        assertExact("sqrt(x - 5) = sqrt(3 - x)", "Действительных корней нет")
        assertExact("sqrt(x + 3) = x - 3", "x = 6")
        assertExact("sqrt(x + 1) = 3", "x = 8")
        assertExact("sqrt(2x + 1) = sqrt(x + 5)", "x = 4")
        assertExact("sqrt(x) + 2 = 2002", "x = 4000000")
    }

    func testNumericRootsFarFromZeroAndHonestLabel() throws {
        // e¹⁰ ≈ 22026,47 — раньше «корней не найдено» на [−1000; 1000].
        let log = try solveEquation("ln(x) = 10")
        XCTAssertEqual(log.roots.count, 1)
        XCTAssertEqual(log.roots.first?.double ?? 0, exp(10), accuracy: 1e-6 * exp(10))
        XCTAssertTrue(log.isApproximate)

        let far = try solveEquation("2^(x/1000) = 4")
        XCTAssertEqual(far.answer, "x = 2000")
        XCTAssertTrue(far.isApproximate, "numeric search cannot prove that no root was missed")

        // Корень найден численно — метка не «точно», даже если сам корень уточнён до дроби.
        let exponential = try solveEquation("2^x = 8")
        XCTAssertEqual(exponential.answer, "x = 3")
        XCTAssertTrue(exponential.isApproximate)
    }

    func testNumericEmptyAnswerMentionsSearch() throws {
        let outcome = try solveEquation("2^x = -1")
        XCTAssertTrue(outcome.roots.isEmpty)
        XCTAssertTrue(outcome.isApproximate)
        XCTAssertFalse(outcome.answer.contains("[−1000; 1000]"))
    }

    func testFarRootThroughMathSolverIsNotExact() {
        let solution = MathSolver(lang: .ru).solve("|x - 1500| = 1000")
        XCTAssertEqual(solution?.answer, "x₁ = 500; x₂ = 2500")
        XCTAssertEqual(solution?.reliability, .exact)
        let numeric = MathSolver(lang: .ru).solve("2^x = 1024")
        XCTAssertEqual(numeric?.answer, "x = 10")
        XCTAssertEqual(numeric?.reliability, .approximate)
    }

    // MARK: - AUD-04. Большие коэффициенты

    func testQuadraticWithLargeCoefficientsKeepsBothRoots() throws {
        let first = try solveEquation("x^2 - 1000000x + 1 = 0")
        XCTAssertEqual(first.roots.count, 2, first.answer)
        XCTAssertFalse(first.isApproximate)
        XCTAssertFalse(first.notes.contains { $0.contains("отброшено") }, first.notes.joined())
        // Малый корень ≈ 10⁻⁶ показан без потери точности.
        XCTAssertTrue(first.answer.hasPrefix("x₁ = 500000 − 127√15500031 ≈ 10⁻⁶;"), first.answer)
        XCTAssertEqual(first.roots.first?.preciseDouble ?? 0, 1.000000000001e-6, accuracy: 1e-15)

        let second = try solveEquation("x^2 + 1000000001x + 1 = 0")
        XCTAssertEqual(second.roots.count, 2, second.answer)
        XCTAssertFalse(second.isApproximate)
        XCTAssertNotEqual(second.answer, "Действительных корней нет")
        XCTAssertFalse(second.answer.contains("≈ 0;"), second.answer)
        // Малый корень ≈ −1/1000000001 (Виет: x₁·x₂ = 1).
        XCTAssertEqual(second.roots.last?.preciseDouble ?? 0, -1.0 / 1_000_000_001, accuracy: 1e-18)
    }

    func testCubicWithLargeCoefficients() throws {
        // (x − 1)(x² − 1000000x + 1): рациональный корень и два иррациональных.
        let outcome = try solveEquation("x^3 - 1000001x^2 + 1000001x - 1 = 0")
        XCTAssertEqual(outcome.roots.count, 3, outcome.answer)
    }

    // MARK: - AUD-57. Неравенства: знак ≠ и модуль

    func testNotEqualInequalities() throws {
        let linear = try solveInequality("2x + 1 ≠ 5")
        XCTAssertEqual(linear.answer, "x ≠ 2")
        XCTAssertEqual(try solveInequality("x^2 ≠ 4").answer, "x ≠ −2; x ≠ 2")
        XCTAssertEqual(try solveInequality("x^2 + 1 ≠ 0").answer, "x — любое число")
        XCTAssertEqual(try solveInequality("1/x ≠ 0").answer, "x ≠ 0")
        XCTAssertEqual(try solveInequality("x - x ≠ 0").answer, "Нет решений")
    }

    func testAbsoluteValueInequalities() throws {
        XCTAssertEqual(try solveInequality("|2x - 1| < 3").answer, "−1 < x < 2, то есть x ∈ (−1; 2)")
        XCTAssertEqual(try solveInequality("|x| > 2").answer, "x ∈ (−∞; −2) ∪ (2; +∞)")
        XCTAssertEqual(try solveInequality("|x - 3| ≤ 0").answer, "x = 3")
        XCTAssertEqual(try solveInequality("|x| ≥ -1").answer, "x — любое число")
        XCTAssertEqual(try solveInequality("|x + 1| < -2").answer, "Нет решений")
        XCTAssertEqual(try solveInequality("|x| < x").answer, "Нет решений")
        XCTAssertEqual(try solveInequality("|x| ≤ x").answer, "x ≥ 0, то есть x ∈ [0; +∞)")
        XCTAssertEqual(try solveInequality("|x - 1| + |x + 1| ≤ 2").answer, "−1 ≤ x ≤ 1, то есть x ∈ [−1; 1]")
        XCTAssertEqual(try solveInequality("|x^2 - 4| < 5").answer, "−3 < x < 3, то есть x ∈ (−3; 3)")
        XCTAssertEqual(try solveInequality("sqrt(x^2) < 3").answer, "−3 < x < 3, то есть x ∈ (−3; 3)")
        XCTAssertEqual(try solveInequality("1/|x| > 1").answer, "x ∈ (−1; 0) ∪ (0; 1)")
        XCTAssertFalse(try solveInequality("|2x - 1| < 3").isApproximate)
    }

    func testAbsoluteValueInequalityThroughMathSolver() {
        let solution = MathSolver(lang: .ru).solve("Решите неравенство |2x - 1| < 3")
        XCTAssertEqual(solution?.answer, "−1 < x < 2, то есть x ∈ (−1; 2)")
        XCTAssertEqual(solution?.reliability, .exact)
    }

    // MARK: - Системы

    func testDependentLinearSystemShowsGeneralSolution() throws {
        let outcome = try solveSystem(["x + y = 2", "2x + 2y = 4"])
        XCTAssertTrue(outcome.answer.contains("бесконечно"), outcome.answer)
        XCTAssertTrue(outcome.answer.contains("y = −x + 2"), outcome.answer)
    }

    func testNonlinearSystemWithIrrationalRootsIsExact() throws {
        // x + y = 2, xy = −1 ⇒ x = 1 ± √2, y = 1 ∓ √2.
        let outcome = try solveSystem(["x + y = 2", "xy = -1"])
        XCTAssertFalse(outcome.isApproximate, outcome.answer)
        XCTAssertTrue(outcome.answer.contains("√2"), outcome.answer)
    }

    // MARK: - Существующее поведение не ломается

    func testRegularEquationsUnchanged() {
        assertExact("x^2 - 2 = 0", "x₁ = −√2 ≈ −1,41421; x₂ = √2 ≈ 1,41421")
        assertExact("2(x + 1) = 2x + 2", "x — любое число")
        assertExact("2x + 3 = 2x + 5", "Нет решений")
        assertExact("x^2 = 2x", "x₁ = 0; x₂ = 2")
        // Степень > 64 Algebra не раскрывает в многочлен — корни ищутся численно, поэтому «приближённо».
        XCTAssertEqual(try? solveEquation("x^100 = 1").answer, "x₁ = −1; x₂ = 1")
        XCTAssertEqual(try? solveEquation("sin(x) = 0.5").answer, "x₁ = π/6 + 2πn, n ∈ ℤ; x₂ = 5π/6 + 2πn, n ∈ ℤ")
        XCTAssertEqual(try? solveEquation("sin(x) = 2").answer, "Действительных корней нет")
    }
}
