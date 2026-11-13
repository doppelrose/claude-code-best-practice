import SwiftUI

extension Color {
    /// Цвет из шестнадцатеричной записи `0xRRGGBB`.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity)
    }
}

/// Общие параметры оформления.
enum Theme {
    static let cardRadius: CGFloat = 26
    static let smallRadius: CGFloat = 16
    static let screenPadding: CGFloat = 20

    /// Фирменный градиент: индиго → фиолетовый → розовый.
    static let brand = [Color(hex: 0x4F46E5), Color(hex: 0x8B5CF6), Color(hex: 0xEC4899)]
    static let orb = [
        Color(hex: 0x38BDF8), Color(hex: 0x6366F1), Color(hex: 0xA855F7), Color(hex: 0xEC4899), Color(hex: 0xFB923C), Color(hex: 0x38BDF8),
    ]

    static var brandGradient: LinearGradient {
        LinearGradient(colors: brand, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Основная пружина интерфейса: быстрая, с лёгким отскоком.
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.82)
    static let bouncy = Animation.spring(response: 0.38, dampingFraction: 0.68)
    static let gentle = Animation.spring(response: 0.6, dampingFraction: 0.9)
}

extension Subject {
    /// Пара цветов предмета для градиентов и акцентов.
    var palette: [Color] {
        switch self {
        case .math: return [Color(hex: 0x5B5BF7), Color(hex: 0xA855F7)]
        case .physics: return [Color(hex: 0x2563EB), Color(hex: 0x22D3EE)]
        case .chemistry: return [Color(hex: 0x059669), Color(hex: 0x34D399)]
        case .russian: return [Color(hex: 0xF43F5E), Color(hex: 0xFB923C)]
        case .english: return [Color(hex: 0x0EA5E9), Color(hex: 0x6366F1)]
        case .history: return [Color(hex: 0xD97706), Color(hex: 0xFBBF24)]
        case .social: return [Color(hex: 0xC026D3), Color(hex: 0xEC4899)]
        case .biology: return [Color(hex: 0x65A30D), Color(hex: 0x22C55E)]
        case .geography: return [Color(hex: 0x0D9488), Color(hex: 0x3B82F6)]
        case .literature: return [Color(hex: 0x7C3AED), Color(hex: 0xF472B6)]
        case .informatics: return [Color(hex: 0x475569), Color(hex: 0x06B6D4)]
        case .other: return [Color(hex: 0x8B5CF6), Color(hex: 0xEC4899)]
        }
    }

    var tint: Color { palette[0] }

    var gradient: LinearGradient {
        LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension SolutionReliability {
    var color: Color {
        switch self {
        case .exact: return Color(hex: 0x16A34A)
        case .approximate: return Color(hex: 0xEA580C)
        case .heuristic: return Color(hex: 0xCA8A04)
        case .generated: return Color(hex: 0x7C3AED)
        case .toolsOnly: return Color(hex: 0x0284C7)
        case .unsupported: return Color(hex: 0x64748B)
        }
    }

    var symbolName: String {
        switch self {
        case .exact: return "checkmark.seal.fill"
        case .approximate: return "plusminus.circle.fill"
        case .heuristic: return "eye.fill"
        case .generated: return "sparkles"
        case .toolsOnly: return "wrench.and.screwdriver.fill"
        case .unsupported: return "exclamationmark.triangle.fill"
        }
    }

    func title(_ l: L10n) -> String {
        switch self {
        case .exact: return l("Точное решение", "Exact solution")
        case .approximate: return l("Приближённо", "Approximate")
        case .heuristic: return l("Проверьте «Дано»", "Check “Given”")
        case .generated: return l("Сгенерировано моделью", "Model-generated")
        case .toolsOnly: return l("Только анализ текста", "Text analysis only")
        case .unsupported: return l("Не решено", "Not solved")
        }
    }

    func detail(_ l: L10n) -> String {
        switch self {
        case .exact:
            return l("Вычислено точным алгоритмом на устройстве и проверено.", "Computed by an exact on-device algorithm and verified.")
        case .approximate:
            return l("Часть значений найдена численно — ответ приближённый.", "Some values were found numerically — the answer is approximate.")
        case .heuristic:
            return l(
                "Вычисления точные, но условие понято автоматически. Сверьте блок «Дано» с задачей.",
                "The computation is exact, but the task was interpreted automatically. Compare “Given” with the problem.")
        case .generated:
            return l("Текст создан языковой моделью на устройстве и может содержать ошибки.", "The text was written by an on-device language model and may contain mistakes.")
        case .toolsOnly:
            return l("Готового ответа нет — показаны результаты локального анализа текста.", "There is no ready answer — on-device text analysis results are shown.")
        case .unsupported:
            return l("Приложение не стало выдумывать ответ.", "The app did not make an answer up.")
        }
    }
}

extension SolutionEngine {
    func title(_ l: L10n) -> String {
        switch self {
        case .math: return l("Математический движок", "Math engine")
        case .physics: return l("Физический решатель", "Physics solver")
        case .chemistry: return l("Химический решатель", "Chemistry solver")
        case .informatics: return l("Решатель по информатике", "Computer science solver")
        case .languageTools: return l("Анализ текста", "Text analysis")
        case .appleIntelligence: return "Apple Intelligence"
        case .coreML: return l("Модель Core ML", "Core ML model")
        case .none: return l("Без решателя", "No solver")
        }
    }
}
