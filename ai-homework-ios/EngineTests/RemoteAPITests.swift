import XCTest
@testable import HomeworkEngine

final class RemoteAPITests: XCTestCase {
    private func json(_ data: Data?) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(data)) as? [String: Any])
    }

    func testBaseURLNormalization() {
        XCTAssertEqual(RemoteAPI.baseURL(from: " https://api.example.com/v1/ ")?.absoluteString, "https://api.example.com/v1")
        XCTAssertEqual(RemoteAPI.baseURL(from: "https://api.example.com/v1/chat/completions")?.absoluteString, "https://api.example.com/v1")
        XCTAssertEqual(RemoteAPI.baseURL(from: "https://api.example.com/v1/messages")?.absoluteString, "https://api.example.com/v1")
        XCTAssertNil(RemoteAPI.baseURL(from: "http://api.example.com/v1"), "the key must never go over plain http")
        XCTAssertNotNil(RemoteAPI.baseURL(from: "http://localhost:8080/v1"))
        XCTAssertNil(RemoteAPI.baseURL(from: "api.example.com"))
        XCTAssertNil(RemoteAPI.baseURL(from: ""))
    }

    func testOpenAIRequestWithImage() throws {
        let image = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let request = try RemoteAPI.chatRequest(
            format: .openAI, baseURL: "https://api.example.com/v1", apiKey: " sk-test ", model: "gpt-x",
            instructions: "system text", prompt: "solve it", imageJPEG: image)
        XCTAssertEqual(request.url.absoluteString, "https://api.example.com/v1/chat/completions")
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.headers["Authorization"], "Bearer sk-test")
        XCTAssertNil(request.headers["x-api-key"])
        let body = try json(request.body)
        XCTAssertEqual(body["model"] as? String, "gpt-x")
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages[0]["role"] as? String, "system")
        XCTAssertEqual(messages[0]["content"] as? String, "system text")
        let content = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
        XCTAssertEqual(content[0]["type"] as? String, "image_url")
        let url = try XCTUnwrap((content[0]["image_url"] as? [String: Any])?["url"] as? String)
        XCTAssertEqual(url, "data:image/jpeg;base64," + image.base64EncodedString())
        XCTAssertEqual(content[1]["text"] as? String, "solve it")
    }

    func testAnthropicRequest() throws {
        let request = try RemoteAPI.chatRequest(
            format: .anthropic, baseURL: "https://api.example.com/v1", apiKey: "key", model: "claude-opus-5-5",
            instructions: "system text", prompt: "solve it", imageJPEG: Data([1, 2, 3]))
        XCTAssertEqual(request.url.absoluteString, "https://api.example.com/v1/messages")
        XCTAssertEqual(request.headers["x-api-key"], "key")
        XCTAssertEqual(request.headers["anthropic-version"], RemoteAPI.anthropicVersion)
        XCTAssertNil(request.headers["Authorization"])
        let body = try json(request.body)
        XCTAssertEqual(body["system"] as? String, "system text")
        XCTAssertEqual(body["max_tokens"] as? Int, RemoteAPI.anthropicMaxTokens)
        XCTAssertNil(body["temperature"])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
        XCTAssertEqual(content[0]["type"] as? String, "image")
        XCTAssertEqual((content[0]["source"] as? [String: Any])?["media_type"] as? String, "image/jpeg")
        XCTAssertEqual(content[1]["type"] as? String, "text")
    }

    func testRequestValidation() {
        XCTAssertThrowsError(try RemoteAPI.chatRequest(format: .openAI, baseURL: "nope", apiKey: "k", model: "m", instructions: "", prompt: "", imageJPEG: nil)) {
            XCTAssertEqual($0 as? RemoteAPIError, .invalidBaseURL)
        }
        XCTAssertThrowsError(try RemoteAPI.chatRequest(format: .openAI, baseURL: "https://a.b/v1", apiKey: " ", model: "m", instructions: "", prompt: "", imageJPEG: nil)) {
            XCTAssertEqual($0 as? RemoteAPIError, .missingKey)
        }
        XCTAssertThrowsError(try RemoteAPI.chatRequest(format: .anthropic, baseURL: "https://a.b/v1", apiKey: "k", model: "", instructions: "", prompt: "", imageJPEG: nil)) {
            XCTAssertEqual($0 as? RemoteAPIError, .missingModel)
        }
        let models = try? RemoteAPI.modelsRequest(format: .openAI, baseURL: "https://a.b/v1/", apiKey: "k")
        XCTAssertEqual(models?.url.absoluteString, "https://a.b/v1/models")
        XCTAssertEqual(models?.method, "GET")
        XCTAssertNil(models?.body)
    }

    func testParseResponses() throws {
        let openAI = Data(#"{"choices":[{"message":{"role":"assistant","content":"ОТВЕТ: 42"}}]}"#.utf8)
        XCTAssertEqual(try RemoteAPI.parseChatResponse(format: .openAI, data: openAI), "ОТВЕТ: 42")
        let parts = Data(#"{"choices":[{"message":{"content":[{"type":"text","text":"a"},{"type":"text","text":"b"}]}}]}"#.utf8)
        XCTAssertEqual(try RemoteAPI.parseChatResponse(format: .openAI, data: parts), "ab")
        let anthropic = Data(#"{"content":[{"type":"thinking","thinking":""},{"type":"text","text":"ANSWER: 7"}],"stop_reason":"end_turn"}"#.utf8)
        XCTAssertEqual(try RemoteAPI.parseChatResponse(format: .anthropic, data: anthropic), "ANSWER: 7")

        let refusal = Data(#"{"content":[],"stop_reason":"refusal","stop_details":{"type":"refusal","explanation":"no"}}"#.utf8)
        XCTAssertThrowsError(try RemoteAPI.parseChatResponse(format: .anthropic, data: refusal)) {
            XCTAssertEqual($0 as? RemoteAPIError, .refusal("no"))
        }
        let empty = Data(#"{"choices":[{"message":{"content":"  "}}]}"#.utf8)
        XCTAssertThrowsError(try RemoteAPI.parseChatResponse(format: .openAI, data: empty)) {
            XCTAssertEqual($0 as? RemoteAPIError, .emptyResponse)
        }
        XCTAssertThrowsError(try RemoteAPI.parseChatResponse(format: .openAI, data: Data("<html>".utf8))) {
            XCTAssertEqual($0 as? RemoteAPIError, .malformed)
        }
    }

    func testParseModelsAndErrors() {
        let models = Data(#"{"object":"list","data":[{"id":"gpt-x"},{"id":"claude-opus-5-5"},{"id":"gpt-x"}]}"#.utf8)
        XCTAssertEqual(RemoteAPI.parseModels(data: models), ["claude-opus-5-5", "gpt-x"])
        XCTAssertEqual(RemoteAPI.parseModels(data: Data("[]".utf8)), [])
        XCTAssertEqual(RemoteAPI.errorMessage(data: Data(#"{"error":{"message":"Invalid key"}}"#.utf8)), "Invalid key")
        XCTAssertEqual(RemoteAPI.errorMessage(data: Data(#"{"error":"bad"}"#.utf8)), "bad")
        XCTAssertEqual(RemoteAPI.errorMessage(data: Data("Bad Gateway".utf8)), "Bad Gateway")
    }

    func testImagePromptAndRemoteNote() {
        let prompt = ModelPrompting.prompt(problem: "2+2", subject: .math, lang: .ru, hasImage: true)
        XCTAssertTrue(prompt.contains("изображении"))
        XCTAssertTrue(prompt.contains("2+2"))
        XCTAssertTrue(ModelPrompting.prompt(problem: "", subject: .other, lang: .en, hasImage: true).contains("could not be recognized"))
        let solution = ModelPrompting.parse("ОТВЕТ: 4", subject: .math, engine: .remoteAPI, lang: .ru)
        XCTAssertEqual(solution.problemType, "Ответ нейросети")
        XCTAssertTrue(solution.notes.first?.contains("нейросетью") ?? false)
        XCTAssertFalse(LocalSolverPipeline(lang: .ru).limitationMessage(for: .history).notes.joined().contains("Core ML"))
    }
}
