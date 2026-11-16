import SwiftUI

/// Сохраняемые настройки приложения.
struct SettingsData: Codable, Equatable, Sendable {
    enum LanguageChoice: String, Codable, CaseIterable, Sendable, Identifiable {
        case system, ru, en
        var id: String { rawValue }
    }

    enum Appearance: String, Codable, CaseIterable, Sendable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
    }

    var languageChoice: LanguageChoice = .system
    var appearance: Appearance = .system
    var hapticsEnabled = true
    /// Использовать Apple Intelligence, когда нет интернета или нейросеть по API недоступна.
    var useSystemModel = true
    /// Сохранять фотографию задания вместе с решением. Для новых установок выключено.
    var keepPhotosInHistory = false
    /// Отправлять изображение задания в нейросеть по API. По умолчанию выключено: уходит только текст.
    /// Включённое изображение уходит только в запрос решения, диспетчеру — никогда.
    var sendImagesToAPI = false
    /// Нейросеть по API: формат, адрес и модель (ключ хранится в Связке ключей).
    var apiFormat: RemoteAPIFormat = .openAI
    var apiBaseURL = ""
    var apiModel = ""

    init() {}

    private enum CodingKeys: String, CodingKey {
        case languageChoice, appearance, hapticsEnabled, useSystemModel, keepPhotosInHistory, sendImagesToAPI, apiFormat, apiBaseURL, apiModel
    }

    /// Терпимая расшифровка: новые поля не ломают настройки, сохранённые старой версией.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = SettingsData()
        languageChoice = (try? container.decodeIfPresent(LanguageChoice.self, forKey: .languageChoice)) ?? defaults.languageChoice
        appearance = (try? container.decodeIfPresent(Appearance.self, forKey: .appearance)) ?? defaults.appearance
        hapticsEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .hapticsEnabled)) ?? defaults.hapticsEnabled
        useSystemModel = (try? container.decodeIfPresent(Bool.self, forKey: .useSystemModel)) ?? defaults.useSystemModel
        keepPhotosInHistory = (try? container.decodeIfPresent(Bool.self, forKey: .keepPhotosInHistory)) ?? defaults.keepPhotosInHistory
        sendImagesToAPI = (try? container.decodeIfPresent(Bool.self, forKey: .sendImagesToAPI)) ?? defaults.sendImagesToAPI
        apiFormat = (try? container.decodeIfPresent(RemoteAPIFormat.self, forKey: .apiFormat)) ?? defaults.apiFormat
        apiBaseURL = (try? container.decodeIfPresent(String.self, forKey: .apiBaseURL)) ?? defaults.apiBaseURL
        apiModel = (try? container.decodeIfPresent(String.self, forKey: .apiModel)) ?? defaults.apiModel
    }
}

/// Настройки приложения. Хранятся только на устройстве, в `UserDefaults`; ключ API — в Связке ключей.
@MainActor
@Observable
final class AppSettings {
    var data: SettingsData

    private static let storageKey = "ai-homework.settings.v1"
    /// Пауза перед записью: при наборе адреса или ключа настройки не пишутся на каждый символ.
    static let saveDelay: Duration = .milliseconds(600)

    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var pendingKeySave: Task<Void, Never>?

    init() {
        if let stored = UserDefaults.standard.data(forKey: AppSettings.storageKey),
            let decoded = try? JSONDecoder().decode(SettingsData.self, from: stored)
        {
            data = decoded
        } else {
            data = SettingsData()
        }
        Haptics.isEnabled = data.hapticsEnabled
        // Ключ из Связки ключей читается лениво — при первом обращении, а не при запуске.
    }

