import SwiftUI

/// Поверхность по дизайн-системе Linear: плоская заливка на ступень светлее фона,
/// тонкая рамка 1 pt и едва заметный блик по верхнему краю. Без теней и размытия.
///
/// Названия модификаторов (`glassCard`, `glassCapsule`, `glassCircle`) остались от прежнего
/// дизайна, чтобы не переписывать все экраны; теперь они рисуют плоские поверхности.
struct SurfaceStyle<S: InsettableShape>: ViewModifier {
    enum Level {
        case one, two, three

        var fill: Color {
            switch self {
            case .one: return Palette.surface1
            case .two: return Palette.surface2
            case .three: return Palette.surface3
            }
        }
    }

    let shape: S
    var level: Level = .one
    var strongBorder = false

    func body(content: Content) -> some View {
        content
            .background {
                shape
                    .fill(level.fill)
                    .overlay {
                        // Блик по верхнему краю — «отрисованный пиксель» на тёмной поверхности.
                        shape.strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.06), Color.white.opacity(0)],
                                startPoint: .top, endPoint: .center),
                            lineWidth: 1)
                    }
                    .overlay {
                        shape.strokeBorder(strongBorder ? Palette.hairlineStrong : Palette.hairline, lineWidth: 1)
                    }
            }
    }
}

extension View {
    /// Карточка: поверхность первого уровня, скругление 12 pt.
    /// `tint` и `interactive` оставлены для совместимости: акцентные заливки карточек в Linear запрещены.
    func glassCard(cornerRadius: CGFloat = Theme.cardRadius, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(
            SurfaceStyle(
                shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), level: .one, strongBorder: interactive))
    }

    /// Капсула — для чипов, статусов и плавающих панелей (поверхность второго уровня).
    func glassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(SurfaceStyle(shape: Capsule(style: .continuous), level: .two, strongBorder: interactive))
    }

    /// Круг — для кнопок-иконок.
    func glassCircle(tint: Color? = nil, interactive: Bool = true) -> some View {
        modifier(SurfaceStyle(shape: Circle(), level: .two))
    }

    /// Карточка контента (решение, шаги): поверхность первого уровня.
    func contentCard(cornerRadius: CGFloat = Theme.cardRadius) -> some View {
        modifier(SurfaceStyle(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), level: .one))
    }

    /// Поле ввода или вложенная панель: поверхность второго уровня.
    func insetSurface(cornerRadius: CGFloat = Theme.smallRadius) -> some View {
        modifier(SurfaceStyle(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), level: .two))
    }
}

/// Группа элементов. Раньше объединяла «жидкое стекло»; в плоском дизайне просто выводит содержимое.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
    }
}
