import AppIntents

/// Готовые команды приложения. Они сразу появляются в «Командах», Spotlight, Siri
/// и в списке «Настройки → Кнопка действия → Команда» — без ручной настройки.
struct HomeworkShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SolveHomeworkIntent(action: .camera),
            phrases: [
                "Solve homework with \(.applicationName)",
                "Решить задание в \(.applicationName)",
                "Сфотографировать задание в \(.applicationName)",
            ],
            shortTitle: "Solve homework",
            systemImageName: "camera.viewfinder")
        AppShortcut(
            intent: SolveHomeworkIntent(action: .scan),
            phrases: [
                "Scan homework with \(.applicationName)",
                "Сканировать задание в \(.applicationName)",
            ],
            shortTitle: "Scan homework",
            systemImageName: "doc.viewfinder")
    }

    static var shortcutTileColor: ShortcutTileColor { .purple }
}
