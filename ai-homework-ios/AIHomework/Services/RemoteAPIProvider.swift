import Foundation

/// Настройки подключения к нейросети по API (без ключа — он в Связке ключей).
struct RemoteAPIConfig: Sendable, Equatable {
    var format: RemoteAPIFormat
    var baseURL: String
    var model: String
    var apiKey: String
    /// Ключ сохранён для другого адреса API (здесь — для какого): на текущий адрес он не отправляется.
    var keyBoundToOtherHost: String? = nil

    var isComplete: Bool {
        RemoteAPI.baseURL(from: baseURL) != nil && !apiKey.trimmed.isEmpty && !model.trimmed.isEmpty
    }

    /// Хост, на который уйдут задание и ключ.
    var host: String? {
        RemoteAPI.keyHost(from: baseURL)
    }
}

/// Нейросеть по API пользователя (apimira, OpenRouter, OpenAI, Anthropic и любой совместимый сервис).
///
/// Задание (текст и, если пользователь это разрешил, выделенный фрагмент изображения) отправляется
/// только на адрес, который пользователь указал в настройках.
struct RemoteAPIProvider: LanguageModelProvider {
    let config: RemoteAPIConfig
    let engine = SolutionEngine.remoteAPI

    /// Полное решение: развёрнутый ответ модели обычно приходит за 5–30 секунд.
    static let solveTimeout: TimeInterval = 75
    /// Диспетчер отвечает одной строкой — ждать его долго незачем.
    static let routeTimeout: TimeInterval = 25
    /// Проверка подключения и список моделей.
    static let probeTimeout: TimeInterval = 20
    /// Потолок длины полного решения: школьному решению хватает с запасом (с учётом рассуждения
    /// «рассуждающих» моделей), а чужое или подложенное задание не потратит весь баланс.
    static let solveMaxTokens = 8_000

    func displayName(_ l: L10n) -> String {
        config.model.trimmed
    }

    func availability(_ l: L10n) async -> ModelAvailability {
        if RemoteAPI.baseURL(from: config.baseURL) == nil {
            return ModelAvailability(isAvailable: false, title: l("Не указан адрес API", "API address not set"), detail: RemoteAPIError.invalidBaseURL.message(l))
        }
        if let boundHost = config.keyBoundToOtherHost {
            return ModelAvailability(
                isAvailable: false, title: l("Ключ сохранён для другого адреса", "The key belongs to another address"),
                detail: l(
                    "Ключ API был сохранён для \(boundHost). Чтобы он не ушёл на чужой сервер, на новый адрес он не отправляется: введите ключ заново в «Настройки → Нейросеть по API».",
                    "The API key was saved for \(boundHost). So that it does not leak to another server, it is not sent to the new address: enter the key again in Settings → AI model via API."))
        }
        if config.apiKey.trimmed.isEmpty {
            return ModelAvailability(isAvailable: false, title: l("Не указан ключ", "API key not set"), detail: RemoteAPIError.missingKey.message(l))
        }
        if config.model.trimmed.isEmpty {
            return ModelAvailability(isAvailable: false, title: l("Не выбрана модель", "Model not set"), detail: RemoteAPIError.missingModel.message(l))
        }
        let host = config.host ?? config.baseURL.trimmed
        return ModelAvailability(
            isAvailable: true, title: l("Настроено", "Configured"),
            detail: l(
                "Текст задания отправляется на \(host). Модель «\(config.model.trimmed)» сначала решает, кому его отдать: точному решателю на iPhone или решить самой. Изображение уходит только если в настройках включено «Отправлять изображение в нейросеть».",
                "The task text is sent to \(host). The model “\(config.model.trimmed)” first decides who solves it: the exact on-device solver or the model itself. The image is sent only if “Send the image to the AI model” is on in Settings."))
    }

    /// Полное решение. Лимит — `solveMaxTokens` (переданный `maxTokens` для API не используется:
    /// обрезанное на полуслове решение хуже долгого). Если сервис отвергает лимит (HTTP 400),
    /// запрос повторяется без него.
    func generate(instructions: String, prompt: String, image: Data?, maxTokens: Int) async throws -> String {
        try await complete(
            instructions: instructions, prompt: prompt, image: image, maxTokens: Self.solveMaxTokens,
            timeout: Self.solveTimeout, retryEmptyWithoutLimit: false)
    }

    /// Нейросеть-диспетчер: решает, отдать задание точному решателю или решать по API.
    /// `nil` — модель ответила, но не по формату.
    func route(text: String, subjectHint: Subject, image: Data?, lang: AppLanguage) async throws -> TaskRoute? {
        let raw = try await complete(
            instructions: TaskRouting.instructions(lang: lang),
            prompt: TaskRouting.prompt(text: text, subjectHint: subjectHint, hasImage: image != nil, lang: lang),
            image: image, maxTokens: TaskRouting.maxTokens, timeout: Self.routeTimeout, retryEmptyWithoutLimit: true)
        return TaskRouting.parse(raw)
    }

    /// Запрос с лимитом токенов и одной повторной попыткой без лимита, если сервис его отверг
    /// или «рассуждающая» модель израсходовала лимит и вернула пустой ответ. Обе попытки
    /// укладываются в общий `timeout`.
    private func complete(
        instructions: String, prompt: String, image: Data?, maxTokens: Int, timeout: TimeInterval, retryEmptyWithoutLimit: Bool
    ) async throws -> String {
        let started = Date()
        do {
            return try await completeOnce(instructions: instructions, prompt: prompt, image: image, maxTokens: maxTokens, timeout: timeout)
        } catch let error as RemoteAPIError where RemoteAPI.shouldRetryWithoutTokenLimit(error, retryEmptyResponse: retryEmptyWithoutLimit) {
            let remaining = timeout - Date().timeIntervalSince(started)
            guard remaining > 3 else { throw error }
            return try await completeOnce(instructions: instructions, prompt: prompt, image: image, maxTokens: nil, timeout: remaining)
        }
    }

    private func completeOnce(
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

    /// Своя сессия вместо `URLSession.shared`: без кэша ответов и cookies на диске,
    /// а редирект на другой хост запрещён — заголовок с ключом не уйдёт постороннему серверу.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCredentialStorage = nil
        return URLSession(configuration: configuration, delegate: RedirectGuard(), delegateQueue: nil)
    }()

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
            (data, response) = try await session.data(for: urlRequest)
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
            // Сервисы иногда возвращают в ошибке фрагмент ключа — прячем его сразу.
            let message = RemoteAPI.redactingSecrets(RemoteAPI.errorMessage(data: data), secrets: RemoteAPI.secrets(in: request))
            throw RemoteAPIError.http(status: http.statusCode, message: String(message.prefix(300)))
        }
        return data
    }
}

/// Разрешает редирект только в пределах того же адреса (схема, хост, порт).
/// Отклонённый редирект возвращается как ответ 3xx и показывается как ошибка сервера.
private final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard let original = task.originalRequest?.url, let target = request.url,
            RemoteAPI.allowsRedirect(from: original, to: target)
        else { return nil }
        return request
    }
}
