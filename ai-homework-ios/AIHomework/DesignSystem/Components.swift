import SwiftUI

/// Заголовок раздела с необязательной кнопкой справа.
struct SectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.bold))
            Spacer()
            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 3) {
                        Text(actionTitle)
                        Image(systemName: "chevron.right").font(.caption.weight(.bold))
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.pressable)
            }
        }
    }
}

/// Значок предмета в цветном скруглённом квадрате.
struct SubjectIcon: View {
    let subject: Subject
    var size: CGFloat = 44

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(subject.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: subject.symbolName)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: subject.tint.opacity(0.35), radius: size * 0.2, x: 0, y: size * 0.1)
    }
}

/// Метка предмета: значок и название.
struct SubjectBadge: View {
    let subject: Subject
    let l: L10n

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: subject.symbolName).font(.caption.weight(.bold))
            Text(subject.title(l)).font(.caption.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule(style: .continuous).fill(subject.gradient))
    }
}

/// Метка достоверности решения.
struct ReliabilityBadge: View {
    let reliability: SolutionReliability
    let l: L10n

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: reliability.symbolName).font(.caption.weight(.bold))
            Text(reliability.title(l)).font(.caption.weight(.semibold))
        }
        .foregroundStyle(reliability.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule(style: .continuous).fill(reliability.color.opacity(0.14)))
    }
}

/// Блок с формулой: моноширинный шрифт, тонированный фон, текст можно выделить.
struct FormulaBlock: View {
    let text: String
    var tint: Color = .accentColor
    var emphasized = false

    var body: some View {
        Text(text)
            .font(.system(emphasized ? .title3 : .callout, design: .monospaced).weight(emphasized ? .semibold : .medium))
            .lineSpacing(4)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.opacity(0.1))
            }
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
            Image(systemName: systemImage)
            Text(message).font(.subheadline.weight(.medium))
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
            .offset(y: isVisible || reduceMotion ? 0 : 18)
            .scaleEffect(isVisible || reduceMotion ? 1 : 0.97, anchor: .top)
            .onAppear {
                withAnimation(Theme.spring.delay(reduceMotion ? 0 : min(Double(index) * 0.07, 0.6))) {
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
            .fill(Color.primary.opacity(0.08))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [Color.white.opacity(0), Color.white.opacity(0.45), Color.white.opacity(0)],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: proxy.size.width * 0.5)
                    .offset(x: phase * proxy.size.width)
                }
                .clipShape(RoundedRectangle(cornerRadius: height / 2, style: .continuous))
            }
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                    phase = 1.2
                }
            }
    }
}
