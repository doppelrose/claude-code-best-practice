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

    /// Синтетический tokenizer.json: все 256 байтов + несколько слияний и служебный токен.
    private func makeTokenizer() throws -> BPETokenizer {
        var vocabulary: [String: Int] = [:]
        var printable: [Int] = Array(33...126) + Array(161...172) + Array(174...255)
        var mapped = printable
        var extra = 0
        for byte in 0..<256 where !printable.contains(byte) {
            printable.append(byte)
            mapped.append(256 + extra)
            extra += 1
        }
        for value in mapped {
            vocabulary[String(Character(Unicode.Scalar(value)!))] = vocabulary.count
        }
        let merges = ["h e", "l l", "he ll", "hell o", "Ġ w", "Ġw o"]
        for merge in merges {
            vocabulary[merge.replacingOccurrences(of: " ", with: "")] = vocabulary.count
        }
        let eot = vocabulary.count
        let root: [String: Any] = [
            "model": ["type": "BPE", "vocab": vocabulary, "merges": merges],
            "added_tokens": [["id": eot, "content": "<|eot|>", "special": true]],
        ]
        return try BPETokenizer(json: try JSONSerialization.data(withJSONObject: root))
    }

    func testTokenizerRoundTrip() throws {
        let tokenizer = try makeTokenizer()
        let hello = tokenizer.encode("hello world")
        // «hello» сливается в один токен, « wo» — в один, «r», «l», «d» остаются байтами.
        XCTAssertEqual(hello.count, 5)
        XCTAssertEqual(tokenizer.decode(hello), "hello world")

        for text in ["Привет, мир! 2 + 2 = 4", "x² − 5x + 6 = 0", "line one\nline two", "emoji 🙂 ok"] {
            XCTAssertEqual(tokenizer.decode(tokenizer.encode(text)), text)
        }
        let withSpecial = tokenizer.encode("hello<|eot|>")
        XCTAssertEqual(withSpecial.last, tokenizer.tokenID(for: "<|eot|>"))
        XCTAssertTrue(tokenizer.isSpecial(withSpecial.last ?? -1))
        XCTAssertEqual(tokenizer.decode(withSpecial), "hello")
        XCTAssertEqual(tokenizer.decode(withSpecial, skipSpecialTokens: false), "hello<|eot|>")
    }

    func testTokenizerRejectsUnsupportedFiles() {
        XCTAssertThrowsError(try BPETokenizer(json: Data("{}".utf8)))
        let unigram = try? JSONSerialization.data(withJSONObject: ["model": ["type": "Unigram", "vocab": [:] as [String: Int]]])
        XCTAssertThrowsError(try BPETokenizer(json: unigram ?? Data()))
    }
}
