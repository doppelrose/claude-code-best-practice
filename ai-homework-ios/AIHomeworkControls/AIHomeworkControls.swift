import AppIntents
import SwiftUI
import WidgetKit

/// Элементы управления (iOS 18+). Их можно поставить в Пункт управления, на экран блокировки
/// и напрямую назначить на кнопку действия: «Настройки → Кнопка действия → Элемент управления».
@main
struct AIHomeworkControlsBundle: WidgetBundle {
    var body: some Widget {
        SolveHomeworkControl()
        ScanHomeworkControl()
    }
}

struct SolveHomeworkControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.example.aihomework.controls.camera") {
            ControlWidgetButton(action: SolveHomeworkIntent(action: .camera)) {
                Label("Solve homework", systemImage: "camera.viewfinder")
            }
        }
        .displayName("Solve homework")
        .description("Opens the camera to snap a homework task.")
    }
}

struct ScanHomeworkControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.example.aihomework.controls.scan") {
            ControlWidgetButton(action: SolveHomeworkIntent(action: .scan)) {
                Label("Scan homework", systemImage: "doc.viewfinder")
            }
        }
        .displayName("Scan homework")
        .description("Opens the document scanner for a homework page.")
    }
}
