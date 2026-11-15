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

    /// Полное решение: развёрнутый ответ модели обычно приходит за 5–30 секунд.
    static let solveTimeout: TimeInterval = 75
    /// Диспетчер отвечает одной строкой — ждать его долго незачем.
    static let routeTimeout: TimeInterval = 25
    /// Проверка подключения и список моделей.
    static let probeTimeout: TimeInterval = 20

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
            detail: l(
                "Модель «\(config.model.trimmed)» читает задание и решает, кому его отдать: точному решателю на iPhone или решить самой.",
                "“\(config.model.trimmed)” reads the task and decides who solves it: the exact on-device solver or the model itself."))
    }

    func generate(instructions: String, prompt: String, image: Data?, maxTokens: Int) async throws -> String {
        // Лимит токенов для полного решения не ставим: обрезанное на полуслове решение хуже долгого.
        try await complete(instructions: instructions, prompt: prompt, image: image, maxTokens: nil, timeout: Self.solveTimeout)
    }

    /// Нейросеть-диспетчер: решает, отдать задание точному решателю или решать по API.
    /// `nil` — модель ответила, но не по формату.
    func route(text: String, subjectHint: Subject, image: Data?, lang: AppLanguage) async throws -> TaskRoute? {
        let raw = try await complete(
            instructions: TaskRouting.instructions(lang: lang),
            prompt: TaskRouting.prompt(text: text, subjectHint: subjectHint, hasImage: image != nil, lang: lang),
            image: image, maxTokens: TaskRouting.maxTokens, timeout: Self.routeTimeout)
        return TaskRouting.parse(raw)
    }

    private func complete(
        instructions: String, prompt: String, image: Data?, maxTokens: Int?, timeout: TimeInterval
    ) async throws -> String {
        let request = try RemoteAPI.chatRequest(
            format: config.format, baseURL: config.baseURL, apiKey: config.apiKey, model: config.model,
            instructions: instructions, prompt: prompt, imageJPEG: image, maxTokens: maxTokens)
        let data = try await RemoteAPIProvider.send(request, timeout: timeout)
        return try RemoteAPI.parseChatResponse(format: config.format, data: data)
    }

    /// Проверка подключения и список моделей.
    static func fetchModels(_ config: RemoteAPIConfig) async throws -> [String] {
        let request = try RemoteAPI.modelsRequest(format: config.format, baseURL: config.baseURL, apiKey: config.apiKey)
        return RemoteAPI.parseModels(data: try await send(request, timeout: probeTimeout))
    }

    /// Сетевые сбои, после которых запрос имеет смысл повторить: оборванное соединение
    /// (часто после переключения VPN или сети), сброс или недоступность хоста.
    private static let retryableCodes: [URLError.Code] = [
        .networkConnectionLost, .cannotConnectToHost, .secureConnectionFailed, .dnsLookupFailed, .cannotFindHost,
    ]

    /// Отправка с общим лимитом времени `timeout` на все попытки вместе:
    /// даже при «подвисшем» соединении ответ (или понятная ошибка) приходит вовремя.
    static func send(_ request: RemoteAPIRequest, timeout: TimeInterval) async throws -> Data {
        do {
            return try await Deadline.run(seconds: timeout) {
                var attempt = 0
                while true {
                    do {
                        return try await sendOnce(request, timeout: timeout)
                    } catch let error as URLError where retryableCodes.contains(error.code) && attempt < 1 {
                        // Одна повторная попытка после обрыва соединения (например, при переключении VPN).
                        attempt += 1
                        try await Task.sleep(for: .milliseconds(800))
                    } catch let error as URLError where error.code == .timedOut {
                        throw RemoteAPIError.timedOut
                    } catch let error as URLError {
                        throw RemoteAPIError.offline(error.localizedDescription)
                    }
                }
            }
        } catch is Deadline.Exceeded {
            throw RemoteAPIError.timedOut
        } catch is CancellationError {
            throw LanguageModelError.cancelled
        }
    }

    private static func sendOnce(_ request: RemoteAPIRequest, timeout: TimeInterval) async throws -> Data {
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
        } catch let error as URLError where retryableCodes.contains(error.code) || error.code == .timedOut {
            // Пробрасываем как есть — `send` повторит запрос или сообщит о тайм-ауте.
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
