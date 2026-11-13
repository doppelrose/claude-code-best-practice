import XCTest
@testable import HomeworkEngine

final class SubjectsTests: XCTestCase {
    private let chem = ChemistrySolver(lang: .ru)
    private let info = InformaticsSolver(lang: .ru)
    private let pipeline = LocalSolverPipeline(lang: .ru)
    private let detector = SubjectDetector()

    func testFormulaParsing() throws {
        XCTAssertEqual(ChemicalFormulaParser.parse("H2SO4")?.composition, ["H": 2, "S": 1, "O": 4])
        XCTAssertEqual(ChemicalFormulaParser.parse("Ca(OH)2")?.composition, ["Ca": 1, "O": 2, "H": 2])
        XCTAssertEqual(ChemicalFormulaParser.parse("Fe2(SO4)3")?.composition, ["Fe": 2, "S": 3, "O": 12])
        XCTAssertEqual(ChemicalFormulaParser.parse("CuSO4·5H2O")?.composition, ["Cu": 1, "S": 1, "O": 9, "H": 10])
        XCTAssertEqual(ChemicalFormulaParser.parse("H₂O")?.display, "H₂O")
        XCTAssertNil(ChemicalFormulaParser.parse("Xx2"))
        XCTAssertEqual(try ChemicalFormulaParser.parse("H2SO4")?.schoolMolarMass(), Rational(98))
        XCTAssertEqual(PeriodicTable.elements.count, 118)
    }

    func testChemistry() {
        XCTAssertEqual(chem.solve("Найдите молярную массу H2SO4")?.answer, "M(H₂SO₄) = 98 г/моль")
        XCTAssertEqual(chem.solve("Вычислите M(NaCl)")?.answer, "M(NaCl) = 58,5 г/моль")
        XCTAssertEqual(chem.solve("Молярная масса Н2О")?.answer, "M(H₂O) = 18 г/моль")
        XCTAssertEqual(chem.solve("Найдите массовую долю кислорода в H2O")?.answer, "ω(O) ≈ 88,89%")
        XCTAssertEqual(chem.solve("Расставьте коэффициенты: H2 + O2 = H2O")?.answer, "2H₂ + O₂ → 2H₂O")
        XCTAssertEqual(chem.solve("Fe + O2 → Fe2O3")?.answer, "4Fe + 3O₂ → 2Fe₂O₃")
        XCTAssertEqual(chem.solve("Уравняйте реакцию Al + HCl -> AlCl3 + H2")?.answer, "2Al + 6HCl → 2AlCl₃ + 3H₂")
        XCTAssertEqual(chem.solve("KMnO4 + HCl = KCl + MnCl2 + Cl2 + H2O")?.answer, "2KMnO₄ + 16HCl → 2KCl + 2MnCl₂ + 5Cl₂ + 8H₂O")
        XCTAssertEqual(chem.solve("Найдите количество вещества в 49 г H2SO4")?.answer, "n(H₂SO₄) ≈ 0,5 моль")
        XCTAssertEqual(chem.solve("Какая масса 2 моль NaOH?")?.answer, "m(NaOH) ≈ 80 г")
        XCTAssertEqual(chem.solve("Какой объём занимают 2 моль CO2?")?.answer, "V(CO₂) ≈ 44,8 л")
        XCTAssertEqual(chem.solve("H2 + O2 = NaCl")?.isSolved, false)
        XCTAssertNil(chem.solve("Что такое валентность?"))
    }

    func testInformatics() {
        XCTAssertEqual(info.solve("Переведите число 45 в двоичную систему счисления")?.answer, "45₁₀ = 101101₂")
        XCTAssertEqual(info.solve("Переведите 1011 из двоичной системы в десятичную")?.answer, "1011₂ = 11₁₀")
        XCTAssertEqual(info.solve("Переведите число 1F₁₆ в десятичную систему")?.answer, "1F₁₆ = 31₁₀")
        XCTAssertEqual(info.solve("Convert 255 from decimal to hexadecimal")?.answer, "255₁₀ = FF₁₆")
        XCTAssertEqual(info.solve("Переведите 777 из восьмеричной в двоичную")?.answer, "777₈ = 111111111₂")
        XCTAssertEqual(info.solve("Сколько бит в 2 Кбайт?")?.answer, "2 Кбайт = 16384 бит")
        XCTAssertEqual(info.solve("Переведите 4096 бит в байты")?.answer, "4096 бит = 512 байт")
        XCTAssertNil(info.solve("Что такое алгоритм?"))
    }

    func testSubjectDetection() {
        XCTAssertEqual(detector.detect("Решите уравнение: 2х + 5 = 11").subject, .math)
        XCTAssertEqual(detector.detect("x² − 5x + 6 = 0").subject, .math)
        XCTAssertEqual(detector.detect("Автомобиль проехал 150 км за 2 ч. Найдите скорость автомобиля.").subject, .physics)
        XCTAssertEqual(detector.detect("Расставьте коэффициенты: H2 + O2 = H2O").subject, .chemistry)
        XCTAssertEqual(detector.detect("Найдите молярную массу H2SO4").subject, .chemistry)
        XCTAssertEqual(detector.detect("Выполните морфологический разбор слова «бегущий». Определите падеж существительного.").subject, .russian)
        XCTAssertEqual(detector.detect("Put the verbs in brackets into the Present Perfect tense.").subject, .english)
        XCTAssertEqual(detector.detect("В каком году произошла Октябрьская революция? Назовите причины восстания.").subject, .history)
        XCTAssertEqual(detector.detect("Что такое инфляция и как она влияет на экономику государства?").subject, .social)
        XCTAssertEqual(detector.detect("Опишите процесс фотосинтеза в клетке растения.").subject, .biology)
        XCTAssertEqual(detector.detect("Переведите число 45 в двоичную систему счисления").subject, .informatics)
        XCTAssertEqual(detector.detect("Привет!").subject, .other)
    }

    func testPipeline() {
        XCTAssertEqual(pipeline.solve("Решите уравнение 2x + 5 = 11", subject: .math)?.answer, "x = 3")
        XCTAssertEqual(pipeline.solve("Автомобиль проехал 150 км за 2 ч. Найдите скорость.", subject: .physics)?.engine, .physics)
        XCTAssertEqual(pipeline.solve("H2 + O2 = H2O", subject: .other)?.engine, .chemistry)
        // Физическая задача при выбранной «математике» всё равно решается физическим решателем.
        XCTAssertEqual(pipeline.solve("Тело массой 2 кг движется с ускорением 3 м/с². Найдите силу.", subject: .math)?.engine, .physics)
        // Даты в гуманитарном тексте не превращаются в «пример».
        XCTAssertNil(pipeline.solve("Великая Отечественная война: 1941-1945. Назовите основные сражения.", subject: .history))
        XCTAssertNil(pipeline.solve("У Маши 5 яблок, а у Пети на 3 больше. Сколько яблок у Пети?", subject: .math))
        XCTAssertFalse(pipeline.limitationMessage(for: .history).isSolved)
    }
}
