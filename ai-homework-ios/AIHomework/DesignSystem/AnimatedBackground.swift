import SwiftUI

/// Фон экранов: спокойное полотно без атмосферных градиентов (правило Linear).
///
/// Параметры оставлены для совместимости с экранами, где раньше был переливающийся фон.
struct AnimatedBackground: View {
    var colors: [Color] = Theme.brand
    var intensity: Double = 1

    var body: some View {
        Palette.canvas.ignoresSafeArea()
    }
}

/// Знак приложения и индикатор работы: кольцо с акцентной дугой и искрой в центре.
///
/// В покое — неподвижен и едва «дышит»; во время распознавания и решения дуга плавно
/// вращается. Учитывает «Уменьшение движения».
struct AIOrb: View {
    var size: CGFloat = 132
    var isActive = false
    var symbol = "sparkle"

    @State private var rotation = 0.0
    @State private var breathing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var ringWidth: CGFloat { max(1.5, size * 0.035) }

    var body: some View {
        ZStack {
            Circle()
                .fill(Palette.surface1)
            Circle()
                .strokeBorder(Palette.hairlineStrong, lineWidth: 1)

            // Дорожка и дуга прогресса.
            Circle()
                .inset(by: size * 0.12)
                .stroke(Palette.hairline, lineWidth: ringWidth)
            Circle()
                .inset(by: size * 0.12)
                .trim(from: 0, to: isActive ? 0.28 : 0.18)
                .stroke(Palette.accent, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                .rotationEffect(.degrees(rotation - 90))

            Image(systemName: symbol)
                .font(.system(size: size * 0.26, weight: .medium))
                .foregroundStyle(Palette.ink)
                .scaleEffect(breathing ? 1.0 : 0.94)
        }
        .frame(width: size, height: size)
        .onAppear { startAnimations() }
        .onChange(of: isActive) { _, _ in startAnimations() }
        .accessibilityHidden(true)
    }

    private func startAnimations() {
        guard !reduceMotion else { return }
        if isActive {
            rotation = 0
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        } else {
            withAnimation(.easeOut(duration: 0.6)) {
                rotation = 0
            }
        }
        withAnimation(.easeInOut(duration: isActive ? 1.0 : 3.2).repeatForever(autoreverses: true)) {
            breathing = true
        }
    }
}
