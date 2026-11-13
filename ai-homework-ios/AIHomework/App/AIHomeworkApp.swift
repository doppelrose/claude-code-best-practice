import SwiftData
import SwiftUI

@main
struct AIHomeworkApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(\.locale, app.settings.locale)
                .preferredColorScheme(app.settings.colorScheme)
        }
        .modelContainer(for: SolvedProblem.self)
    }
}
