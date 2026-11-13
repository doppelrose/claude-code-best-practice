import SwiftUI

/// Выделение части задания на фотографии — в духе Circle to Search.
///
/// Пользователь обводит нужный фрагмент пальцем; по контуру строится прямоугольная область,
/// которую затем можно подправить за угловые маркеры. Выделение хранится в нормированных
/// координатах изображения (0…1), поэтому не зависит от размера экрана.
struct RegionSelectionView: View {
    let image: UIImage
    @Binding var selection: CGRect?
    let l: L10n

    @State private var lasso: [CGPoint] = []
    @State private var dashPhase: CGFloat = 0
    @State private var resizeStart: CGRect?

    var body: some View {
        GeometryReader { proxy in
            let frame = imageFrame(in: proxy.size)
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: frame.width, height: frame.height)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .position(x: frame.midX, y: frame.midY)

                if let rect = viewRect(for: selection, in: frame) {
                    // Затемнение всего, кроме выделенной области.
                    Path { path in
                        path.addRoundedRect(in: frame, cornerSize: CGSize(width: 18, height: 18))
                        path.addRoundedRect(in: rect, cornerSize: CGSize(width: 12, height: 12))
                    }
                    .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)

                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            AngularGradient(colors: Theme.orb, center: .center),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [12, 7], dashPhase: dashPhase)
                        )
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .shadow(color: Theme.brand[1].opacity(0.7), radius: 8)
                        .allowsHitTesting(false)

                    ForEach(Corner.allCases) { corner in
                        handle(corner, rect: rect, frame: frame)
                    }
                }

                // След пальца.
                if lasso.count > 1 {
                    LassoShape(points: lasso)
                        .stroke(
                            LinearGradient(colors: Theme.orb, startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                        )
                        .shadow(color: Theme.brand[1].opacity(0.9), radius: 10)
                        .shadow(color: Color.white.opacity(0.6), radius: 2)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(lassoGesture(frame: frame))
        }
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                dashPhase = -38
            }
        }
        .accessibilityLabel(l("Фотография задания. Обведите нужную часть.", "Photo of the task. Circle the part you need."))
    }

    // MARK: - Geometry

    /// Прямоугольник, который занимает изображение при вписывании в контейнер.
    private func imageFrame(in container: CGSize) -> CGRect {
        let size = image.size
        guard size.width > 0, size.height > 0, container.width > 0, container.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let scale = min(container.width / size.width, container.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(
            x: (container.width - fitted.width) / 2, y: (container.height - fitted.height) / 2,
            width: fitted.width, height: fitted.height)
    }

    private func viewRect(for normalized: CGRect?, in frame: CGRect) -> CGRect? {
        guard let normalized else { return nil }
        return CGRect(
            x: frame.minX + normalized.minX * frame.width, y: frame.minY + normalized.minY * frame.height,
            width: normalized.width * frame.width, height: normalized.height * frame.height)
    }

    private func normalizedRect(for rect: CGRect, in frame: CGRect) -> CGRect {
        let clipped = rect.intersection(frame)
        return CGRect(
            x: (clipped.minX - frame.minX) / frame.width, y: (clipped.minY - frame.minY) / frame.height,
            width: clipped.width / frame.width, height: clipped.height / frame.height)
    }

    // MARK: - Lasso

    private func lassoGesture(frame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if lasso.isEmpty { Haptics.soft() }
                lasso.append(value.location)
            }
            .onEnded { _ in
                let points = lasso
                withAnimation(.easeOut(duration: 0.25)) { lasso = [] }
                guard points.count > 3 else { return }
                let xs = points.map { $0.x }
                let ys = points.map { $0.y }
                guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return }
                let bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).insetBy(dx: -8, dy: -8)
                let clipped = bounds.intersection(frame)
                guard clipped.width >= 32, clipped.height >= 24 else { return }
                Haptics.success()
                withAnimation(Theme.bouncy) {
                    selection = normalizedRect(for: clipped, in: frame)
                }
            }
    }

    // MARK: - Corner handles

    private enum Corner: Int, CaseIterable, Identifiable {
        case topLeft, topRight, bottomLeft, bottomRight
        var id: Int { rawValue }
    }

    private func position(of corner: Corner, in rect: CGRect) -> CGPoint {
        switch corner {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    private func handle(_ corner: Corner, rect: CGRect, frame: CGRect) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: 22, height: 22)
            .overlay { Circle().strokeBorder(Theme.brand[1], lineWidth: 3) }
            .shadow(color: Color.black.opacity(0.3), radius: 4, y: 2)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .position(position(of: corner, in: rect))
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if resizeStart == nil {
                            resizeStart = rect
                            Haptics.selection()
                        }
                        guard let start = resizeStart else { return }
                        var minX = start.minX
                        var maxX = start.maxX
                        var minY = start.minY
                        var maxY = start.maxY
                        let minimum: CGFloat = 40
                        switch corner {
                        case .topLeft:
                            minX = min(start.minX + value.translation.width, maxX - minimum)
                            minY = min(start.minY + value.translation.height, maxY - minimum)
                        case .topRight:
                            maxX = max(start.maxX + value.translation.width, minX + minimum)
                            minY = min(start.minY + value.translation.height, maxY - minimum)
                        case .bottomLeft:
                            minX = min(start.minX + value.translation.width, maxX - minimum)
                            maxY = max(start.maxY + value.translation.height, minY + minimum)
                        case .bottomRight:
                            maxX = max(start.maxX + value.translation.width, minX + minimum)
                            maxY = max(start.maxY + value.translation.height, minY + minimum)
                        }
                        let updated = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                        selection = normalizedRect(for: updated, in: frame)
                    }
                    .onEnded { _ in
                        resizeStart = nil
                    }
            )
            .accessibilityLabel(l("Маркер области", "Selection handle"))
    }
}

/// Сглаженная линия по точкам касания.
private struct LassoShape: Shape {
    var points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            for point in points.dropFirst() { path.addLine(to: point) }
            return path
        }
        // Квадратичные кривые через середины отрезков дают плавный штрих.
        for index in 1..<(points.count - 1) {
            let current = points[index]
            let next = points[index + 1]
            let middle = CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2)
            path.addQuadCurve(to: middle, control: current)
        }
        if let last = points.last { path.addLine(to: last) }
        return path
    }
}
