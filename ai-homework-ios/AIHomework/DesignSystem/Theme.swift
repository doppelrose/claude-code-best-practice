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

extension Color {
    /// Цвет, который меняется вместе с темой: `light` — для светлой, `dark` — для тёмной.
    init(light: UInt32, dark: UInt32) {
        self.init(
            uiColor: UIColor { traits in
                let hex = traits.userInterfaceStyle == .dark ? dark : light
                return UIColor(
                    red: CGFloat((hex >> 16) & 0xFF) / 255,
                    green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255,
                    alpha: 1)
            })
    }
}

/// Цвета по дизайн-системе Linear (awesome-design-md/design-md/linear.app):
/// почти чёрное полотно, «лестница» поверхностей, тонкие рамки и единственный акцент.
enum Palette {
    /// Единственный цветной акцент — лавандово-синий. Только для главных действий, фокуса и ссылок.
    static let accent = Color(light: 0x5E6AD2, dark: 0x5E6AD2)
    static let accentHover = Color(light: 0x4F5BC4, dark: 0x828FFF)
    /// Текст на акценте.
    static let onAccent = Color.white

    static let canvas = Color(light: 0xFBFBFC, dark: 0x010102)
    static let surface1 = Color(light: 0xFFFFFF, dark: 0x0F1011)
    static let surface2 = Color(light: 0xF4F5F6, dark: 0x141516)
    static let surface3 = Color(light: 0xECEDEF, dark: 0x18191A)

    static let hairline = Color(light: 0xE6E7EA, dark: 0x23252A)
    static let hairlineStrong = Color(light: 0xD3D5DA, dark: 0x34343A)

    static let ink = Color(light: 0x08090A, dark: 0xF7F8F8)
    static let inkMuted = Color(light: 0x3C3F44, dark: 0xD0D6E0)
    static let inkSubtle = Color(light: 0x6B6F76, dark: 0x8A8F98)
    static let inkTertiary = Color(light: 0x9A9EA5, dark: 0x62666D)

    /// Единственный семантический цвет — «готово / точно».
    static let success = Color(light: 0x1F8A3A, dark: 0x27A644)
}

/// Общие параметры оформления.
enum Theme {
    /// Карточки — 12 pt, крупные панели — 16 pt, кнопки и поля — 10 pt (8 pt в Linear + запас для пальца).
    static let cardRadius: CGFloat = 12
    static let panelRadius: CGFloat = 16
    static let smallRadius: CGFloat = 10
    static let screenPadding: CGFloat = 20

    /// Наследие прежнего дизайна: везде, где раньше был градиент, теперь сплошной акцент.
    static let brand = [Palette.accent, Palette.accent]
    static let orb = [Palette.accent, Palette.accentHover, Palette.accent]

    static var brandGradient: LinearGradient {
        LinearGradient(colors: brand, startPoint: .top, endPoint: .bottom)
    }

    /// Движение: плавные пружины без отскока — элементы «доезжают», а не прыгают.
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.92)
    static let bouncy = Animation.spring(response: 0.32, dampingFraction: 0.86)
    static let gentle = Animation.spring(response: 0.55, dampingFraction: 0.95)
}

extension Font {
    /// Заголовки как в Linear: полужирный 600 и отрицательный трекинг задаются через `.tracking`.
    static let displayLarge = Font.system(size: 32, weight: .semibold)
    static let displayMedium = Font.system(size: 26, weight: .semibold)
    static let headlineTitle = Font.system(size: 20, weight: .semibold)
    static let cardTitle = Font.system(size: 17, weight: .medium)
    static let buttonLabel = Font.system(size: 15, weight: .medium)
}

extension Subject {
    /// Предметы больше не раскрашены: один акцент на всё приложение.
    var palette: [Color] { [Palette.accent, Palette.accent] }

    var tint: Color { Palette.accent }

    var gradient: LinearGradient {
        LinearGradient(colors: palette, startPoint: .top, endPoint: .bottom)
    }
}

extension SolutionReliability {
    var color: Color {
        switch self {
        case .exact: return Palette.success
        case .generated: return Palette.accent
        case .approximate, .heuristic, .toolsOnly, .unsupported: return Palette.inkSubtle
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
            return l("Текст создан нейросетью и может содержать ошибки.", "The text was written by an AI model and may contain mistakes.")
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
        case .remoteAPI: return l("Нейросеть по API", "AI model via API")
        case .none: return l("Без решателя", "No solver")
        }
    }
}
