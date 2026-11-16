import Foundation

/// Формат запросов к нейросети по API.
///
/// Почти все агрегаторы (apimira, OpenRouter и др.), а также OpenAI, DeepSeek и Gemini
/// принимают формат OpenAI (`/chat/completions`). Anthropic и часть агрегаторов — свой
/// формат `/messages`. Поддерживаются оба, выбор — в настройках.
enum RemoteAPIFormat: String, Codable, CaseIterable, Sendable, Identifiable {
    case openAI
    case anthropic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAI: return "OpenAI (chat/completions)"
        case .anthropic: return "Anthropic (messages)"
        }
    }
}

/// Готовый HTTP-запрос (без сетевого кода — его выполняет слой сервисов).
struct RemoteAPIRequest: Sendable {
    var url: URL
    var method: String
    var headers: [String: String]
    var body: Data?
}

enum RemoteAPIError: Error, Equatable, Sendable {
    case invalidBaseURL
    case missingKey
    case missingModel
    case http(status: Int, message: String)
    case emptyResponse
    case refusal(String)
    case malformed
    case offline(String)
    /// Сервер не ответил за отведённое время.
    case timedOut

    /// Сообщение для показа сразу (в настройках при проверке подключения): с текстом ответа сервера.
    func message(_ l: L10n) -> String {
        message(l, includeServerDetails: true)
    }

    /// Сообщение, которое можно хранить в истории и PDF: только код и наше пояснение,
    /// без сырого текста сервера (там бывают фрагменты ключа, HTML прокси и прочий мусор).
    func storedMessage(_ l: L10n) -> String {
        message(l, includeServerDetails: false)
    }

    func message(_ l: L10n, includeServerDetails: Bool) -> String {
        switch self {
        case .invalidBaseURL:
            return l(
                "Неверный адрес API. Он должен начинаться с https://, например https://api.example.com/v1.",
                "Invalid API address. It must start with https://, for example https://api.example.com/v1.")
        case .missingKey:
            return l("Не указан ключ API.", "The API key is not set.")
        case .missingModel:
            return l("Не указана модель.", "The model is not set.")
        case .http(let status, let message):
            let hint: String
            switch status {
            case 401, 403: hint = l("Проверьте ключ API.", "Check the API key.")
            case 404: hint = l("Проверьте адрес API и название модели.", "Check the API address and the model name.")
            case 402: hint = l("Похоже, на балансе закончились средства.", "The account balance may be empty.")
            case 429: hint = l("Слишком много запросов — попробуйте через минуту.", "Too many requests — try again in a minute.")
            default: hint = ""
            }
            let details = message.isEmpty || !includeServerDetails ? "" : " \(message)"
            return l("Сервер ответил ошибкой \(status).", "The server returned error \(status).") + details + (hint.isEmpty ? "" : " " + hint)
        case .emptyResponse:
            return l(
                "Нейросеть вернула пустой ответ. «Рассуждающие» модели иногда тратят весь лимит ответа на рассуждение — попробуйте ещё раз или выберите другую модель.",
                "The model returned an empty answer. Reasoning models sometimes spend the whole answer limit on reasoning — try again or choose another model.")
        case .refusal(let reason):
            return l("Нейросеть отказалась отвечать на это задание.", "The model declined to answer this task.")
                + (reason.isEmpty || !includeServerDetails ? "" : " \(reason)")
        case .malformed:
            return l("Не удалось разобрать ответ сервера. Проверьте формат API в настройках.", "Could not read the server response. Check the API format in Settings.")
        case .offline(let detail):
            return l("Нет связи с сервером API.", "Cannot reach the API server.") + (detail.isEmpty || !includeServerDetails ? "" : " \(detail)")
        case .timedOut:
            return l(
                "Нейросеть не ответила вовремя. Проверьте интернет (и что VPN не мешает соединению) и попробуйте ещё раз.",
                "The AI model did not answer in time. Check the internet connection (and that a VPN is not interfering) and try again.")
        }
    }
}

/// Построение запросов и разбор ответов для обоих форматов API.
enum RemoteAPI {
    static let anthropicVersion = "2023-06-01"
    /// Предел длины ответа для формата Anthropic (обязательное поле). Это потолок, а не расход.
    static let anthropicMaxTokens = 16_000

