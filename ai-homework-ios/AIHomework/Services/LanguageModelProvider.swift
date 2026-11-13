import Foundation

/// Состояние языковой модели — показывается пользователю как есть.
struct ModelAvailability: Sendable, Equatable {
    var isAvailable: Bool
    var title: String
    var detail: String
}

enum LanguageModelError: Error, Sendable {
    case unavailable(String)
    case generationFailed(String)
    case cancelled

    func message(_ l: L10n) -> String {
        switch self {
        case .unavailable(let detail): return detail
        case .generationFailed(let detail):
            return l("Модель не смогла сформировать ответ: \(detail)", "The model could not produce an answer: \(detail)")
        case .cancelled: return l("Генерация отменена.", "Generation was cancelled.")
        }
    }
}

/// Локальная языковая модель, работающая на устройстве.
///
/// Это точка расширения: чтобы подключить новый тип моделей (другой формат, другой рантайм),
/// достаточно реализовать этот протокол и зарегистрировать провайдер в `SolveCoordinator`.
/// Сетевых провайдеров здесь нет намеренно — приложение не отправляет задания на серверы.
protocol LanguageModelProvider: Sendable {
    /// Какой механизм указывается в решении.
    var engine: SolutionEngine { get }

    func displayName(_ l: L10n) -> String

    /// Доступна ли модель прямо сейчас и почему нет.
    func availability(_ l: L10n) async -> ModelAvailability

    /// Генерация ответа. Всё выполняется на устройстве.
    func generate(instructions: String, prompt: String, maxTokens: Int) async throws -> String
}
