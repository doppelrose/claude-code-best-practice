import XCTest
@testable import HomeworkEngine

final class TaskRoutingTests: XCTestCase {
    func testParsesPlainJSON() throws {
        let route = try XCTUnwrap(
            TaskRouting.parse(#"{"route":"local","subject":"math","problem":"x^2 - 5x + 6 = 0","reason":"quadratic"}"#))
        XCTAssertEqual(route.target, .local)
        XCTAssertEqual(route.subject, .math)
        XCTAssertEqual(route.problem, "x^2 - 5x + 6 = 0")
    }

    func testParsesJSONWrappedInMarkdownAndText() throws {
        let raw = """
            Sure! Here is my decision:
            ```json
            {"route": "model", "subject": "history", "problem": "Назовите причины войны 1812 года", "reason": "theory"}
            ```
            """
        let route = try XCTUnwrap(TaskRouting.parse(raw))
        XCTAssertEqual(route.target, .model)
        XCTAssertEqual(route.subject, .history)
    }

    func testLocalWithoutProblemFallsBackToModel() throws {
        let route = try XCTUnwrap(TaskRouting.parse(#"{"route":"local","subject":"math","problem":"  "}"#))
        XCTAssertEqual(route.target, .model)
    }

    func testRejectsGarbage() {
        XCTAssertNil(TaskRouting.parse("I cannot help with that."))
        XCTAssertNil(TaskRouting.parse(#"{"route":"maybe"}"#))
        XCTAssertNil(TaskRouting.parse("{not json}"))
    }

    func testUnknownSubjectIsNil() throws {
        let route = try XCTUnwrap(TaskRouting.parse(#"{"route":"model","subject":"astrology","problem":"?"}"#))
        XCTAssertNil(route.subject)
    }

    func testPromptMentionsImageAndText() {
        let prompt = TaskRouting.prompt(text: "×^2 − 5× + 6 = 0", subjectHint: .math, hasImage: true, lang: .ru)
        XCTAssertTrue(prompt.contains("attached image"))
        XCTAssertTrue(prompt.contains("×^2"))
        XCTAssertTrue(prompt.contains("Russian"))
    }

    /// Записи, которые диспетчер получает в инструкции как образец, должны решаться точным решателем.
    func testRouterStyleRewritesAreSolvedLocally() {
        let cases: [(Subject, AppLanguage, String)] = [
            (.math, .ru, "x^2 - 5x + 6 = 0"),
            (.math, .ru, "sqrt(16)"),
            (.math, .ru, "3/4 - 1/6 + 2"),
            (.math, .ru, "(x+1)/(x-2) >= 0"),
            (.math, .ru, "x + y = 5, x - y = 1"),
            (.math, .ru, "derivative of x*sin(x)"),
            (.math, .ru, "simplify (a+b)^2 - (a-b)^2"),
            (.math, .en, "2x + 3 = 11"),
            (.physics, .ru, "Автомобиль проехал 150 км за 2 ч. Найдите скорость."),
            (.chemistry, .en, "Balance: Al + HCl -> AlCl3 + H2"),
            (.chemistry, .ru, "Найдите молярную массу H2SO4"),
            (.informatics, .ru, "Переведите число 45 в двоичную систему счисления"),
        ]
        for (subject, lang, text) in cases {
            let solution = LocalSolverPipeline(lang: lang).solve(text, subject: subject)
            XCTAssertEqual(solution?.isSolved, true, "Not solved locally: \(text)")
        }
    }

    func testOpenAIRequestCarriesTokenLimitWhenGiven() throws {
        let request = try RemoteAPI.chatRequest(
            format: .openAI, baseURL: "https://api.example.com/v1", apiKey: "k", model: "m",
            instructions: "i", prompt: "p", imageJPEG: nil, maxTokens: TaskRouting.maxTokens)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body ?? Data()) as? [String: Any])
        XCTAssertEqual(body["max_tokens"] as? Int, TaskRouting.maxTokens)

        let plain = try RemoteAPI.chatRequest(
            format: .openAI, baseURL: "https://api.example.com/v1", apiKey: "k", model: "m",
            instructions: "i", prompt: "p", imageJPEG: nil)
        let plainBody = try XCTUnwrap(JSONSerialization.jsonObject(with: plain.body ?? Data()) as? [String: Any])
        XCTAssertNil(plainBody["max_tokens"])
    }
}
