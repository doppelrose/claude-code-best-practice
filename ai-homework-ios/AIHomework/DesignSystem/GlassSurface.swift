import SwiftUI

/// «Стеклянная» поверхность.
///
/// На iOS 26 и новее используется настоящий Liquid Glass (`glassEffect`), на iOS 17–18 —
/// максимально близкая замена на системных материалах: полупрозрачный фон, тонкий блик
/// по контуру и мягкая тень.
struct GlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    var tint: Color?
    var interactive = false
    var shadow = true

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                content.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
            } else {
                fallback(content)
            }
        #else
            fallback(content)
        #endif
    }

    private func fallback(_ content: Content) -> some View {
        content
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay { shape.fill((tint ?? Color.clear).opacity(0.16)) }
                    .overlay {
                        shape.strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.55), Color.white.opacity(0.08), Color.white.opacity(0.22)],
                                startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 0.8)
                    }
                    .shadow(color: Color.black.opacity(shadow ? 0.12 : 0), radius: 18, x: 0, y: 10)
            }
    }
}

extension View {
    /// Стеклянная карточка со скруглёнными углами.
    func glassCard(cornerRadius: CGFloat = Theme.cardRadius, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassSurface(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), tint: tint, interactive: interactive))
    }

    /// Стеклянная «капсула» — для чипов и плавающих панелей.
    func glassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassSurface(shape: Capsule(style: .continuous), tint: tint, interactive: interactive))
    }

    /// Стеклянный круг — для кнопок-иконок.
    func glassCircle(tint: Color? = nil, interactive: Bool = true) -> some View {
        modifier(GlassSurface(shape: Circle(), tint: tint, interactive: interactive))
    }

    /// Непрозрачная карточка контента (текст решения читается лучше на плотном фоне).
    func contentCard(cornerRadius: CGFloat = Theme.cardRadius) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 6)
        }
    }
}

/// Группа стеклянных элементов: на iOS 26 они «сливаются» при сближении, как в системных панелях.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: spacing) { content() }
            } else {
                content()
            }
        #else
            content()
        #endif
    }
}
