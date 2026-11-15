import SwiftUI

/// Нажатие: короткое мягкое сжатие и затемнение — без «прыжка».
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    var haptic = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.9), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed, haptic { Haptics.tap() }
            }
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

/// Главная кнопка: сплошной акцент, скругление 10 pt, без градиента и свечения.
struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    var isLoading = false
    /// Оставлено для совместимости: главная кнопка всегда акцентная.
    var colors: [Color] = Theme.brand
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(Palette.onAccent)
                } else if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 15, weight: .semibold))
                }
                Text(title).font(.buttonLabel)
            }
            .foregroundStyle(Palette.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background {
                RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                    .fill(Palette.accent)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    }
            }
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.pressable)
        .disabled(isLoading)
    }
}

/// Второстепенная кнопка: поверхность с тонкой рамкой.
struct GlassButton: View {
    let title: String
    var systemImage: String?
    var tint: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 14, weight: .medium))
                }
                Text(title).font(.buttonLabel)
            }
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .modifier(SurfaceStyle(shape: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous), level: .one, strongBorder: true))
        }
        .buttonStyle(.pressable)
    }
}

/// Круглая кнопка-иконка.
struct GlassIconButton: View {
    let systemImage: String
    var size: CGFloat = 40
    var tint: Color?
    var accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.38, weight: .medium))
                .foregroundStyle(tint ?? Palette.ink)
                .frame(width: size, height: size)
                .glassCircle()
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(accessibilityLabel)
    }
}
