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
    /// Сохранять фотографию задания вместе с решением.
    var keepPhotosInHistory = true
    /// Нейросеть по API: формат, адрес и модель (ключ хранится в Связке ключей).
    var apiFormat: RemoteAPIFormat = .openAI
    var apiBaseURL = ""
    var apiModel = ""

    init() {}

    private enum CodingKeys: String, CodingKey {
        case languageChoice, appearance, hapticsEnabled, useSystemModel, keepPhotosInHistory, apiFormat, apiBaseURL, apiModel
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
        apiFormat = (try? container.decodeIfPresent(RemoteAPIFormat.self, forKey: .apiFormat)) ?? defaults.apiFormat
        apiBaseURL = (try? container.decodeIfPresent(String.self, forKey: .apiBaseURL)) ?? defaults.apiBaseURL
        apiModel = (try? container.decodeIfPresent(String.self, forKey: .apiModel)) ?? defaults.apiModel
    }
}

/// Настройки приложения. Хранятся только на устройстве, в `UserDefaults`.
@MainActor
@Observable
final class AppSettings {
    var data: SettingsData

    private static let storageKey = "ai-homework.settings.v1"

    init() {
        if let stored = UserDefaults.standard.data(forKey: AppSettings.storageKey),
            let decoded = try? JSONDecoder().decode(SettingsData.self, from: stored)
        {
            data = decoded
        } else {
            data = SettingsData()
        }
        Haptics.isEnabled = data.hapticsEnabled
        loadAPIKey()
    }

    func save() {
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: AppSettings.storageKey)
        }
        Haptics.isEnabled = data.hapticsEnabled
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

    private static let apiKeyAccount = "api-key"

    /// Ключ API. Хранится в Связке ключей, в `UserDefaults` не попадает; сохраняется `saveAPIKey()`.
    var apiKey: String = ""

    func loadAPIKey() {
        apiKey = KeychainStore.read(AppSettings.apiKeyAccount) ?? ""
    }

    func saveAPIKey() {
        KeychainStore.write(apiKey, for: AppSettings.apiKeyAccount)
    }

    var remoteConfig: RemoteAPIConfig {
        RemoteAPIConfig(format: data.apiFormat, baseURL: data.apiBaseURL, model: data.apiModel, apiKey: apiKey)
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
