import XCTest
@testable import HomeworkEngine

/// Регрессионные тесты на неверные ответы из аудита (химия, информатика, физика,
/// определение предмета и конвейер решателей). Правило: лучше честно не решить,
/// чем выдать неверный ответ с меткой «Точное решение».
final class SubjectsRegressionTests: XCTestCase {
    private let chem = ChemistrySolver(lang: .ru)
    private let info = InformaticsSolver(lang: .ru)
    private let physics = PhysicsSolver(lang: .ru)
    private let pipeline = LocalSolverPipeline(lang: .ru)
    private let detector = SubjectDetector()

    private func assertNotSolved(_ solution: Solution?, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotEqual(solution?.isSolved, true, "\(message): \(solution?.answer ?? "nil")", file: file, line: line)
    }

    // MARK: - AUD-05: цифра 0 вместо буквы O

    func testZeroInsteadOfLetterOIsCorrectedHeuristically() {
        let cases: [(String, String)] = [
            ("Молярная масса H2S04", "M(H₂SO₄) = 98 г/моль"),
            ("Молярная масса C02", "M(CO₂) = 44 г/моль"),
            ("Молярная масса CaC03", "M(CaCO₃) = 100 г/моль"),
            ("Молярная масса H20", "M(H₂O) = 18 г/моль"),
            ("Найдите молярную массу Fe203", "M(Fe₂O₃) = 160 г/моль"),
        ]
        for (input, expected) in cases {
            let solution = chem.solve(input)
            XCTAssertEqual(solution?.answer, expected, input)
            XCTAssertEqual(solution?.reliability, .heuristic, "OCR-исправление не может быть «точным»: \(input)")
            XCTAssertTrue(solution?.notes.contains { $0.contains("0") && $0.contains("O") } ?? false, "нет пометки об исправлении: \(input)")
        }
    }

    func testUnrecoverableZeroIsRefused() {
        assertNotSolved(chem.solve("Молярная масса NaOH0"), "NaOH0")
        // Формула с индексом, начинающимся с нуля, сама по себе не разбирается.
        XCTAssertNil(ChemicalFormulaParser.parse("S04"))
    }

    func testLegitimateFormulasWithZeroStayExact() {
        let solution = chem.solve("Молярная масса C10H22")
        XCTAssertEqual(solution?.answer, "M(C₁₀H₂₂) = 142 г/моль")
        XCTAssertEqual(solution?.reliability, .exact)
        XCTAssertEqual(chem.solve("Молярная масса H2SO4")?.reliability, .exact)
    }

    // MARK: - AUD-06: ионные уравнения

    func testIonicEquationsAreBalancedWithCharges() {
        let cases: [(String, String)] = [
            ("Cu2+ + OH- = Cu(OH)2", "Cu²⁺ + 2OH⁻ → Cu(OH)₂"),
            ("Ba2+ + SO4 2- = BaSO4", "Ba²⁺ + SO₄²⁻ → BaSO₄"),
            ("H+ + OH- = H2O", "H⁺ + OH⁻ → H₂O"),
            ("Fe3+ + OH- = Fe(OH)3", "Fe³⁺ + 3OH⁻ → Fe(OH)₃"),
            ("Ag+ + Cl- → AgCl↓", "Ag⁺ + Cl⁻ → AgCl"),
            ("Ca^2+ + CO3^2- = CaCO3", "Ca²⁺ + CO₃²⁻ → CaCO₃"),
        ]
        for (input, expected) in cases {
            let solution = chem.solve(input)
            XCTAssertEqual(solution?.answer, expected, input)
            XCTAssertFalse(solution?.answer.contains("M(") ?? false, input)
        }
    }

    func testIonsAreNotMolarMassesOfFakeSubstances() {
        for input in ["Ион Cu2+", "Cu2+ + OH-", "Ba2+ + SO4 2-"] {
            let solution = chem.solve(input)
            XCTAssertFalse(solution?.answer.contains("128") ?? false, input)
            XCTAssertFalse(solution?.answer.contains("274") ?? false, input)
            XCTAssertNotEqual(solution?.reliability, .exact, input)
        }
        XCTAssertTrue(chem.solve("Молярная масса SO4^2-")?.answer.contains("96") ?? false)
    }

