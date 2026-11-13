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
    /// Использовать системную модель Apple Intelligence для заданий, которые не решаются алгоритмами.
    var useSystemModel = true
    /// Идентификатор выбранной пользовательской модели Core ML.
    var activeCoreMLModelID: String?
    /// Сохранять фотографию задания вместе с решением.
    var keepPhotosInHistory = true
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

    var colorScheme: ColorScheme? {
        switch data.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var locale: Locale { Locale(identifier: language.localeIdentifier) }
}
