import PhotosUI
import SwiftUI

/// Корневой экран: навигация, сценарий решения поверх неё, камера, галерея и быстрые действия.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var heroNamespace
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        @Bindable var app = app
        ZStack {
            NavigationStack(path: $app.path) {
                HomeView(namespace: heroNamespace)
                    .navigationDestination(for: AppRoute.self) { route in
                        switch route {
                        case .history: HistoryView()
                        case .subject(let subject): SubjectView(subject: subject)
                        case .problem(let id): ProblemDetailView(problemID: id)
                        }
                    }
            }
            .scaleEffect(app.activeFlow == nil ? 1 : 0.94)
            .blur(radius: app.activeFlow == nil ? 0 : 8)
            .allowsHitTesting(app.activeFlow == nil)

            if let flow = app.activeFlow {
                SolveFlowView(model: flow, namespace: heroNamespace)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 1.04)), removal: .opacity))
                    .zIndex(1)
            }
        }
        .sheet(isPresented: $app.isSettingsPresented) {
            SettingsView()
        }
        .fullScreenCover(item: $app.capture) { source in
            captureView(source)
                .ignoresSafeArea()
        }
        .photosPicker(isPresented: $app.isPhotoPickerPresented, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    app.startSolve(.image(image))
                } else {
                    app.alertMessage = app.l("Не удалось открыть изображение.", "Could not open the image.")
                }
            }
        }
        .alert(
            app.l("Внимание", "Heads up"),
            isPresented: Binding(get: { app.alertMessage != nil }, set: { if !$0 { app.alertMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(app.alertMessage ?? "")
        }
        // Кнопка действия / Команды / элементы управления.
        .onAppear { app.handlePendingQuickAction() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { app.handlePendingQuickAction() }
        }
        .onReceive(NotificationCenter.default.publisher(for: QuickActionInbox.notification)) { _ in
            app.handlePendingQuickAction()
        }
    }

    @ViewBuilder
    private func captureView(_ source: CaptureSource) -> some View {
        switch source {
        case .camera:
            CameraPicker(
                onImage: { image in
                    app.capture = nil
                    app.startSolve(.image(image))
                },
                onCancel: { app.capture = nil })
        case .scanner:
            DocumentScanner(
                onImage: { image in
                    app.capture = nil
                    app.startSolve(.image(image))
                },
                onCancel: { app.capture = nil })
        }
    }
}
