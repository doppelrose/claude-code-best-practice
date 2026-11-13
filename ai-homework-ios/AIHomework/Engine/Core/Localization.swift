import Foundation

/// Язык интерфейса и объяснений. Приложение двуязычное (русский / английский),
/// причём язык можно переключать прямо в настройках, не меняя язык системы.
enum AppLanguage: String, Codable, CaseIterable, Sendable, Identifiable {
    case ru
    case en

    var id: String { rawValue }

    var localeIdentifier: String {
        switch self {
        case .ru: return "ru_RU"
        case .en: return "en_US"
        }
    }

    var decimalSeparator: String {
        switch self {
        case .ru: return ","
        case .en: return "."
        }
    }

    /// Язык по умолчанию — по первому предпочитаемому языку системы.
    static func systemDefault(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard let first = preferredLanguages.first?.lowercased() else { return .en }
        let cyrillicFamily = ["ru", "uk", "be", "kk", "ky", "tg", "uz"]
        return cyrillicFamily.contains { first.hasPrefix($0) } ? .ru : .en
    }
}

/// Лёгкая двуязычная локализация: обе версии строки лежат рядом в месте использования.
///
/// Так движок решения (который должен собираться и под Linux для тестов) не зависит
/// от бандла приложения, а объяснения генерируются на выбранном пользователем языке.
struct L10n: Sendable, Hashable {
    let lang: AppLanguage

    init(_ lang: AppLanguage) {
        self.lang = lang
    }

    func callAsFunction(_ ru: String, _ en: String) -> String {
        lang == .ru ? ru : en
    }
}
