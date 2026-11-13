import Foundation

/// Формирование запроса к локальной языковой модели и разбор её ответа.
///
/// Модель просят отвечать в простом размеченном формате (ОТВЕТ / ОБЪЯСНЕНИЕ / ШАГИ) —
/// его одинаково хорошо соблюдают и системная модель Apple, и небольшие модели Core ML.
enum ModelPrompting {
    static func instructions(lang: AppLanguage) -> String {
        switch lang {
        case .ru:
            return """
                Ты — терпеливый школьный репетитор. Объясняй простым и понятным языком, как для ученика.
                Отвечай на русском языке.
                Будь честен: если данных недостаточно, условие неясно или ты не уверен в ответе — прямо скажи об этом. Никогда не выдумывай факты, даты, имена и числа.
                Строго соблюдай формат ответа:
                ОТВЕТ: краткий итоговый ответ в одну-две строки.
                ОБЪЯСНЕНИЕ: почему ответ именно такой, 2–5 предложений.
                ШАГИ:
                1. первый шаг решения
                2. второй шаг решения
                (от 2 до 7 шагов)
                """
        case .en:
            return """
                You are a patient school tutor. Explain in simple, clear language suitable for a student.
                Answer in English.
                Be honest: if the data is insufficient, the task is unclear or you are not sure — say so directly. Never invent facts, dates, names or numbers.
                Follow this answer format strictly:
                ANSWER: a short final answer in one or two lines.
                EXPLANATION: why this is the answer, 2–5 sentences.
                STEPS:
                1. first step of the solution
                2. second step of the solution
                (between 2 and 7 steps)
                """
        }
    }

    static func prompt(problem: String, subject: Subject, lang: AppLanguage) -> String {
        let l = L10n(lang)
        let trimmed = String(problem.trimmed.prefix(2_000))
        return l(
            "Предмет: \(subject.title(l)).\nЗадание:\n\(trimmed)\n\nРеши задание и объясни решение.",
            "Subject: \(subject.title(l)).\nTask:\n\(trimmed)\n\nSolve the task and explain the solution.")
    }

    private static let answerMarkers = ["краткий ответ", "итоговый ответ", "ответ", "final answer", "answer"]
    private static let explanationMarkers = ["объяснение", "пояснение", "explanation"]
    private static let stepsMarkers = ["пошаговое решение", "шаги решения", "шаги", "решение", "step-by-step solution", "steps", "solution"]

    private enum Section {
        case answer, explanation, steps
    }

    private static func cleaned(_ line: String) -> String {
        var text = line.trimmed
        // Убираем Markdown-разметку, которую любят добавлять модели.
        for token in ["**", "__", "`"] {
            text = text.replacingOccurrences(of: token, with: "")
        }
        while text.hasPrefix("#") { text = String(text.dropFirst()).trimmed }
        return text
    }

    /// Заголовок раздела в начале строки: «ОТВЕТ: …», «Explanation -».
    private static func header(in line: String) -> (section: Section, rest: String)? {
        let lower = line.lowercased()
        let groups: [(Section, [String])] = [
            (.steps, stepsMarkers), (.explanation, explanationMarkers), (.answer, answerMarkers),
        ]
        for (section, markers) in groups {
            for marker in markers where lower.hasPrefix(marker) {
                let rest = String(line.dropFirst(marker.count)).trimmed
                // После маркера должен идти разделитель либо конец строки — иначе это обычное слово.
                if rest.isEmpty { return (section, "") }
                if let first = rest.first, ":—–-.".contains(first) {
                    return (section, String(rest.dropFirst()).trimmed)
                }
            }
        }
        return nil
    }

    /// Превращает сырой текст модели в `Solution`. Никогда не «улучшает» содержание —
    /// только раскладывает по разделам.
    static func parse(_ raw: String, subject: Subject, engine: SolutionEngine, lang: AppLanguage) -> Solution {
        let l = L10n(lang)
        var answer: [String] = []
        var explanation: [String] = []
        var steps: [SolutionStep] = []
        var preamble: [String] = []
        var current: Section?

        for rawLine in raw.components(separatedBy: .newlines) {
            let line = cleaned(rawLine)
            guard !line.isEmpty else { continue }
            if let found = header(in: line) {
                current = found.section
                guard !found.rest.isEmpty else { continue }
                switch found.section {
                case .answer: answer.append(found.rest)
                case .explanation: explanation.append(found.rest)
                case .steps: appendStep(found.rest, to: &steps)
                }
                continue
            }
            switch current {
            case .answer: answer.append(line)
            case .explanation: explanation.append(line)
            case .steps: appendStep(line, to: &steps)
            case nil: preamble.append(line)
            }
        }

        var answerText = answer.joined(separator: "\n")
        var explanationText = explanation.joined(separator: "\n")
        if answerText.isEmpty, explanationText.isEmpty, steps.isEmpty {
            // Модель не соблюла формат — показываем текст как есть.
            explanationText = preamble.joined(separator: "\n")
            answerText = preamble.first.map { String($0.prefix(240)) } ?? ""
        } else {
            if explanationText.isEmpty { explanationText = preamble.joined(separator: "\n") }
            if answerText.isEmpty { answerText = l("См. объяснение ниже", "See the explanation below") }
        }

        let note = l(
            "Ответ сгенерирован языковой моделью прямо на устройстве. Такие модели могут ошибаться — обязательно проверьте результат.",
            "The answer was generated by a language model running on this device. Such models can be wrong — always double-check the result."
        )
        guard !answerText.trimmed.isEmpty else {
            return Solution.unsupported(
                subject: subject,
                problemType: l("Ответ модели", "Model answer"),
                reason: l("Локальная модель вернула пустой ответ.", "The on-device model returned an empty answer."),
                engine: engine)
        }
        return Solution(
            subject: subject,
            problemType: l("Ответ локальной модели", "On-device model answer"),
            answer: answerText,
            explanation: explanationText,
            steps: steps,
            reliability: .generated,
            engine: engine,
            notes: [note])
    }

    /// Строка «1. текст» начинает новый шаг, остальные строки дополняют предыдущий.
    private static func appendStep(_ line: String, to steps: inout [SolutionStep]) {
        if let match = Rx.first("^(?:шаг\\s+|step\\s+)?(\\d{1,2})\\s*[.):]\\s*(.+)$", in: line) {
            steps.append(SolutionStep(match[2]))
        } else if let match = Rx.first("^[-•*]\\s+(.+)$", in: line) {
            steps.append(SolutionStep(match[1]))
        } else if var last = steps.popLast() {
            last.detail = last.detail.isEmpty ? line : last.detail + "\n" + line
            steps.append(last)
        } else {
            steps.append(SolutionStep(line))
        }
    }
}
