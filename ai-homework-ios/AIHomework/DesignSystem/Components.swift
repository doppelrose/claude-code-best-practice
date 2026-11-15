import SwiftUI

/// Заголовок раздела с необязательной кнопкой справа.
struct SectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headlineTitle)
                .tracking(-0.3)
                .foregroundStyle(Palette.ink)
            Spacer()
            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 3) {
                        Text(actionTitle)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.inkSubtle)
                }
                .buttonStyle(.pressable)
            }
        }
    }
}

/// Значок предмета: монохромная плитка с тонкой рамкой.
struct SubjectIcon: View {
    let subject: Subject
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: subject.symbolName)
            .font(.system(size: size * 0.4, weight: .medium))
            .foregroundStyle(Palette.inkMuted)
            .frame(width: size, height: size)
            .modifier(
                SurfaceStyle(shape: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous), level: .two))
    }
}

/// Монохромная плитка со значком для карточек и быстрых действий.
struct CardIcon: View {
    let systemImage: String
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .regular))
            .foregroundStyle(Palette.inkMuted)
            .frame(width: size, height: size)
            .modifier(
                SurfaceStyle(shape: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous), level: .two))
    }
}

/// Чип-фильтр. Выбранный чип «приподнят» — светлее поверхность и рамка (правило Linear),
/// невыбранный — прозрачный с тонкой рамкой. Цвет не используется.
struct FilterChip<Background: View>: View {
    let title: String
    var systemImage: String?
    let isSelected: Bool
    /// Фон выбранного чипа — сюда передают поверхность с `matchedGeometryEffect`,
    /// чтобы выделение плавно переезжало между чипами.
    @ViewBuilder var selectedBackground: () -> Background
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage).font(.caption.weight(.medium))
                }
                Text(title).font(.footnote.weight(.medium))
            }
            .foregroundStyle(isSelected ? Palette.ink : Palette.inkSubtle)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                if isSelected {
                    selectedBackground()
                } else {
                    Capsule(style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.pressable)
    }
}

extension FilterChip where Background == AnyView {
    init(title: String, systemImage: String? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.init(
            title: title, systemImage: systemImage, isSelected: isSelected,
            selectedBackground: { AnyView(ChipSelection()) }, action: action)
    }
}

/// Поверхность выбранного чипа.
struct ChipSelection: View {
    var body: some View {
        Capsule(style: .continuous)
            .fill(Palette.surface3)
            .overlay { Capsule(style: .continuous).strokeBorder(Palette.hairlineStrong, lineWidth: 1) }
    }
}

/// Метка предмета: значок и название.
struct SubjectBadge: View {
    let subject: Subject
    let l: L10n

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: subject.symbolName).font(.caption.weight(.medium))
            Text(subject.title(l)).font(.caption.weight(.medium))
        }
        .foregroundStyle(Palette.inkMuted)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassCapsule()
    }
}

/// Метка достоверности решения.
struct ReliabilityBadge: View {
    let reliability: SolutionReliability
    let l: L10n

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: reliability.symbolName).font(.caption.weight(.medium))
                .foregroundStyle(reliability.color)
            Text(reliability.title(l)).font(.caption.weight(.medium))
                .foregroundStyle(Palette.inkMuted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassCapsule()
    }
}

/// Блок с формулой: моноширинный шрифт, вложенная поверхность, текст можно выделить.
struct FormulaBlock: View {
    let text: String
    /// Оставлено для совместимости: формулы больше не тонируются.
    var tint: Color = Palette.accent
    var emphasized = false

    var body: some View {
        Text(text)
            .font(.system(emphasized ? .title3 : .callout, design: .monospaced).weight(emphasized ? .semibold : .medium))
            .lineSpacing(4)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .insetSurface()
    }
}

/// Раскладка «чипов» с переносом на новую строку.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width.isFinite ? width : maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Всплывающее сообщение внизу экрана.
struct Toast: View {
    let message: String
    var systemImage = "checkmark.circle.fill"

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage).foregroundStyle(Palette.success)
            Text(message).font(.subheadline.weight(.medium)).foregroundStyle(Palette.ink)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassCapsule()
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// Модификатор «появление с задержкой» — для каскадного показа карточек решения.
struct StaggeredAppearance: ViewModifier {
    let index: Int
    @State private var isVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : 8)
            .scaleEffect(isVisible || reduceMotion ? 1 : 0.99, anchor: .top)
            .onAppear {
                withAnimation(Theme.gentle.delay(reduceMotion ? 0 : min(Double(index) * 0.06, 0.5))) {
                    isVisible = true
                }
            }
    }
}

extension View {
    func staggered(_ index: Int) -> some View {
        modifier(StaggeredAppearance(index: index))
    }
}

/// «Скелетон» с бегущим бликом — пока идёт обработка.
struct ShimmerBar: View {
    var width: CGFloat?
    var height: CGFloat = 14
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(Palette.surface3)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [Palette.hairlineStrong.opacity(0), Palette.hairlineStrong, Palette.hairlineStrong.opacity(0)],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: proxy.size.width * 0.5)
                    .offset(x: phase * proxy.size.width)
                }
                .clipShape(RoundedRectangle(cornerRadius: height / 2, style: .continuous))
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: false)) {
                    phase = 1.2
                }
            }
    }
}
