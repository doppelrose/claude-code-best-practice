import AppIntents
import UIKit

/// «Решить скриншот»: открывает AI Homework с изображением, чтобы сразу обвести задание.
///
/// iOS не позволяет приложению снимать экран других приложений, поэтому скриншот делает
/// приложение «Команды»: команда «Сделать снимок экрана → Решить скриншот» назначается
/// на кнопку действия. Интент живёт только в приложении (не в расширении), поэтому
/// файл сохраняется в контейнер приложения.
struct SolveScreenshotIntent: AppIntent {
    static let title: LocalizedStringResource = "Solve a screenshot"
    static var description: IntentDescription {
        IntentDescription("Opens AI Homework with an image so you can circle the task. Put it after “Take Screenshot” in a shortcut and assign the shortcut to the Action Button.")
    }
    static let openAppWhenRun = true

    /// Автоматически связывается с результатом предыдущего действия («Сделать снимок экрана»),
    /// чтобы не приходилось выбирать переменную вручную.
    @Parameter(title: "Image", inputConnectionBehavior: .connectToPreviousIntentResult)
    var image: IntentFile

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        try ScreenshotInbox.store(image.data)
        return .result()
    }
}

/// Передача скриншота из интента в интерфейс (тот же принцип, что у `QuickActionInbox`).
enum ScreenshotInbox {
    private static let flagKey = "ai-homework.pending-screenshot"

    private static var fileURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("action-button-screenshot.dat")
    }

    @MainActor
    static func store(_ data: Data) throws {
        // Скриншот может содержать личные данные: файл защищён и живёт только до чтения.
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        UserDefaults.standard.set(true, forKey: flagKey)
        NotificationCenter.default.post(name: QuickActionInbox.notification, object: nil)
    }

    /// Забирает данные скриншота (декодирует их вызывающий код, вне главного потока).
    /// Временный файл удаляется при любом исходе — в том числе «осиротевший» от прошлого запуска.
    @MainActor
    static func consume() -> Data? {
        let isPending = UserDefaults.standard.bool(forKey: flagKey)
        UserDefaults.standard.removeObject(forKey: flagKey)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        guard isPending else { return nil }
        return try? Data(contentsOf: fileURL)
    }
}
