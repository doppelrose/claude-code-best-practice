import SwiftUI

@main
struct AIHomeworkApp: App {
    var body: some Scene {
        WindowGroup {
            Text(MathSolver(lang: .ru).solve("2x + 5 = 11")?.answer ?? "—")
        }
    }
}
