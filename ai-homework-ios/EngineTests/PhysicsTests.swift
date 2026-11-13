import XCTest
@testable import HomeworkEngine

final class PhysicsTests: XCTestCase {
    private let ru = PhysicsSolver(lang: .ru)
    private let en = PhysicsSolver(lang: .en)

    private func answer(_ text: String, file: StaticString = #filePath, line: UInt = #line) -> String {
        guard let solution = ru.solve(text) else {
            XCTFail("no solution: \(text)", file: file, line: line)
            return ""
        }
        XCTAssertTrue(solution.isSolved, "unsolved: \(text) — \(solution.explanation)", file: file, line: line)
        return solution.answer
    }

    func testMechanics() {
        XCTAssertEqual(answer("Автомобиль проехал 150 км за 2 ч. Найдите скорость автомобиля."), "v ≈ 20,83 м/с = 75 км/ч")
        XCTAssertEqual(answer("Тело массой 2 кг движется с ускорением 3 м/с². Найдите силу, действующую на тело."), "F ≈ 6 Н")
        XCTAssertEqual(answer("Какое давление оказывает сила 200 Н на площадь 0,5 м²?"), "p ≈ 400 Па")
        XCTAssertEqual(answer("Определите кинетическую энергию тела массой 4 кг, движущегося со скоростью 5 м/с."), "Eₖ ≈ 50 Дж")
        XCTAssertEqual(answer("Найдите плотность тела массой 500 г и объёмом 200 см³."), "ρ ≈ 2500 кг/м³")
        XCTAssertEqual(answer("На какой высоте потенциальная энергия тела массой 2 кг равна 98 Дж?"), "h ≈ 5 м")
        XCTAssertEqual(answer("Какую работу совершает сила 50 Н на пути 10 м?"), "A ≈ 500 Дж")
        XCTAssertEqual(answer("За какое время автомобиль, двигаясь со скоростью 20 м/с, пройдёт путь 400 м?"), "t ≈ 20 с")
    }

    func testElectricityAndHeat() {
        XCTAssertEqual(answer("Сопротивление проводника 10 Ом, напряжение на нём 220 В. Найдите силу тока."), "I ≈ 22 А")
        XCTAssertEqual(answer("Какое количество теплоты необходимо для нагревания 2 кг воды от 20 °C до 100 °C?"), "Q ≈ 672000 Дж = 672 кДж")
        XCTAssertEqual(answer("Определите мощность тока в лампе, если напряжение 220 В, а сила тока 0,5 А."), "N ≈ 110 Вт")
    }

    func testConversionAndEnglish() {
        XCTAssertEqual(answer("Переведите 72 км/ч в м/с"), "72 км/ч = 20 м/с")
        XCTAssertEqual(en.solve("A car travels 150 km in 2 h. Find the speed.")?.answer, "v ≈ 20.83 m/s = 75 km/h")
        XCTAssertEqual(en.solve("What force is needed to accelerate a mass of 5 kg at 2 m/s^2?")?.answer, "F ≈ 10 N")
    }

    func testHonesty() {
        XCTAssertNil(ru.solve("Кто открыл закон всемирного тяготения?"))
        // Данные есть, но одной формулы нет — честный отказ, а не выдуманный ответ.
        let unsolved = ru.solve("Тело массой 2 кг нагрели, сила тока была 3 А. Найдите частоту.")
        XCTAssertEqual(unsolved?.isSolved, false)
    }

    func testPrintSample() {
        let text = "Какое количество теплоты необходимо для нагревания 2 кг воды от 20 °C до 100 °C?"
        if let s = ru.solve(text) { print("\n" + s.plainText(problem: text, L10n(.ru))) }
    }
}
