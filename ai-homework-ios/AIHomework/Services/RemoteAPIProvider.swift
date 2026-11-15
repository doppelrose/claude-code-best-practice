import Foundation

/// Настройки подключения к нейросети по API (без ключа — он в Связке ключей).
struct RemoteAPIConfig: Sendable, Equatable {
    var format: RemoteAPIFormat
    var baseURL: String
    var model: String
    var apiKey: String

    var isComplete: Bool {
        RemoteAPI.baseURL(from: baseURL) != nil && !apiKey.trimmed.isEmpty && !model.trimmed.isEmpty
    }
}

/// Нейросеть по API пользователя (apimira, OpenRouter, OpenAI, Anthropic и любой совместимый сервис).
///
/// Задание (текст и выделенный фрагмент изображения) отправляется только на адрес,
/// который пользователь указал в настройках.
struct RemoteAPIProvider: LanguageModelProvider {
    let config: RemoteAPIConfig
    let engine = SolutionEngine.remoteAPI

    /// Решение длинной задачи может занять больше минуты.
    private static let timeout: TimeInterval = 180

    func displayName(_ l: L10n) -> String {
        config.model.trimmed
    }

    func availability(_ l: L10n) async -> ModelAvailability {
        if RemoteAPI.baseURL(from: config.baseURL) == nil {
            return ModelAvailability(isAvailable: false, title: l("Не указан адрес API", "API address not set"), detail: RemoteAPIError.invalidBaseURL.message(l))
        }
        if config.apiKey.trimmed.isEmpty {
            return ModelAvailability(isAvailable: false, title: l("Не указан ключ", "API key not set"), detail: RemoteAPIError.missingKey.message(l))
        }
        if config.model.trimmed.isEmpty {
            return ModelAvailability(isAvailable: false, title: l("Не выбрана модель", "Model not set"), detail: RemoteAPIError.missingModel.message(l))
        }
        return ModelAvailability(
            isAvailable: true, title: l("Настроено", "Configured"),
            detail: l("Задания, которые не решаются точными алгоритмами, отправляются в модель «\(config.model.trimmed)».", "Tasks that the exact algorithms cannot solve are sent to “\(config.model.trimmed)”."))
    }

    func generate(instructions: String, prompt: String, image: Data?, maxTokens: Int) async throws -> String {
        let request = try RemoteAPI.chatRequest(
            format: config.format, baseURL: config.baseURL, apiKey: config.apiKey, model: config.model,
            instructions: instructions, prompt: prompt, imageJPEG: image)
        let data = try await RemoteAPIProvider.send(request)
        return try RemoteAPI.parseChatResponse(format: config.format, data: data)
    }

    /// Проверка подключения и список моделей.
    static func fetchModels(_ config: RemoteAPIConfig) async throws -> [String] {
        let request = try RemoteAPI.modelsRequest(format: config.format, baseURL: config.baseURL, apiKey: config.apiKey)
        return RemoteAPI.parseModels(data: try await send(request))
    }

    /// Сетевые сбои, после которых запрос имеет смысл повторить: оборванное соединение
    /// (часто после переключения VPN или сети), сброс или недоступность хоста.
    private static let retryableCodes: [URLError.Code] = [
        .networkConnectionLost, .cannotConnectToHost, .secureConnectionFailed, .dnsLookupFailed, .cannotFindHost,
    ]

    static func send(_ request: RemoteAPIRequest) async throws -> Data {
        var attempt = 0
        while true {
            do {
                return try await sendOnce(request)
            } catch let error as URLError where retryableCodes.contains(error.code) && attempt < 2 {
                attempt += 1
                try? await Task.sleep(for: .milliseconds(700 * attempt))
                if Task.isCancelled { throw LanguageModelError.cancelled }
            } catch let error as URLError {
                throw RemoteAPIError.offline(error.localizedDescription)
            }
        }
    }

    private static func sendOnce(_ request: RemoteAPIRequest) async throws -> Data {
        var urlRequest = URLRequest(url: request.url, timeoutInterval: timeout)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch is CancellationError {
            throw LanguageModelError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw LanguageModelError.cancelled
        } catch let error as URLError where retryableCodes.contains(error.code) {
            // Пробрасываем как есть — `send` повторит запрос.
            throw error
        } catch {
            throw RemoteAPIError.offline(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw RemoteAPIError.malformed }
        guard (200..<300).contains(http.statusCode) else {
            throw RemoteAPIError.http(status: http.statusCode, message: String(RemoteAPI.errorMessage(data: data).prefix(300)))
        }
        return data
    }
}
