import Foundation
import XCTest

@testable import HomeworkEngine

/// Регрессионные тесты на неверные ответы и краш из аудита (AUD-09…AUD-14, AUD-17, AUD-33,
/// AUD-57, AUD-59, AUD-60, AUD-63, AUD-99). Входы взяты из `audit/software-tester.md`
/// («Проверочные задания») и `audit/ai-ml-engineer.md` («Входы для проверочных тестов»).
///
/// Правило: лучше честный отказ, чем неверный ответ с меткой «точно».
final class MathTextRegressionTests: XCTestCase {
    private let ru = MathSolver(lang: .ru)
    private let en = MathSolver(lang: .en)

    private func solved(_ text: String, _ solver: MathSolver? = nil, file: StaticString = #filePath, line: UInt = #line) -> Solution? {
        guard let solution = (solver ?? ru).solve(text) else {
            XCTFail("no solution for: \(text)", file: file, line: line)
            return nil
        }
        XCTAssertTrue(solution.isSolved, "unsolved: \(text) — \(solution.explanation)", file: file, line: line)
        return solution
    }

    private func answer(_ text: String, _ solver: MathSolver? = nil, file: StaticString = #filePath, line: UInt = #line) -> String {
        solved(text, solver, file: file, line: line)?.answer ?? ""
    }

    /// Задание не решено «уверенно»: `nil` или честный отказ.
    private func assertRefused(_ text: String, _ solver: MathSolver? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let solution = (solver ?? ru).solve(text)
        XCTAssertFalse(solution?.isSolved ?? false, "should be refused: \(text) → \(solution?.answer ?? "")", file: file, line: line)
    }

    // MARK: - AUD-14: переполнение стека

