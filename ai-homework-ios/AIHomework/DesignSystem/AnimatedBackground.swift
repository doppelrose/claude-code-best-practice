import SwiftUI

/// Мягкий «северное сияние»-фон: медленно переливающийся градиент.
///
/// На iOS 18+ это `MeshGradient` (рисуется на GPU), на iOS 17 — размытые цветные пятна.
/// Анимация останавливается, когда включено «Уменьшение движения» или экран неактивен.
struct AnimatedBackground: View {
    var colors: [Color] = Theme.brand
    /// Насколько фон насыщен: на экранах с текстом он должен быть спокойнее.
    var intensity: Double = 1

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || scenePhase != .active)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate * 0.35
            ZStack {
                Color(.systemGroupedBackground)
                aurora(time: time)
                    .opacity((colorScheme == .dark ? 0.55 : 0.42) * intensity)
                    .blur(radius: 30)
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func aurora(time: Double) -> some View {
        if #available(iOS 18.0, *) {
            MeshAurora(time: time, colors: meshColors)
        } else {
            BlobAurora(time: time, colors: colors)
        }
    }

    /// Девять цветов для сетки 3×3: фирменные оттенки по диагонали, фон — по краям.
    private var meshColors: [Color] {
        let base = Color(.systemGroupedBackground)
        let first = colors.first ?? .indigo
        let middle = colors.count > 1 ? colors[colors.count / 2] : first
        let last = colors.last ?? .pink
        return [
            first, base, middle,
            base, middle.opacity(0.85), base,
            last, base, first.opacity(0.9),
        ]
    }
}

@available(iOS 18.0, *)
private struct MeshAurora: View {
    let time: Double
    let colors: [Color]

    private func point(_ x: Double, _ y: Double) -> SIMD2<Float> {
        SIMD2<Float>(Float(x), Float(y))
    }

    var body: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [
                point(0, 0), point(0.5 + 0.12 * sin(time), 0), point(1, 0),
                point(0, 0.5 + 0.1 * cos(time * 0.8)),
                point(0.5 + 0.18 * sin(time * 0.7), 0.5 + 0.16 * cos(time * 0.9)),
                point(1, 0.5 + 0.1 * sin(time * 1.1)),
                point(0, 1), point(0.5 + 0.12 * cos(time * 1.3), 1), point(1, 1),
            ],
            colors: colors)
    }
}

private struct BlobAurora: View {
    let time: Double
    let colors: [Color]

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                ForEach(Array(colors.enumerated()), id: \.offset) { index, color in
                    let phase = time + Double(index) * 2.1
                    Circle()
                        .fill(color)
                        .frame(width: size.width * 0.9, height: size.width * 0.9)
                        .offset(
                            x: CGFloat(cos(phase * 0.9)) * size.width * 0.35,
                            y: CGFloat(sin(phase * 0.7)) * size.height * 0.3 + CGFloat(index - 1) * size.height * 0.22)
                        .blur(radius: 70)
                }
            }
            .frame(width: size.width, height: size.height)
        }
    }
}

/// Светящийся «орб» — главный визуальный элемент приложения (кнопка решения и индикатор работы).
struct AIOrb: View {
    var size: CGFloat = 132
    /// В активном состоянии (идёт распознавание или решение) орб вращается быстрее.
    var isActive = false
    var symbol = "sparkles"

    @State private var rotation = 0.0
    @State private var breathing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Свечение.
            Circle()
                .fill(AngularGradient(colors: Theme.orb, center: .center))
                .blur(radius: size * 0.2)
                .opacity(0.7)
                .scaleEffect(breathing ? 1.14 : 0.94)

            // Вращающийся градиент.
            Circle()
                .fill(AngularGradient(colors: Theme.orb, center: .center))
                .rotationEffect(.degrees(rotation))

            // Блик сверху — ощущение стеклянной сферы.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.65), Color.white.opacity(0)],
                        center: UnitPoint(x: 0.32, y: 0.24), startRadius: 0, endRadius: size * 0.55))
            Circle()
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)

            Image(systemName: symbol)
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 3)
                .symbolEffect(.pulse, options: .repeating, isActive: isActive)
        }
        .frame(width: size, height: size)
        .onAppear { startAnimations() }
        .onChange(of: isActive) { _, _ in startAnimations() }
        .accessibilityHidden(true)
    }

    private func startAnimations() {
        guard !reduceMotion else { return }
        rotation = 0
        withAnimation(.linear(duration: isActive ? 2.6 : 10).repeatForever(autoreverses: false)) {
            rotation = 360
        }
        withAnimation(.easeInOut(duration: isActive ? 0.9 : 2.4).repeatForever(autoreverses: true)) {
            breathing = true
        }
    }
}
