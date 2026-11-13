import XCTest
@testable import HomeworkEngine

/// Примеры, которые приложение предлагает на страницах предметов, должны действительно решаться.
final class CatalogExamplesTests: XCTestCase {
    private let examples: [(Subject, AppLanguage, String)] = [
        (.math, .ru, "Решите уравнение x² − 5x + 6 = 0"),
        (.math, .ru, "Решите неравенство (x + 1)/(x − 2) ≥ 0"),
        (.math, .ru, "Решите систему уравнений: x + y = 5, x − y = 1"),
        (.math, .ru, "Найдите производную функции f(x) = x·sin(x)"),
        (.math, .ru, "Упростите выражение (a + b)² − (a − b)²"),
        (.math, .ru, "Вычислите 3/4 − 1/6 + 2"),
        (.math, .en, "Solve the equation x² − 5x + 6 = 0"),
        (.math, .en, "Solve the inequality (x + 1)/(x − 2) ≥ 0"),
        (.math, .en, "Solve the system: x + y = 5, x − y = 1"),
        (.math, .en, "Find the derivative of f(x) = x·sin(x)"),
        (.math, .en, "Simplify (a + b)² − (a − b)²"),
        (.math, .en, "Calculate 3/4 − 1/6 + 2"),
        (.physics, .ru, "Автомобиль проехал 150 км за 2 ч. Найдите скорость автомобиля."),
        (.physics, .ru, "Какое количество теплоты необходимо для нагревания 2 кг воды от 20 °C до 100 °C?"),
        (.physics, .ru, "Сопротивление проводника 10 Ом, напряжение на нём 220 В. Найдите силу тока."),
        (.physics, .en, "A car travels 150 km in 2 h. Find the speed."),
        (.physics, .en, "What force is needed to accelerate a mass of 5 kg at 2 m/s^2?"),
        (.physics, .en, "Convert 72 km/h to m/s"),
        (.chemistry, .ru, "Расставьте коэффициенты: Al + HCl → AlCl3 + H2"),
        (.chemistry, .ru, "Найдите молярную массу H2SO4"),
        (.chemistry, .ru, "Найдите массовую долю кислорода в H2O"),
        (.chemistry, .ru, "Какой объём занимают 2 моль CO2?"),
        (.chemistry, .en, "Balance: Al + HCl → AlCl3 + H2"),
        (.chemistry, .en, "Find the molar mass of H2SO4"),
        (.chemistry, .en, "Find the mass percent of oxygen in H2O"),
        (.chemistry, .en, "Balance: Fe + O2 → Fe2O3"),
        (.informatics, .ru, "Переведите число 45 в двоичную систему счисления"),
        (.informatics, .ru, "Переведите 1011 из двоичной системы в десятичную"),
        (.informatics, .ru, "Сколько бит в 2 Кбайт?"),
        (.informatics, .en, "Convert 255 from decimal to hexadecimal"),
        (.informatics, .en, "Convert 1011 from binary to decimal"),
        (.informatics, .en, "How many bits are in 2 KB?"),
    ]

    func testAllExamplesAreSolvedLocally() {
        for (subject, lang, text) in examples {
            let pipeline = LocalSolverPipeline(lang: lang)
            let detected = pipeline.detectSubject(text).subject
            XCTAssertEqual(detected, subject, "subject for: \(text)")
            let solution = pipeline.solve(text, subject: subject)
            XCTAssertEqual(solution?.isSolved, true, "not solved: \(text) — \(solution?.explanation ?? "nil")")
        }
    }
}