    /// Выполняет работу в потоке со стеком 512 КБ — как у вторичных потоков iOS.
    private func onSmallStack<T: Sendable>(_ work: @escaping @Sendable () -> T) -> T? {
        let box = SmallStackBox<T>()
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            box.value = work()
            done.signal()
        }
        thread.stackSize = 512 * 1024
        thread.start()
        XCTAssertEqual(done.wait(timeout: .now() + 60), .success, "small-stack work timed out")
        return box.value
    }

    private func solveOnSmallStack(_ text: String) -> Solution? {
        onSmallStack { LocalSolverPipeline(lang: .ru).solve(text, subject: .math) } ?? nil
    }

    func testLongSumsDoNotCrashOnSmallStack() {
        for count in [300, 400] {
            let text = Array(repeating: "1", count: count).joined(separator: "+")
            let solution = solveOnSmallStack(text)
            XCTAssertEqual(solution?.answer, "\(count)", "sum of \(count) ones")
        }
        for count in [3000, 4000, 10000] {
            let text = Array(repeating: "1", count: count).joined(separator: "+")
            let solution = solveOnSmallStack(text)
            // Либо верный ответ, либо честный отказ — но не краш.
            if let solution, solution.isSolved {
                XCTAssertEqual(solution.answer, "\(count)")
            } else {
                XCTAssertEqual(solution?.reliability, .unsupported, "sum of \(count) ones")
            }
        }
    }

    func testLongDifferenceAndProductChainsOnSmallStack() {
        let difference = Array(repeating: "1", count: 400).joined(separator: "-")
        XCTAssertEqual(solveOnSmallStack(difference)?.answer, "−398")
        let mixed = (1...300).map { "\($0)" }.joined(separator: " - ")
        // 1 − 2 − 3 − … − 300 = 1 − (2 + … + 300) = 1 − 45149
        XCTAssertEqual(solveOnSmallStack(mixed)?.answer, "−45148")
        let product = Array(repeating: "1", count: 2000).joined(separator: "*")
        let solution = solveOnSmallStack(product)
        XCTAssertTrue(solution?.answer == "1" || solution?.reliability == .unsupported)
    }

    func testDeepNestingDoesNotCrashOnSmallStack() {
        let shallow = String(repeating: "(", count: 30) + "1" + String(repeating: ")", count: 30)
        XCTAssertEqual(solveOnSmallStack(shallow)?.answer, "1")
        for depth in [200, 2000, 3000] {
            let parentheses = String(repeating: "(", count: depth) + "1" + String(repeating: ")", count: depth)
            XCTAssertEqual(solveOnSmallStack(parentheses)?.reliability, .unsupported, "parentheses \(depth)")
            let bars = String(repeating: "|", count: depth) + "1" + String(repeating: "|", count: depth)
            XCTAssertFalse(solveOnSmallStack(bars)?.isSolved ?? false, "bars \(depth)")
            let functions = String(repeating: "sin(", count: depth) + "1" + String(repeating: ")", count: depth)
            XCTAssertEqual(solveOnSmallStack(functions)?.reliability, .unsupported, "functions \(depth)")
            let minuses = String(repeating: "-", count: depth) + "1"
            XCTAssertFalse(solveOnSmallStack(minuses)?.isSolved ?? false, "unary minus \(depth)")
            let powers = Array(repeating: "1", count: depth).joined(separator: "^")
            XCTAssertFalse(solveOnSmallStack(powers)?.isSolved ?? false, "powers \(depth)")
        }
        let equation = "x" + String(repeating: " + 1", count: 300) + " = 500"
        XCTAssertEqual(solveOnSmallStack(equation)?.answer, "x = 200")
    }

    func testEvaluatorHandlesDeepTreesOnSmallStack() {
        var tree = Expr.int(1)
        for _ in 1..<3000 { tree = .bin(.add, tree, .int(1)) }
        let deep = tree
        let value = onSmallStack { try? MathEvaluator().evaluate(deep) }
        XCTAssertEqual(value ?? nil, .exact(Rational(3000)))
        let withSteps = onSmallStack { try? MathEvaluator().evaluateWithSteps(deep).steps.count }
        XCTAssertEqual(withSteps ?? nil, 2999)
        // Дерево освобождается здесь, на основном потоке (его освобождение рекурсивно — это не задача вычислителя).
        withExtendedLifetime(deep) {}
    }

    func testParserRejectsHugeInputHonestly() {
        let text = Array(repeating: "1", count: 20000).joined(separator: "+")
        XCTAssertThrowsError(try MathParser.parse(text)) { error in
            XCTAssertEqual(error as? MathError, .tooComplex)
        }
    }

    // MARK: - AUD-12, AUD-63: эвристики OCR

    func testTimesSignWithLostPowerIsQuadratic() {
        let solution = solved("2×2 − 5× + 2 = 0")
        XCTAssertEqual(solution?.answer, "x₁ = 1/2 = 0,5; x₂ = 2")
        XCTAssertEqual(solution?.reliability, .heuristic)
        XCTAssertFalse(solution?.notes.isEmpty ?? true)
    }

    func testLostPowerAfterParenthesis() {
        let solution = solved("(x+1)2 = 9")
        XCTAssertEqual(solution?.answer, "x₁ = −4; x₂ = 2")
        XCTAssertEqual(solution?.reliability, .heuristic)
        XCTAssertFalse(solution?.notes.isEmpty ?? true)
    }

    func testTimesSignStillMultipliesBetweenNumbers() {
        XCTAssertEqual(answer("3 × 4"), "12")
        XCTAssertEqual(answer("Вычислите 12 × 3"), "36")
        XCTAssertEqual(answer("2×+3×=10"), "x = 2")
        XCTAssertEqual(answer("2×x = 6"), "x = 3")
        XCTAssertEqual(answer("3×(2+1)"), "9")
        XCTAssertEqual(answer("x×x = 4"), "x₁ = −2; x₂ = 2")
        XCTAssertEqual(answer("2(x + 1) = 2x + 2"), ru.solve("2(x + 1) = 2x + 2")?.answer ?? "")
    }

    func testVariableIndicesAreNotPowers() throws {
        let statement = try MathParser.parseStatement("x1 + x2 = 5").statement
        XCTAssertEqual(statement.variables, ["x₁", "x₂"])
        let solution = ru.solve("x1 + x2 = 5, x1·x2 = 6")
        if let solution, solution.isSolved {
            XCTAssertTrue(solution.answer.contains("2") && solution.answer.contains("3"), solution.answer)
            XCTAssertFalse(solution.answer.contains("x²"))
        }
        // Одиночная «x2» по-прежнему читается как степень, с оговоркой.
        XCTAssertEqual(answer("x2 - 9 = 0"), "x₁ = −3; x₂ = 3")
    }

    // MARK: - AUD-09: номер задания

    func testTaskNumberIsNotData() {
        XCTAssertEqual(answer("3. Найдите НОД чисел 12 и 18"), "НОД = 6")
        XCTAssertEqual(answer("№ 12. Разложите на простые множители число 360"), "360 = 2³·3²·5")
        XCTAssertEqual(answer("12) Найдите НОК чисел 4 и 6"), "НОК = 12")
        XCTAssertEqual(answer("Задание 7. Найдите НОД чисел 24 и 36"), "НОД = 12")
        XCTAssertEqual(answer("№245 Найдите 20% от 150"), "30")
    }

    // MARK: - AUD-10: решена только часть задания

    func testSeparateGCDAndLCM() {
        XCTAssertEqual(answer("Найдите НОД чисел 24 и 36 и НОК чисел 8 и 12"), "НОД = 12; НОК = 24")
        XCTAssertEqual(answer("Найдите НОД и НОК чисел 12 и 18"), "НОД = 6; НОК = 36")
    }

    func testPercentChains() {
        XCTAssertEqual(answer("Найдите 20% от 50% от 400"), "40")
        XCTAssertEqual(answer("Увеличьте 200 на 15%, затем уменьшите результат на 10%"), "207")
        XCTAssertEqual(answer("Цена 200 руб. +10 %, затем −10 %. Новая цена?"), "198")
        XCTAssertEqual(answer("Цена товара 200 рублей увеличилась на 10 %, а затем уменьшилась на 10 %. Какой стала цена?"), "198")
        // Одинокий процент из текстовой задачи — честный отказ, а не «1/10».
        assertRefused("Цена 200 руб. +10 %. Новая цена?")
        // Одиночные шаблоны по-прежнему работают.
        XCTAssertEqual(answer("Увеличьте число 200 на 15%"), "230")
        XCTAssertEqual(answer("Найдите 20% от 150"), "30")
    }

    func testDerivativeAtPoint() {
        let solution = solved("Найдите значение производной функции f(x) = x^3 − 2x в точке x₀ = 2")
        XCTAssertEqual(solution?.answer, "f′(2) = 10")
        XCTAssertEqual(answer("Найдите производную функции f(x) = x^2 при x = 3"), "f′(3) = 6")
    }

    func testSeveralExpressionsAreNotExact() {
        let solution = ru.solve("Вычислите 2 + 3 и 4 · 5")
        if let solution, solution.isSolved {
            XCTAssertNotEqual(solution.reliability, .exact)
        }
    }

    // MARK: - AUD-11: задания «про функцию»

    func testFunctionTasks() {
        XCTAssertEqual(answer("Найдите нули функции f(x) = x^2 − 4x + 3"), "x₁ = 1; x₂ = 3")
        assertRefused("Постройте график функции y = 2x + 1")
        assertRefused("Найдите наибольшее значение функции y = x^2 − 4x")
        assertRefused("Исследуйте функцию f(x) = x^2 + 1 на чётность")
        assertRefused("f(x) = x^2 + 1")
    }

    // MARK: - AUD-13: определённый интеграл

    func testDefiniteIntegralBounds() {
        XCTAssertTrue(answer("Вычислите интеграл от 0 до 2 x^2 dx").hasPrefix("8/3"))
        XCTAssertEqual(answer("Вычислите интеграл от 1 до 3 x dx"), "4")
        XCTAssertEqual(answer("Вычислите интеграл функции 2x от 0 до 3"), "9")
        assertRefused("∫ 1/x dx от −1 до 1")
        XCTAssertTrue(answer("∫ 1/x dx от 1 до 2").contains("0,693"))
    }

    // MARK: - AUD-17, AUD-33, AUD-57: школьная запись чисел

    func testColonDividesFractions() {
        XCTAssertTrue(answer("2/3 : 4/9").hasPrefix("3/2"))
        XCTAssertTrue(answer("3/4 : 1/2").hasPrefix("3/2"))
        XCTAssertTrue(answer("Вычислите 2/3:4/9").hasPrefix("3/2"))
        XCTAssertEqual(answer("Найдите значение выражения (3,5 + 1,5) : 2"), "2,5")
        XCTAssertEqual(answer("12 : 4 : 3"), "1")
        XCTAssertFalse(solved("2/3 : 4/9")?.notes.isEmpty ?? true)
    }

    func testThousandsSeparators() {
        XCTAssertEqual(answer("Calculate 1,500 * 2", en), "3000")
        XCTAssertEqual(answer("Calculate 12,000,000 / 4", en), "3000000")
        XCTAssertEqual(answer("Calculate 1.5 * 2", en), "3")
        XCTAssertEqual(answer("Вычислите 1 500 · 2"), "3000")
        XCTAssertEqual(answer("1,5 + 1"), "2,5")
    }

    func testMixedNumbersAndNumberedLists() {
        XCTAssertEqual(answer("1 1/2 + 1/2"), "2")
        XCTAssertTrue(answer("2 3/4 - 3/4").hasPrefix("2"))
        let list = answer("1. 2x + 1 = 5  2. 3x - 3 = 0")
        XCTAssertTrue(list.contains("x = 2") && list.contains("x = 1"), list)
        let oneLine = answer("1) 2x+3=7 2) x^2=4")
        XCTAssertTrue(oneLine.contains("x = 2") && oneLine.contains("x₁ = −2; x₂ = 2"), oneLine)
    }

    // MARK: - AUD-59, AUD-60, AUD-99: большие числа, градусы, формат

    func testBigIntegersAreExact() {
        let power = solved("2^100")
        XCTAssertEqual(power?.answer, "1267650600228229401496703205376")
        XCTAssertEqual(power?.reliability, .exact)
        XCTAssertEqual(answer("3^40"), "12157665459056928801")
        XCTAssertEqual(answer("10^20 + 1"), "100000000000000000001")
        XCTAssertEqual(answer("2^64 - 2^64"), "0")
        XCTAssertTrue(answer("2^1000").hasPrefix("10715086071862673209484250490600018105614048117055336074437503883703510511249361"))
        XCTAssertFalse(ru.solve("2^(2^30)")?.isSolved ?? false)
        XCTAssertFalse(ru.solve("999999^999999")?.isSolved ?? false)
    }

    func testSineOfRoundNumberMentionsDegrees() {
        let solution = solved("sin(30)")
        XCTAssertTrue(solution?.notes.contains { $0.contains("1/2") && $0.contains("°") } ?? false, "\(solution?.notes ?? [])")
        XCTAssertEqual(answer("cos(60°)"), "1/2 = 0,5")
    }

    func testScientificNotationIsNormalized() {
        let fmt = MathFormatter(lang: .ru)
        XCTAssertEqual(fmt.approx(9.999999999e98), "10⁹⁹")
        XCTAssertEqual(fmt.approx(-9.9999999e20), "−10²¹")
        XCTAssertEqual(fmt.approx(1.5e30), "1,5·10³⁰")
        XCTAssertFalse(answer("99999999999^9").contains("10·10"))
    }
}

/// Результат работы из потока с маленьким стеком (запись и чтение разделены семафором).
private final class SmallStackBox<T>: @unchecked Sendable {
    var value: T?
}
