import UIKit

/// Тактильная обратная связь. Отключается в настройках.
@MainActor
enum Haptics {
    static var isEnabled = true

    /// Лёгкое касание — обычные кнопки.
    static func tap() {
        impact(.light)
    }

    /// Более выраженный отклик — главные действия.
    static func press() {
        impact(.medium)
    }

    static func soft() {
        impact(.soft)
    }

    static func selection() {
        guard isEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        notify(.success)
    }

    static func warning() {
        notify(.warning)
    }

    static func error() {
        notify(.error)
    }

    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    private static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}
