import XCTest
@testable import HomeworkEngine

final class MathSolverTests: XCTestCase {
    private let ru = MathSolver(lang: .ru)
    private let en = MathSolver(lang: .en)

    private func answer(_ text: String, file: StaticString = #filePath, line: UInt = #line) -> String {
        guard let solution = ru.solve(text) else {
            XCTFail("no solution for: \(text)", file: file, line: line)
            return ""
        }
        XCTAssertTrue(solution.isSolved, "unsolved: \(text) — \(solution.explanation)", file: file, line: line)
        return solution.answer
    }

    func testExtraction() {
        XCTAssertEqual(MathTextExtractor.fragments(in: "Решите уравнение: 2х + 5 = 11."), ["2x + 5 = 11"])
        XCTAssertEqual(MathTextExtractor.fragments(in: "Solve for x: 3x - 7 = 11"), ["x", "3x - 7 = 11"])
        XCTAssertEqual(MathTextExtractor.fragments(in: "Решите систему уравнений: x + y = 5, x − y = 1"), ["x + y = 5", "x - y = 1"])
        XCTAssertEqual(MathTextExtractor.fragments(in: "У Маши 5 яблок, а у Пети на 3 больше.").filter { $0.count > 1 }, [])
        XCTAssertEqual(MathTextExtractor.fragments(in: "5) Вычислите (3,5 + 1,5) : 2"), ["(3,5 + 1,5) / 2"])
    }

    func testRussianTasks() {
        XCTAssertEqual(answer("Решите уравнение: 2х + 5 = 11."), "x = 3")
        XCTAssertEqual(answer("Решите уравнение x² − 5x + 6 = 0."), "x₁ = 2; x₂ = 3")
        XCTAssertEqual(answer("Решите уравнение х2 - 5х + 6 = 0"), "x₁ = 2; x₂ = 3")
        XCTAssertEqual(answer("Вычислите: 2 + 2 · 2"), "6")
        XCTAssertEqual(answer("Найдите значение выражения (3,5 + 1,5) : 2"), "2,5")
        XCTAssertEqual(answer("Решите систему уравнений: x + y = 5, x − y = 1"), "x = 3; y = 2")
        XCTAssertEqual(answer("Решите систему уравнений\n{ 2x + 3y = 12\n{ x − y = 1"), "x = 3; y = 2")
        XCTAssertEqual(answer("Решите неравенство 2x − 3 > 5"), "x > 4, то есть x ∈ (4; +∞)")
        XCTAssertEqual(answer("Найдите производную функции f(x) = 3x² + 2x − 1"), "f′(x) = 6x + 2")
        XCTAssertEqual(answer("Упростите выражение (a + b)² − (a − b)²"), "4ab")
        XCTAssertEqual(answer("Разложите на множители x² − 9"), "(x + 3)(x − 3)")
        XCTAssertEqual(answer("Найдите 20% от 150"), "30")
        XCTAssertEqual(answer("Сколько процентов составляет 15 от 60?"), "25%")
        XCTAssertEqual(answer("Увеличьте число 200 на 15%"), "230")
        XCTAssertEqual(answer("Найдите число, 20% которого равны 30"), "150")
        XCTAssertEqual(answer("Найдите НОД и НОК чисел 12 и 18"), "НОД = 6; НОК = 36")
        XCTAssertEqual(answer("Разложите число 360 на простые множители"), "360 = 2³·3²·5")
        XCTAssertEqual(answer("1/2 + 1/3"), "5/6 ≈ 0,833333")
        XCTAssertEqual(answer("Найдите значение выражения 2x + 3 при x = 5"), "13")
        XCTAssertEqual(answer("sin 30° + cos 60° ="), "1")
        XCTAssertEqual(answer("Решите неравенство −3 ≤ 2x + 1 < 7"), "−2 ≤ x < 3, то есть x ∈ [−2; 3)")
        XCTAssertEqual(answer("Вычислите интеграл ∫ (3x² + 2x) dx"), "x³ + x² + C")
        XCTAssertEqual(answer("Вычислите интеграл функции 2x от 0 до 3"), "9")
        XCTAssertEqual(answer("Сократите дробь (x² − 1)/(x − 1)"), "x + 1")
        XCTAssertEqual(answer("Верно ли равенство 2 + 2 = 5"), "Неверно: 4 < 5")
    }

    func testEnglishTasks() {
        XCTAssertEqual(en.solve("Solve for x: 3x - 7 = 11")?.answer, "x = 6")
        XCTAssertEqual(en.solve("What is 15% of 200?")?.answer, "30")
        XCTAssertEqual(en.solve("Simplify (x + 2)(x - 2)")?.answer, "x² − 4")
        XCTAssertEqual(en.solve("Find the derivative of x^3 + 2x")?.answer, "f′(x) = 3x² + 2")
        XCTAssertEqual(en.solve("Calculate 12.5 * 4")?.answer, "50")
        XCTAssertEqual(en.solve("Find the GCD of 48 and 36")?.answer, "GCD = 12")
    }

    func testHonestFailures() {
        // Текстовая задача — движок не притворяется, что решил.
        XCTAssertNil(ru.solve("У Маши 5 яблок, а у Пети на 3 больше. Сколько яблок у Пети?"))
        XCTAssertNil(ru.solve("Кто написал роман «Война и мир»?"))
        XCTAssertNil(en.solve("Who discovered America?"))
        // Синтаксическая ошибка — честное сообщение, а не выдуманный ответ.
        let broken = ru.solve("Вычислите 2 + * 3")
        XCTAssertEqual(broken?.isSolved, false)
        XCTAssertEqual(broken?.reliability, .unsupported)
        let division = ru.solve("Вычислите 5 : (3 − 3)")
        XCTAssertEqual(division?.isSolved, false)
        XCTAssertTrue(division?.explanation.contains("ноль") ?? false)
    }

    func testPrintSamples() {
        for text in ["Решите уравнение x² − 3x + 1 = 0", "Решите неравенство (x + 1)/(x − 2) ≥ 0", "Найдите производную функции y = x·sin(x)", "Вычислите 3/4 − 1/6 + 2"] {
            guard let s = ru.solve(text) else { continue }
            print("\n=== \(text)\n" + s.plainText(problem: text, L10n(.ru)))
        }
    }
}
