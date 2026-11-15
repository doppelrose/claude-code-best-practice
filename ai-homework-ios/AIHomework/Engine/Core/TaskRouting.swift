import Foundation

/// Решение нейросети-«диспетчера»: кому отдать задание.
struct TaskRoute: Sendable, Equatable {
    enum Target: String, Sendable {
        /// Точные алгоритмы приложения на iPhone.
        case local
        /// Дальнейшее решение нейросетью по API.
        case model
    }

    var target: Target
    /// Предмет, который определила нейросеть (если узнала).
    var subject: Subject?
    /// Условие, переписанное так, чтобы его понял точный решатель (для `.local`),
    /// или очищенное от ошибок распознавания условие (для `.model`).
    var problem: String
    /// Короткое объяснение выбора — для отладки и подписи под решением.
    var reason: String
}

/// Маршрутизация: нейросеть смотрит на задание (картинку и распознанный текст) и решает,
/// справится ли с ним точный решатель приложения. Если да — переписывает условие в понятной
/// ему записи; если нет — задание уходит на полноценное решение по API.
///
/// Так нейросеть исправляет ошибки распознавания (× вместо x, потерянные степени), а сами
/// вычисления там, где это возможно, выполняет точный алгоритм — без «галлюцинаций» в арифметике.
enum TaskRouting {
    /// Небольшой лимит: диспетчер отвечает одной строкой JSON.
    static let maxTokens = 400

    static func instructions(lang: AppLanguage) -> String {
        // Инструкции на английском — модели надёжнее соблюдают формат; условие остаётся на языке ученика.
        let language = lang == .ru ? "Russian" : "English"
        return """
            You are the dispatcher of a homework-solving app. Decide who should solve the student's task:
            "local" — the app's exact on-device solver, or "model" — a full AI solution.

            The local solver can do ONLY these kinds of single tasks:
            • Math: evaluate an expression (fractions, powers, roots); solve one equation (linear, quadratic, polynomial, rational, simple radical); solve one inequality (linear, quadratic, rational); solve a system of 2–3 linear equations; find a derivative; simplify or expand an algebraic expression.
            • Physics: a one-formula problem with given numbers and units — speed/distance/time, acceleration, F = ma, weight, pressure, density, work, power, kinetic/potential energy, momentum, heat Q = cmΔt, Ohm's law, charge, spring force, frequency/period/wavelength, unit conversion.
            • Chemistry: balance a chemical equation; molar mass; mass fraction of an element; amount of substance, mass, molecules or gas volume at STP.
            • Computer science: convert a number between bases 2, 8, 10, 16; convert information units (bits, bytes, KB, MB…).

            Choose "model" for everything else: geometry, word problems that need reasoning or several steps of modelling, proofs, limits, integrals, graphs, several tasks at once, theory questions, and all humanities subjects.

            If you choose "local", rewrite the task in "problem" so the solver can parse it:
            • Math: one line of plain text, ASCII operators: x^2 - 5x + 6 = 0, sqrt(16), 3/4, (x+1)/(x-2) >= 0, 2*a. Use x as the variable unless the task names another one. A system: equations separated by commas. A derivative: "derivative of x*sin(x)". Simplification: "simplify (a+b)^2 - (a-b)^2".
            • Physics, chemistry, computer science: a short sentence in \(language) with every given value, its unit and the question, e.g. "Автомобиль проехал 150 км за 2 ч. Найдите скорость." or "Balance: Al + HCl -> AlCl3 + H2".
            If you choose "model", put the corrected task text in "problem".

            The recognized text may contain OCR mistakes (× instead of x, lost exponents, Cyrillic look-alike letters); if an image is attached, trust the image.
            Never solve the task yourself.
            Reply with ONE line of JSON and nothing else:
            {"route":"local"|"model","subject":"math|physics|chemistry|informatics|russian|english|history|social|biology|geography|literature|other","problem":"...","reason":"few words"}
            """
    }

    static func prompt(text: String, subjectHint: Subject, hasImage: Bool, lang: AppLanguage) -> String {
        let trimmed = String(text.trimmed.prefix(2_000))
        var lines: [String] = []
        lines.append("Subject guessed by the app: \(subjectHint.rawValue).")
        if hasImage {
            lines.append("The task is in the attached image.")
        }
        if trimmed.isEmpty {
            lines.append("Recognized text: (none)")
        } else {
            lines.append("Recognized text:\n\(trimmed)")
        }
        lines.append("Student's language: \(lang == .ru ? "Russian" : "English").")
        return lines.joined(separator: "\n")
    }

    /// Разбор ответа диспетчера. Терпим к Markdown-обёрткам и тексту вокруг JSON.
    /// `nil` — ответ не удалось понять (тогда приложение решает задание как обычно).
    static func parse(_ raw: String) -> TaskRoute? {
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"), start < end else { return nil }
        let json = String(raw[start...end])
        guard let data = json.data(using: .utf8),
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }

        let routeText = (object["route"] as? String)?.trimmed.lowercased() ?? ""
        let problem = (object["problem"] as? String)?.trimmed ?? ""
        let reason = (object["reason"] as? String)?.trimmed ?? ""
        let subjectText = (object["subject"] as? String)?.trimmed.lowercased() ?? ""
        let subject = Subject(rawValue: subjectText)

        let target: TaskRoute.Target
        switch routeText {
        case "local", "app", "solver", "program": target = .local
        case "model", "api", "ai", "llm": target = .model
        default: return nil
        }
        // Точному решателю нечего решать без переписанного условия.
        if target == .local, problem.isEmpty {
            return TaskRoute(target: .model, subject: subject, problem: problem, reason: reason)
        }
        return TaskRoute(target: target, subject: subject, problem: String(problem.prefix(2_000)), reason: reason)
    }
}
