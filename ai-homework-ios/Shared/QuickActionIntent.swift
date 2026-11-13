import AppIntents
import Foundation

/// Способ начать решение — выбирается в настройках кнопки действия, Команд или элемента управления.
enum QuickAction: String, AppEnum, Sendable {
    case camera
    case scan
    case photos
    case clipboard
    case type

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Input method")
    }

    static var caseDisplayRepresentations: [QuickAction: DisplayRepresentation] {
        [
            .camera: DisplayRepresentation(title: "Camera", image: .init(systemName: "camera.fill")),
            .scan: DisplayRepresentation(title: "Document scanner", image: .init(systemName: "doc.viewfinder")),
            .photos: DisplayRepresentation(title: "Photo library", image: .init(systemName: "photo.on.rectangle")),
            .clipboard: DisplayRepresentation(title: "Paste from clipboard", image: .init(systemName: "doc.on.clipboard")),
            .type: DisplayRepresentation(title: "Type the task", image: .init(systemName: "keyboard")),
        ]
    }
}

/// Открывает приложение сразу в нужном режиме. Это действие можно назначить
/// на кнопку действия iPhone: «Настройки → Кнопка действия → Команда / Элемент управления».
///
/// Файл входит и в приложение, и в расширение элементов управления: когда интент открывает
/// приложение, система выполняет его в процессе приложения.
struct SolveHomeworkIntent: AppIntent {
    static let title: LocalizedStringResource = "Solve homework"
    static var description: IntentDescription {
        IntentDescription("Opens AI Homework ready to capture a homework task.")
    }
    static let openAppWhenRun = true

    @Parameter(title: "Input method", default: .camera)
    var action: QuickAction

    init() {}

    init(action: QuickAction) {
        self.action = action
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Solve homework using \(\.$action)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickActionInbox.post(action)
        return .result()
    }
}

/// «Почтовый ящик» быстрых действий: интент кладёт запрос, приложение забирает его,
/// когда становится активным (или сразу, если оно уже открыто).
enum QuickActionInbox {
    static let notification = Notification.Name("ai-homework.quick-action")
    private static let key = "ai-homework.pending-quick-action"

    @MainActor
    static func post(_ action: QuickAction) {
        UserDefaults.standard.set(action.rawValue, forKey: key)
        NotificationCenter.default.post(name: notification, object: nil)
    }

    @MainActor
    static func consume() -> QuickAction? {
        guard let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        UserDefaults.standard.removeObject(forKey: key)
        return QuickAction(rawValue: raw)
    }
}
