import SwiftData
import SwiftUI

/// Полноэкранный сценарий решения. Появляется поверх главного экрана: «орб» в верхней
/// панели связан с большой кнопкой главного экрана через `matchedGeometryEffect`.
struct SolveFlowView: View {
    @Bindable var model: SolveViewModel
    let namespace: Namespace.ID

    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @State private var toast: String?
    @State private var sharedFile: SharedFile?

    private var l: L10n { model.l }

    var body: some View {
        ZStack(alignment: .bottom) {
            AnimatedBackground(colors: model.subject.palette + [Theme.brand[2]], intensity: 0.85)

            VStack(spacing: 0) {
                topBar
                stageContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let toast {
                Toast(message: toast)
                    .padding(.bottom, model.stage == .result ? 110 : 30)
                    .zIndex(5)
            }
        }
        .onAppear {
            model.onAppear()
            if model.consumeAutoSolve() {
                model.solve(context: context)
            }
        }
        .sheet(item: $sharedFile) { file in
            ActivityView(items: [file.url])
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Top bar

    private var stageTitle: String {
        switch model.stage {
        case .selecting: return l("Что решаем?", "What should we solve?")
        case .recognizing: return l("Распознаю текст", "Recognizing text")
        case .review: return l("Проверьте условие", "Check the task")
        case .solving: return l("Решаю", "Solving")
        case .result: return l("Решение", "Solution")
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            GlassIconButton(systemImage: "xmark", accessibilityLabel: l("Закрыть", "Close")) {
                app.closeFlow()
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                AIOrb(size: 30, isActive: model.stage == .recognizing || model.stage == .solving)
                    .matchedGeometryEffect(id: "hero-orb", in: namespace)
                Text(stageTitle)
                    .font(.headline)
                    .contentTransition(.opacity)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            // Симметричный элемент справа: избранное на экране результата.
            if model.stage == .result {
                GlassIconButton(
                    systemImage: model.isFavorite ? "bookmark.fill" : "bookmark",
                    tint: model.isFavorite ? Color.yellow : nil,
                    accessibilityLabel: l("В избранное", "Add to favorites")
                ) {
                    model.toggleFavorite(context: context)
                    show(model.isFavorite ? l("Добавлено в избранное", "Added to favorites") : l("Убрано из избранного", "Removed from favorites"))
                }
                .transition(.scale.combined(with: .opacity))
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    // MARK: - Stages

    @ViewBuilder
    private var stageContent: some View {
        switch model.stage {
        case .selecting:
            SelectingStage(model: model)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        case .recognizing:
            RecognizingStage(model: model)
                .transition(.opacity)
        case .review:
            ReviewStage(model: model) {
                model.solve(context: context)
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
        case .solving:
            SolvingStage(l: l)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        case .result:
            ResultStage(
                model: model,
                onToast: { show($0) },
                onExportPDF: { exportPDF() },
                onResolve: { model.solve(context: context) }
            )
            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
        }
    }

    // MARK: - Actions

    private func show(_ message: String) {
        withAnimation(Theme.bouncy) { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(Theme.spring) {
                if toast == message { toast = nil }
            }
        }
    }

    private func exportPDF() {
        guard let solution = model.solution else { return }
        do {
            let url = try PDFExporter.export(
                problem: model.text.trimmed, solution: solution, image: model.recognizedImage ?? model.image,
                date: model.record?.createdAt ?? Date(), l: l)
            Haptics.success()
            sharedFile = SharedFile(url: url)
        } catch {
            Haptics.error()
            show(l("Не удалось создать PDF", "Could not create the PDF"))
        }
    }
}

// MARK: - Selecting

private struct SelectingStage: View {
    @Bindable var model: SolveViewModel
    private var l: L10n { model.l }

    var body: some View {
        VStack(spacing: 14) {
            Label(
                model.selection == nil
                    ? l("Обведите пальцем нужную часть задания", "Circle the part of the task with your finger")
                    : l("Потяните за углы, чтобы уточнить область", "Drag the corners to adjust the area"),
                systemImage: model.selection == nil ? "hand.draw.fill" : "crop"
            )
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassCapsule()
            .contentTransition(.opacity)

            if let image = model.image {
                RegionSelectionView(image: image, selection: $model.selection, l: l)
                    .padding(.horizontal, 12)
            }

            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, Theme.screenPadding)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }

            VStack(spacing: 10) {
                if model.selection != nil {
                    PrimaryButton(title: l("Распознать выделенное", "Recognize the selection"), systemImage: "viewfinder") {
                        model.recognize(useSelection: true)
                    }
                    HStack(spacing: 10) {
                        GlassButton(title: l("Сбросить", "Reset"), systemImage: "arrow.uturn.backward") {
                            Haptics.tap()
                            withAnimation(Theme.spring) { model.selection = nil }
                        }
                        GlassButton(title: l("Всё фото", "Whole photo"), systemImage: "photo") {
                            model.recognize(useSelection: false)
                        }
                    }
                } else {
                    PrimaryButton(title: l("Распознать всё фото", "Recognize the whole photo"), systemImage: "text.viewfinder") {
                        model.recognize(useSelection: false)
                    }
                    GlassButton(title: l("Ввести условие вручную", "Type the task manually"), systemImage: "keyboard") {
                        model.enterManually()
                    }
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 12)
            .animation(Theme.spring, value: model.selection != nil)
        }
    }
}

// MARK: - Recognizing

private struct RecognizingStage: View {
    let model: SolveViewModel
    @State private var beam: CGFloat = 0

    var body: some View {
        VStack(spacing: 22) {
            if let image = model.recognizedImage ?? model.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        // Луч сканирования.
                        GeometryReader { proxy in
                            LinearGradient(
                                colors: [Color.white.opacity(0), Theme.brand[1].opacity(0.55), Color.white.opacity(0.9), Theme.brand[2].opacity(0.55), Color.white.opacity(0)],
                                startPoint: .top, endPoint: .bottom
                            )
                            .frame(height: 110)
                            .offset(y: beam * (proxy.size.height + 110) - 110)
                            .blendMode(.plusLighter)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(AngularGradient(colors: Theme.orb, center: .center), lineWidth: 2.5)
                    }
                    .shadow(color: Theme.brand[1].opacity(0.35), radius: 24, y: 12)
                    .padding(.horizontal, 28)
                    .frame(maxHeight: 420)
            }
            VStack(spacing: 6) {
                Text(model.l("Читаю текст на изображении…", "Reading the text in the image…"))
                    .font(.headline)
                Label(model.l("Обработка на устройстве", "Processed on device"), systemImage: "lock.shield.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 20)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) {
                beam = 1
            }
        }
    }
}

// MARK: - Solving

private struct SolvingStage: View {
    let l: L10n
    @State private var statusIndex = 0

    private var statuses: [String] {
        [
            l("Определяю тип задания…", "Identifying the task type…"),
            l("Подбираю способ решения…", "Choosing a method…"),
            l("Вычисляю и проверяю ответ…", "Computing and checking the answer…"),
        ]
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            AIOrb(size: 150, isActive: true, symbol: "wand.and.stars")
            VStack(spacing: 8) {
                Text(l("Решаю задание", "Solving the task"))
                    .font(.title2.weight(.bold))
                Text(statuses[statusIndex % statuses.count])
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .id(statusIndex)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            VStack(alignment: .leading, spacing: 12) {
                ShimmerBar(width: 120)
                ShimmerBar()
                ShimmerBar()
                ShimmerBar(width: 200)
            }
            .padding(20)
            .glassCard()
            .padding(.horizontal, 36)
            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .task {
            // Смена подписи — пока идёт работа.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(900))
                withAnimation(Theme.spring) { statusIndex += 1 }
            }
        }
    }
}
