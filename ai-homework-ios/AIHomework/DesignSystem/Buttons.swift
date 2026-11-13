import SwiftUI

/// Стиль нажатия: пружинное сжатие и тактильный отклик.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    var haptic = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.6), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed, haptic { Haptics.tap() }
            }
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

/// Главная кнопка действия с фирменным градиентом.
struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    var isLoading = false
    var colors: [Color] = Theme.brand
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView().tint(.white)
                } else if let systemImage {
                    Image(systemName: systemImage).font(.headline)
                }
                Text(title).font(.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background {
                Capsule(style: .continuous)
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .shadow(color: (colors.last ?? .purple).opacity(isEnabled ? 0.38 : 0), radius: 16, x: 0, y: 8)
            }
            .saturation(isEnabled ? 1 : 0.3)
            .opacity(isEnabled ? 1 : 0.6)
        }
        .buttonStyle(.pressable)
        .disabled(isLoading)
    }
}

/// Второстепенная кнопка на стекле.
struct GlassButton: View {
    let title: String
    var systemImage: String?
    var tint: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage).font(.subheadline.weight(.semibold))
                }
                Text(title).font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .glassCapsule(tint: tint, interactive: true)
        }
        .buttonStyle(.pressable)
    }
}

/// Круглая стеклянная кнопка-иконка.
struct GlassIconButton: View {
    let systemImage: String
    var size: CGFloat = 44
    var tint: Color?
    var accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: size, height: size)
                .glassCircle(tint: tint)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(accessibilityLabel)
    }
}