    func testIonicEquationsThroughPipeline() {
        for input in ["Cu2+ + OH- = Cu(OH)2", "Ba2+ + SO4 2- = BaSO4"] {
            let subject = pipeline.detectSubject(input).subject
            XCTAssertEqual(subject, .chemistry, input)
            let solution = pipeline.solve(input, subject: subject)
            XCTAssertEqual(solution?.engine, .chemistry, input)
            XCTAssertEqual(solution?.isSolved, true, input)
        }
    }

    // MARK: - AUD-58: невозможные реакции и неверные формулы

    func testImpossibleReactionsAreFlagged() {
        for input in ["Cu + HCl = CuCl2 + H2", "Au + H2O = Au2O3 + H2", "Ag + H2SO4 = Ag2SO4 + H2"] {
            let solution = chem.solve(input)
            XCTAssertNotEqual(solution?.reliability, .exact, input)
            XCTAssertTrue(solution?.notes.contains { $0.contains("ряду активности") } ?? false, "нет предупреждения: \(input)")
        }
    }

    func testPossibleReactionsStayExact() {
        let cases: [(String, String)] = [
            ("Na + H2O = NaOH + H2", "2Na + 2H₂O → 2NaOH + H₂"),
            ("Zn + HCl = ZnCl2 + H2", "Zn + 2HCl → ZnCl₂ + H₂"),
            ("Ag + HNO3 = AgNO3 + NO + H2O", "3Ag + 4HNO₃ → 3AgNO₃ + NO + 2H₂O"),
            ("Cu + HNO3 = Cu(NO3)2 + NO2 + H2O", "Cu + 4HNO₃ → Cu(NO₃)₂ + 2NO₂ + 2H₂O"),
        ]
        for (input, expected) in cases {
            let solution = chem.solve(input)
            XCTAssertEqual(solution?.answer, expected, input)
            XCTAssertEqual(solution?.reliability, .exact, input)
        }
    }

    func testWrongFormulasAreFlagged() {
        let solution = chem.solve("Молярная масса NaCl2")
        XCTAssertNotEqual(solution?.reliability, .exact)
        XCTAssertTrue(solution?.notes.contains { $0.contains("NaCl₂") } ?? false)
        let reaction = chem.solve("Na + Cl2 = NaCl2")
        XCTAssertNotEqual(reaction?.reliability, .exact)
        for formula in ["NaCl", "Fe3O4", "CH4", "NH3", "H2O2", "Al2O3", "CaCl2", "Pb3O4", "CO", "P2O5"] {
            XCTAssertEqual(chem.solve("Молярная масса \(formula)")?.reliability, .exact, formula)
        }
    }

    // MARK: - AUD-07: ответ решателя чужого предмета

    func testGeometryIsNotAnsweredByChemistry() {
        let text = "В треугольнике ABC AB = 5, BC = 7, AC = 6. Найдите периметр."
        XCTAssertNil(chem.solve(text))
        let solution = pipeline.solve(text, subject: .math)
        XCTAssertNotEqual(solution?.engine, .chemistry)
        XCTAssertFalse(solution?.answer.contains("моль") ?? false)
        XCTAssertNil(chem.solve("Отрезок CO равен 5 см. Найдите длину отрезка AB."))
        // При явной химической постановке формулы из заглавных букв по-прежнему понимаются.
        XCTAssertEqual(chem.solve("Найдите молярную массу CO")?.answer, "M(CO) = 28 г/моль")
    }

    func testRefusalOfOwnSolverDoesNotHandOverToChemistry() {
        // Математика честно отказывает на «график функции» — химия не должна отвечать «M(BC)».
        for text in [
            "Постройте график функции y = 2x + 1 и отметьте на нём отрезок BC.",
            "Найдите наибольшее значение функции y = x^2 на отрезке AB.",
        ] {
            let solution = pipeline.solve(text, subject: .math)
            XCTAssertNotEqual(solution?.engine, .chemistry, text)
            XCTAssertFalse(solution?.answer.contains("моль") ?? false, text)
        }
    }