    /// Немедленная запись настроек.
    func save() {
        pendingSave?.cancel()
        pendingSave = nil
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: AppSettings.storageKey)
        }
        Haptics.isEnabled = data.hapticsEnabled
    }

    /// Запись с небольшой задержкой: следующие изменения в течение `saveDelay` объединяются в одну.
    func scheduleSave() {
        Haptics.isEnabled = data.hapticsEnabled
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: AppSettings.saveDelay)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    /// Записать всё отложенное сейчас (при закрытии настроек и уходе приложения в фон).
    func flushPendingSaves() {
        if pendingSave != nil { save() }
        if pendingKeySave != nil { saveAPIKey() }
    }

    /// Язык интерфейса и объяснений.
    var language: AppLanguage {
        switch data.languageChoice {
        case .system: return AppLanguage.systemDefault()
        case .ru: return .ru
        case .en: return .en
        }
    }

    var l: L10n { L10n(language) }

    // MARK: - API key

    private static let apiKeyAccount = "api-key"
    /// Хост, для которого введён ключ: на другой адрес ключ не отправляется.
    private static let apiKeyHostAccount = "api-key-host"

    @ObservationIgnored private var isKeyLoaded = false
    @ObservationIgnored private var storedKey = ""
    @ObservationIgnored private var storedKeyHost: String?

    private func loadKeyIfNeeded() {
        guard !isKeyLoaded else { return }
        isKeyLoaded = true
        storedKey = KeychainStore.read(AppSettings.apiKeyAccount) ?? ""
        storedKeyHost = KeychainStore.read(AppSettings.apiKeyHostAccount)
    }

    /// Ключ API. Хранится в Связке ключей, в `UserDefaults` не попадает; запись — с задержкой
    /// (`saveAPIKey()` или `flushPendingSaves()` записывают сразу). Введённый ключ привязывается
    /// к текущему адресу API.
    var apiKey: String {
        get {
            access(keyPath: \.apiKey)
            loadKeyIfNeeded()
            return storedKey
        }
        set {
            loadKeyIfNeeded()
            guard newValue != storedKey else { return }
            withMutation(keyPath: \.apiKey) { storedKey = newValue }
            withMutation(keyPath: \.apiKeyHost) { storedKeyHost = currentAPIHost }
            scheduleKeySave()
        }
    }

    /// Хост, для которого сохранён ключ (`nil` — ключ ещё не привязан, например сохранён старой версией).
    var apiKeyHost: String? {
        access(keyPath: \.apiKeyHost)
        loadKeyIfNeeded()
        return storedKeyHost
    }

    /// Хост из поля «Адрес API».
    var currentAPIHost: String? {
        RemoteAPI.keyHost(from: data.apiBaseURL)
    }

    /// Ключ сохранён для другого адреса: на текущий адрес он не отправляется, пока пользователь
    /// не введёт ключ заново или явно не разрешит отправку (`bindAPIKeyToCurrentHost()`).
    var isAPIKeyBoundToOtherHost: Bool {
        guard !apiKey.trimmed.isEmpty, let bound = apiKeyHost, let current = currentAPIHost else { return false }
        return bound != current
    }

    /// Пользователь подтвердил, что ключ предназначен для нового адреса.
    func bindAPIKeyToCurrentHost() {
        guard let current = currentAPIHost else { return }
        loadKeyIfNeeded()
        withMutation(keyPath: \.apiKeyHost) { storedKeyHost = current }
        scheduleKeySave()
    }

    /// Перечитать ключ из Связки ключей.
    func loadAPIKey() {
        isKeyLoaded = false
        withMutation(keyPath: \.apiKey) {
            withMutation(keyPath: \.apiKeyHost) { loadKeyIfNeeded() }
        }
    }

    private func scheduleKeySave() {
        pendingKeySave?.cancel()
        pendingKeySave = Task { [weak self] in
            try? await Task.sleep(for: AppSettings.saveDelay)
            guard !Task.isCancelled else { return }
            self?.saveAPIKey()
        }
    }

    /// Немедленная запись ключа и его адреса в Связку ключей. `false` — запись не удалась.
    @discardableResult
    func saveAPIKey() -> Bool {
        pendingKeySave?.cancel()
        pendingKeySave = nil
        loadKeyIfNeeded()
        let keySaved = KeychainStore.write(storedKey, for: AppSettings.apiKeyAccount)
        let host = storedKey.trimmed.isEmpty ? "" : (storedKeyHost ?? "")
        let hostSaved = KeychainStore.write(host, for: AppSettings.apiKeyHostAccount)
        return keySaved && hostSaved
    }

    /// Настройки для показа и проверок (без побочных эффектов): если ключ сохранён для другого
    /// адреса, он в конфигурацию не попадает.
    var remoteConfig: RemoteAPIConfig {
        let blocked = isAPIKeyBoundToOtherHost
        return RemoteAPIConfig(
            format: data.apiFormat, baseURL: data.apiBaseURL, model: data.apiModel,
            apiKey: blocked ? "" : apiKey, keyBoundToOtherHost: blocked ? apiKeyHost : nil)
    }

    /// Настройки для настоящего запроса. Ключ без привязки (сохранённый старой версией)
    /// при первом использовании привязывается к текущему адресу.
    func remoteConfigForRequest() -> RemoteAPIConfig {
        if !apiKey.trimmed.isEmpty, apiKeyHost == nil, currentAPIHost != nil {
            bindAPIKeyToCurrentHost()
        }
        return remoteConfig
    }

    var colorScheme: ColorScheme? {
        switch data.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var locale: Locale { Locale(identifier: language.localeIdentifier) }
}