    /// Нормализует адрес: убирает пробелы, завершающий «/» и случайно вставленный путь метода.
    static func baseURL(from text: String) -> URL? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in ["/chat/completions", "/messages", "/models"] where value.lowercased().hasSuffix(suffix) {
            value = String(value.dropLast(suffix.count))
        }
        while value.hasSuffix("/") { value.removeLast() }
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(), let host = url.host, !host.isEmpty else {
            return nil
        }
        // Ключ нельзя отправлять открытым текстом; http допустим только для локального сервера.
        let isLocal = host == "localhost" || host == "127.0.0.1"
        guard scheme == "https" || (scheme == "http" && isLocal) else { return nil }
        return url
    }

    /// Хост, для которого сохраняется ключ: ключ уходит только на тот адрес, для которого его ввели.
    static func keyHost(from text: String) -> String? {
        baseURL(from: text)?.host?.lowercased()
    }

    /// Можно ли идти по редиректу: только в пределах того же адреса (схема, хост и порт).
    /// Иначе заголовок с ключом может уйти на посторонний сервер.
    static func allowsRedirect(from original: URL, to target: URL) -> Bool {
        guard let fromHost = original.host?.lowercased(), let toHost = target.host?.lowercased() else { return false }
        let fromScheme = original.scheme?.lowercased()
        let toScheme = target.scheme?.lowercased()
        guard fromHost == toHost, fromScheme == toScheme, toScheme == "https" || (toScheme == "http" && fromScheme == "http") else {
            return false
        }
        return effectivePort(original) == effectivePort(target)
    }

    private static func effectivePort(_ url: URL) -> Int? {
        if let port = url.port { return port }
        switch url.scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }

    /// Прячет в тексте всё, что похоже на ключ API: сам ключ и строки вида `sk-…`, `Bearer …`.
    static func redactingSecrets(_ text: String, secrets: [String] = []) -> String {
        var result = text
        for secret in secrets {
            let value = secret.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.count >= 6 else { continue }
            result = result.replacingOccurrences(of: value, with: "•••")
        }
        result = Rx.replace("\\b(sk|pk|rk)-[A-Za-z0-9_\\-]{6,}", in: result, with: "$1-•••", caseInsensitive: false)
        result = Rx.replace("(Bearer\\s+)[A-Za-z0-9._\\-]{6,}", in: result, with: "$1•••")
        return result
    }

    /// Ключ из заголовков готового запроса — чтобы не показывать его, если сервер вернул его в ошибке.
    static func secrets(in request: RemoteAPIRequest) -> [String] {
        var result: [String] = []
        for (name, value) in request.headers {
            switch name.lowercased() {
            case "authorization":
                result.append(value.hasPrefix("Bearer ") ? String(value.dropFirst("Bearer ".count)) : value)
            case "x-api-key":
                result.append(value)
            default:
                continue
            }
        }
        return result
    }

    /// Ответ ошибкой, после которой имеет смысл повторить запрос без лимита токенов:
    /// часть моделей отвергает `max_tokens` (HTTP 400), а «рассуждающие» модели
    /// могут израсходовать небольшой лимит на рассуждение и вернуть пустой ответ.
    static func shouldRetryWithoutTokenLimit(_ error: RemoteAPIError, retryEmptyResponse: Bool) -> Bool {
        switch error {
        case .http(let status, _): return status == 400
        case .emptyResponse: return retryEmptyResponse
        default: return false
        }
    }

    private static func endpoint(_ base: URL, _ path: String) -> URL {
        base.appendingPathComponent(path)
    }

    private static func headers(format: RemoteAPIFormat, apiKey: String) -> [String: String] {
        var result = ["Content-Type": "application/json", "Accept": "application/json"]
        switch format {
        case .openAI:
            result["Authorization"] = "Bearer \(apiKey)"
        case .anthropic:
            result["x-api-key"] = apiKey
            result["anthropic-version"] = anthropicVersion
        }
        return result
    }

    /// Запрос на решение задания: системная инструкция, текст и (необязательно) изображение JPEG.
    static func chatRequest(
        format: RemoteAPIFormat, baseURL text: String, apiKey: String, model: String,
        instructions: String, prompt: String, imageJPEG: Data?, maxTokens: Int? = nil
    ) throws -> RemoteAPIRequest {
        guard let base = baseURL(from: text) else { throw RemoteAPIError.invalidBaseURL }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw RemoteAPIError.missingKey }
        let modelID = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelID.isEmpty else { throw RemoteAPIError.missingModel }

        let body: [String: Any]
        let url: URL
        switch format {
        case .openAI:
            url = endpoint(base, "chat/completions")
            var content: [[String: Any]] = []
            if let imageJPEG {
                content.append([
                    "type": "image_url",
                    "image_url": ["url": "data:image/jpeg;base64," + imageJPEG.base64EncodedString()],
                ])
            }
            content.append(["type": "text", "text": prompt])
            var openAIBody: [String: Any] = [
                "model": modelID,
                "messages": [
                    ["role": "system", "content": instructions],
                    ["role": "user", "content": content],
                ],
            ]
            if let maxTokens { openAIBody["max_tokens"] = maxTokens }
            body = openAIBody
        case .anthropic:
            url = endpoint(base, "messages")
            var content: [[String: Any]] = []
            if let imageJPEG {
                content.append([
                    "type": "image",
                    "source": ["type": "base64", "media_type": "image/jpeg", "data": imageJPEG.base64EncodedString()],
                ])
            }
            content.append(["type": "text", "text": prompt])
            body = [
                "model": modelID,
                "max_tokens": maxTokens ?? anthropicMaxTokens,
                "system": instructions,
                "messages": [["role": "user", "content": content]],
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return RemoteAPIRequest(url: url, method: "POST", headers: headers(format: format, apiKey: key), body: data)
    }

    /// Запрос списка моделей (`GET /models` — одинаков в обоих форматах).
    static func modelsRequest(format: RemoteAPIFormat, baseURL text: String, apiKey: String) throws -> RemoteAPIRequest {
        guard let base = baseURL(from: text) else { throw RemoteAPIError.invalidBaseURL }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw RemoteAPIError.missingKey }
        var requestHeaders = headers(format: format, apiKey: key)
        requestHeaders["Content-Type"] = nil
        return RemoteAPIRequest(url: endpoint(base, "models"), method: "GET", headers: requestHeaders, body: nil)
    }

    /// Текст ответа модели.
    static func parseChatResponse(format: RemoteAPIFormat, data: Data) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RemoteAPIError.malformed
        }
        let text: String
        switch format {
        case .openAI:
            guard let choices = root["choices"] as? [[String: Any]], let first = choices.first,
                let message = first["message"] as? [String: Any]
            else { throw RemoteAPIError.malformed }
            if let refusal = message["refusal"] as? String, !refusal.isEmpty {
                throw RemoteAPIError.refusal(refusal)
            }
            if let string = message["content"] as? String {
                text = string
            } else if let parts = message["content"] as? [[String: Any]] {
                text = parts.compactMap { $0["text"] as? String }.joined()
            } else {
                text = ""
            }
        case .anthropic:
            if (root["stop_reason"] as? String) == "refusal" {
                let details = root["stop_details"] as? [String: Any]
                throw RemoteAPIError.refusal((details?["explanation"] as? String) ?? "")
            }
            guard let blocks = root["content"] as? [[String: Any]] else { throw RemoteAPIError.malformed }
            // Блоки размышлений (thinking) пропускаем — нужен только итоговый текст.
            text = blocks.filter { ($0["type"] as? String) == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RemoteAPIError.emptyResponse }
        return trimmed
    }

    /// Идентификаторы моделей из ответа `GET /models`.
    static func parseModels(data: Data) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let list = root["data"] as? [[String: Any]]
        else { return [] }
        return Array(Set(list.compactMap { $0["id"] as? String })).sorted()
    }

    /// Текст ошибки из тела ответа (`{"error": {"message": …}}` или `{"error": "…"}`).
    static func errorMessage(data: Data) -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(String(decoding: data.prefix(300), as: UTF8.self)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let error = root["error"] as? [String: Any], let message = error["message"] as? String { return message }
        if let error = root["error"] as? String { return error }
        if let message = root["message"] as? String { return message }
        return ""
    }
}