    func testHexNumbersAreNotChemicalFormulas() {
        let text = "Переведите FF₁₆ в восьмеричную систему"
        XCTAssertEqual(detector.detect(text).subject, .informatics)
        XCTAssertEqual(pipeline.solve(text, subject: .informatics)?.answer, "FF₁₆ = 377₈")
    }

    func testFailedChemistryIsNotOverriddenByMath() {
        for subject in [Subject.chemistry, .math, .other] {
            let solution = pipeline.solve("Fe + O2 = FeO + Fe2O3", subject: subject)
            XCTAssertEqual(solution?.engine, .chemistry, "\(subject)")
            XCTAssertNotEqual(solution?.isSolved, true, "\(subject)")
        }
    }

    func testCrossSubjectStillWorksWithStrongEvidence() {
        XCTAssertEqual(pipeline.solve("Тело массой 2 кг движется с ускорением 3 м/с². Найдите силу.", subject: .math)?.engine, .physics)
        XCTAssertEqual(pipeline.solve("H2 + O2 = H2O", subject: .other)?.engine, .chemistry)
        XCTAssertEqual(pipeline.solve("H2 + O2 = H2O", subject: .math)?.answer, "2H₂ + O₂ → 2H₂O")
    }

    // MARK: - AUD-08: знак и дробная часть в системах счисления

    func testSignedAndFractionalBaseConversion() {
        let cases: [(String, String)] = [
            ("Переведите число −5 в двоичную систему счисления", "−5₁₀ = −101₂"),
            ("Переведите -10 в двоичную систему", "−10₁₀ = −1010₂"),
            ("Переведите 0.5 в двоичную систему", "0,5₁₀ = 0,1₂"),
            ("Переведите 10,25 в двоичную систему", "10,25₁₀ = 1010,01₂"),
            ("Переведите 3.75 в двоичную систему счисления", "3,75₁₀ = 11,11₂"),
            ("Переведите 1010,1₂ в десятичную систему", "1010,1₂ = 10,5₁₀"),
            ("Переведите 0 в двоичную систему", "0₁₀ = 0₂"),
            ("Переведите число 45 в двоичную систему счисления", "45₁₀ = 101101₂"),
        ]
        for (input, expected) in cases {
            let solution = info.solve(input)
            XCTAssertEqual(solution?.answer, expected, input)
            XCTAssertEqual(solution?.reliability, .exact, input)
        }
    }

    func testInfiniteBinaryFractionIsApproximate() {
        let solution = info.solve("Переведите 0,1 в двоичную систему")
        XCTAssertEqual(solution?.reliability, .approximate)
        XCTAssertTrue(solution?.answer.hasPrefix("0,1₁₀ ≈ 0,0001100110") ?? false, solution?.answer ?? "nil")
    }

    func testSeveralNumbersAreNotPartiallyConverted() {
        assertNotSolved(info.solve("Переведите числа 45 и 17 в двоичную систему"), "два числа")
    }

    // MARK: - AUD-09: номер задания не попадает в данные

    func testTaskNumberIsIgnored() {
        XCTAssertEqual(info.solve("№ 5. Переведите число 45 в двоичную систему счисления")?.answer, "45₁₀ = 101101₂")
        XCTAssertEqual(info.solve("5. Переведите число 45 в двоичную систему счисления")?.answer, "45₁₀ = 101101₂")
        XCTAssertEqual(info.solve("Задание 3. Переведите 1011 из двоичной системы в десятичную")?.answer, "1011₂ = 11₁₀")
        XCTAssertEqual(info.solve("12) Переведите число 45 в двоичную систему счисления")?.answer, "45₁₀ = 101101₂")
        XCTAssertEqual(info.solve("№ 12. Переведите 255 в шестнадцатеричную систему")?.answer, "255₁₀ = FF₁₆")
        XCTAssertEqual(
            pipeline.solve("№ 5. Переведите число 45 в двоичную систему счисления", subject: .informatics)?.answer, "45₁₀ = 101101₂")
    }

