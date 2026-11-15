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
        try data.write(to: fileURL, options: .atomic)
        UserDefaults.standard.set(true, forKey: flagKey)
        NotificationCenter.default.post(name: QuickActionInbox.notification, object: nil)
    }

    @MainActor
    static func consume() -> UIImage? {
        guard UserDefaults.standard.bool(forKey: flagKey) else { return nil }
        UserDefaults.standard.removeObject(forKey: flagKey)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }
}
