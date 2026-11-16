import SwiftData
import SwiftUI

@main
struct AIHomeworkApp: App {
    @State private var app: AppModel
    /// Хранилище истории с версионированной схемой (см. `HistoryStore.makeContainer`).
    private let container: ModelContainer

    init() {
        let store = HistoryStore.makeContainer()
        container = store.container
        let model = AppModel()
        model.isHistoryTemporary = store.isTemporary
        _app = State(initialValue: model)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(\.locale, app.settings.locale)
                .preferredColorScheme(app.settings.colorScheme)
        }
        .modelContainer(container)
    }
}