    // MARK: - AUD-61: определение предмета

    func testSubjectDetectionForReactionsAndPrices() {
        for input in ["H2O = H2 + O3", "Cu2+ + OH- = Cu(OH)2", "Ba2+ + SO4 2- = BaSO4", "H2 + O2 = H2O + H2O2", "Fe + O2 = FeO + Fe2O3"] {
            XCTAssertEqual(detector.detect(input).subject, .chemistry, input)
        }
        XCTAssertEqual(detector.detect("Цена 200 рублей увеличилась на 10 %, затем уменьшилась на 10 %. Какой стала цена?").subject, .math)
        XCTAssertEqual(detector.detect("Стоимость товара 500 руб. Скидка 20 %. Сколько стоит товар со скидкой?").subject, .math)
        XCTAssertEqual(detector.detect("x^2 - 5x + 6 = 0").subject, .math)
        XCTAssertEqual(detector.detect("Решите уравнение 2x + 3 = 7").subject, .math)
        XCTAssertEqual(detector.detect("Скорость автомобиля увеличилась с 10 м/с до 20 м/с за 5 с. Найдите ускорение.").subject, .physics)
    }

    // MARK: - AUD-62: Δt по одной температуре

    func testTemperatureRangeWithSingleUnit() {
        let cases: [(PhysicsSolver, String, String)] = [
            (physics, "Какое количество теплоты необходимо для нагревания 2 кг воды от 20 до 100 °C?", "672 кДж"),
            (physics, "Какое количество теплоты необходимо для нагревания 2 кг воды от 20 °C до 100 °C?", "672 кДж"),
            (physics, "Сколько теплоты нужно, чтобы нагреть 2 кг воды с 20 до 100 °C?", "672 кДж"),
            (physics, "Какое количество теплоты нужно, чтобы нагреть 2 кг воды на 10 °C?", "84 кДж"),
            (PhysicsSolver(lang: .en), "How much heat is needed to warm 2 kg of water from 20 to 100 °C?", "672 kJ"),
        ]
        for (solver, input, expected) in cases {
            let answer = solver.solve(input)?.answer ?? "nil"
            XCTAssertTrue(answer.contains(expected), "\(input) → \(answer)")
        }
    }

    func testSingleAbsoluteTemperatureIsNotADifference() {
        let solution = physics.solve("Какое количество теплоты нужно, чтобы нагреть 2 кг воды до 100 °C?")
        assertNotSolved(solution, "одна конечная температура")
        XCTAssertFalse(solution?.answer.contains("840") ?? false)
        assertNotSolved(
            physics.solve("Начальная температура воды 20 °C. Сколько теплоты нужно, чтобы нагреть 2 кг воды?"), "одна начальная температура")
        XCTAssertTrue(
            physics.solve("Температура воды повысилась на 10 °C. Какое количество теплоты получили 2 кг воды?")?.answer.contains("84 кДж") ?? false)
    }

    // MARK: - AUD-18: исправленное условие не даёт «точной» метки

    func testCorrectedInputDowngradesExactLabel() {
        let exact = Solution(subject: .math, problemType: "t", answer: "x = 3", reliability: .exact, engine: .math)
        let corrected = exact.withCorrectedInput(note: "Условие переписано")
        XCTAssertEqual(corrected.reliability, .heuristic)
        XCTAssertEqual(corrected.notes.last, "Условие переписано")
        XCTAssertEqual(corrected.answer, "x = 3")

        let approximate = Solution(subject: .math, problemType: "t", answer: "x ≈ 1", reliability: .approximate, engine: .math)
        XCTAssertEqual(approximate.withCorrectedInput(note: "n").reliability, .approximate)
        let failed = Solution.unsupported(subject: .math, problemType: "t", reason: "r")
        XCTAssertEqual(failed.withCorrectedInput(note: "n").reliability, .unsupported)
    }
}
