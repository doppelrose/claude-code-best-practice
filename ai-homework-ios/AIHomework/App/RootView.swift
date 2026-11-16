import PhotosUI
import SwiftUI
import VisionKit

/// Корневой экран: навигация, сценарий решения поверх неё, камера, галерея и быстрые действия.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var heroNamespace
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        @Bindable var bindable = app
        ZStack {
            NavigationStack(path: $bindable.path) {
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
            .sheet(isPresented: $bindable.isCameraAccessDeniedPresented, onDismiss: { app.cameraSheetDidDismiss() }) {
                CameraAccessDeniedView(
                    l: app.l,
                    onOpenSettings: { app.openCameraSettings() },
                    onChoosePhoto: { app.choosePhotoInsteadOfCamera() },
                    onClose: { app.isCameraAccessDeniedPresented = false })
                .presentationDetents([.medium])
            }

            if let flow = app.activeFlow {
                SolveFlowView(model: flow, namespace: heroNamespace)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 1.04)), removal: .opacity))
                    .zIndex(1)
            }

            if app.isPreparingImage {
                ProgressView(app.l("Готовлю изображение…", "Preparing the image…"))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .glassCard()
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .sheet(isPresented: $bindable.isSettingsPresented) {
            SettingsView()
        }
        .fullScreenCover(item: $bindable.capture) { source in
            captureView(source)
                .ignoresSafeArea()
        }
        .photosPicker(isPresented: $bindable.isPhotoPickerPresented, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task {
                // Файл декодируется сразу в уменьшенном виде и вне главного потока (см. `ImageTools.downsampled`).
                if let data = try? await item.loadTransferable(type: Data.self) {
                    app.startSolve(imageData: data)
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
        .confirmationDialog(
            app.l("Идёт решение задания", "A task is being solved"),
            isPresented: Binding(get: { app.pendingInterruption != nil }, set: { if !$0 { app.pendingInterruption = nil } }),
            titleVisibility: .visible
        ) {
            Button(app.l("Остановить и начать новое", "Stop and start a new one"), role: .destructive) {
                app.resolveInterruption(startNew: true)
            }
            Button(app.l("Продолжить решение", "Keep solving"), role: .cancel) {
                app.resolveInterruption(startNew: false)
            }
        } message: {
            Text(app.l("Текущее решение будет остановлено.", "The current solution will be stopped."))
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
                    app.startSolve(preparing: image)
                },
                onCancel: { app.capture = nil })
        case .scanner:
            DocumentScanner(
                onScan: { scan in
                    app.capture = nil
                    app.startSolve(scan: scan)
                },
                onCancel: { app.capture = nil },
                onError: { message in
                    app.capture = nil
                    app.alertMessage = app.l("Сканер не сработал: \(message)", "The scanner failed: \(message)")
                })
        }
    }
}
