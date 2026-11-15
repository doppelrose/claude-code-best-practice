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

/// Языковая модель: нейросеть по API пользователя или системная модель Apple Intelligence.
///
/// Это точка расширения: чтобы подключить новый тип моделей, достаточно реализовать
/// этот протокол и добавить провайдер в `SolveCoordinator.providers()`.
protocol LanguageModelProvider: Sendable {
    /// Какой механизм указывается в решении.
    var engine: SolutionEngine { get }

    func displayName(_ l: L10n) -> String

    /// Доступна ли модель прямо сейчас и почему нет.
    func availability(_ l: L10n) async -> ModelAvailability

    /// Генерация ответа. `image` — выделенный фрагмент задания в JPEG (модели без зрения его игнорируют).
    func generate(instructions: String, prompt: String, image: Data?, maxTokens: Int) async throws -> String
}
