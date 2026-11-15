import XCTest
@testable import HomeworkEngine

final class ModelSupportTests: XCTestCase {
    func testParsesStructuredAnswer() {
        let raw = """
            **ОТВЕТ:** Столица Франции — Париж.
            ОБЪЯСНЕНИЕ: Париж является столицей с давних времён.
            Там находится правительство страны.
            ШАГИ:
            1. Вспоминаем, о какой стране идёт речь.
            2. Называем её столицу.
            """
        let solution = ModelPrompting.parse(raw, subject: .geography, engine: .appleIntelligence, lang: .ru)
        XCTAssertEqual(solution.answer, "Столица Франции — Париж.")
        XCTAssertEqual(solution.explanation, "Париж является столицей с давних времён.\nТам находится правительство страны.")
        XCTAssertEqual(solution.steps.map { $0.title }, ["Вспоминаем, о какой стране идёт речь.", "Называем её столицу."])
        XCTAssertEqual(solution.reliability, .generated)
        XCTAssertEqual(solution.engine, .appleIntelligence)
        XCTAssertTrue(solution.isSolved)
        XCTAssertFalse(solution.notes.isEmpty, "generated answers must carry a warning")
    }

    func testParsesEnglishAndUnstructuredAnswers() {
        let english = "ANSWER: 1789\nEXPLANATION: The French Revolution began in 1789.\nSTEPS:\n- Recall the date\n- State it"
        let parsed = ModelPrompting.parse(english, subject: .history, engine: .coreML, lang: .en)
        XCTAssertEqual(parsed.answer, "1789")
        XCTAssertEqual(parsed.steps.count, 2)

        let loose = ModelPrompting.parse("Это просто текст без разметки.\nВторая строка.", subject: .other, engine: .coreML, lang: .ru)
        XCTAssertEqual(loose.answer, "Это просто текст без разметки.")
        XCTAssertTrue(loose.explanation.contains("Вторая строка."))

        let empty = ModelPrompting.parse("   \n ", subject: .other, engine: .coreML, lang: .ru)
        XCTAssertFalse(empty.isSolved)
        // Слово «ответственность» не должно считаться заголовком «ответ».
        let word = ModelPrompting.parse("Ответственность — важное качество.", subject: .social, engine: .coreML, lang: .ru)
        XCTAssertEqual(word.answer, "Ответственность — важное качество.")
    }

    func testPromptContainsTaskAndHonestyRule() {
        XCTAssertTrue(ModelPrompting.prompt(problem: "Кто такой Пётр I?", subject: .history, lang: .ru).contains("Кто такой Пётр I?"))
        XCTAssertTrue(ModelPrompting.instructions(lang: .ru).contains("не выдумывай"))
        XCTAssertTrue(ModelPrompting.instructions(lang: .en).contains("Never invent"))
    }
}
