import Foundation

#if canImport(FoundationModels)
    import FoundationModels
#endif

/// Системная языковая модель Apple Intelligence (фреймворк Foundation Models, iOS 26+).
///
/// Модель встроена в систему, работает на устройстве, не требует ключей и интернета.
/// Доступна только на устройствах с поддержкой Apple Intelligence — на остальных
/// провайдер честно сообщает, почему он недоступен.
struct AppleIntelligenceProvider: LanguageModelProvider {
    let engine = SolutionEngine.appleIntelligence

    func displayName(_ l: L10n) -> String {
        "Apple Intelligence"
    }

    func availability(_ l: L10n) async -> ModelAvailability {
        #if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                let model = SystemLanguageModel.default
                switch model.availability {
                case .available:
                    let locale = Locale(identifier: l.lang.localeIdentifier)
                    if model.supportsLocale(locale) {
                        return ModelAvailability(
                            isAvailable: true,
                            title: l("Готова к работе", "Ready"),
                            detail: l(
                                "Системная модель работает на этом устройстве и используется для заданий, которые не решаются точными алгоритмами.",
                                "The system model runs on this device and is used for tasks that the exact algorithms cannot solve."))
                    }
                    return ModelAvailability(
                        isAvailable: true,
                        title: l("Готова, но язык поддерживается не полностью", "Ready, but the language is not fully supported"),
                        detail: l(
                            "Системная модель пока официально не поддерживает русский язык. Она может отказаться отвечать или ответить хуже, чем на поддерживаемых языках — в этом случае приложение сообщит об ошибке.",
                            "The system model does not officially support this language yet. It may refuse to answer or answer worse than in supported languages — the app will report the error in that case."
                        ))
                case .unavailable(let reason):
                    switch reason {
                    case .deviceNotEligible:
                        return ModelAvailability(
                            isAvailable: false,
                            title: l("Устройство не поддерживается", "Device not supported"),
                            detail: l(
                                "Apple Intelligence работает только на iPhone 15 Pro и новее. На этом устройстве системная модель недоступна.",
                                "Apple Intelligence requires iPhone 15 Pro or newer. The system model is not available on this device."))
                    case .appleIntelligenceNotEnabled:
                        return ModelAvailability(
                            isAvailable: false,
                            title: l("Apple Intelligence выключен", "Apple Intelligence is turned off"),
                            detail: l(
                                "Включите Apple Intelligence в «Настройки → Apple Intelligence и Siri», и модель станет доступна.",
                                "Turn on Apple Intelligence in Settings → Apple Intelligence & Siri to make the model available."))
                    case .modelNotReady:
                        return ModelAvailability(
                            isAvailable: false,
                            title: l("Модель загружается", "The model is downloading"),
                            detail: l(
                                "Система ещё загружает модель. Попробуйте позже — приложение ничего не скачивает само.",
                                "The system is still downloading the model. Try again later — the app does not download anything itself."))
                    @unknown default:
                        return ModelAvailability(
                            isAvailable: false,
                            title: l("Модель недоступна", "Model unavailable"),
                            detail: l("Система сообщила, что модель сейчас недоступна.", "The system reports that the model is currently unavailable."))
                    }
                }
            }
        #endif
        return ModelAvailability(
            isAvailable: false,
            title: l("Требуется iOS 26", "Requires iOS 26"),
            detail: l(
                "Системная языковая модель появилась в iOS 26 и работает на устройствах с Apple Intelligence.",
                "The system language model was introduced in iOS 26 and runs on devices with Apple Intelligence."))
    }

    func generate(instructions: String, prompt: String, maxTokens: Int) async throws -> String {
        #if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                guard case .available = SystemLanguageModel.default.availability else {
                    throw LanguageModelError.unavailable("Apple Intelligence is unavailable")
                }
                do {
                    let session = LanguageModelSession(instructions: instructions)
                    let options = GenerationOptions(temperature: 0.3, maximumResponseTokens: maxTokens)
                    let response = try await session.respond(to: prompt, options: options)
                    return response.content
                } catch is CancellationError {
                    throw LanguageModelError.cancelled
                } catch {
                    throw LanguageModelError.generationFailed(error.localizedDescription)
                }
            }
        #endif
        throw LanguageModelError.unavailable("iOS 26 required")
    }
}
