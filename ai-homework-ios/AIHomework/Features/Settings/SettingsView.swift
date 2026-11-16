import AppIntents
import SwiftData
import SwiftUI

/// Настройки: язык, оформление, кнопка действия, нейросеть по API, Apple Intelligence, приватность и данные.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var systemModel: ModelAvailability?
    @State private var isClearConfirmationPresented = false
    @State private var availableModels: [String] = []
    @State private var connectionStatus: ConnectionStatus = .idle
    @State private var isKeyVisible = false

    private enum ConnectionStatus: Equatable {
        case idle
        case checking
        case success(String)
        case failure(String)
    }

    private var l: L10n { app.l }

    var body: some View {
        @Bindable var settings = app.settings
        NavigationStack {
            Form {
                Section(l("Основное", "General")) {
                    Picker(l("Язык", "Language"), selection: $settings.data.languageChoice) {
                        Text(l("Как в системе", "System")).tag(SettingsData.LanguageChoice.system)
                        Text("Русский").tag(SettingsData.LanguageChoice.ru)
                        Text("English").tag(SettingsData.LanguageChoice.en)
                    }
                    Picker(l("Оформление", "Appearance"), selection: $settings.data.appearance) {
                        Text(l("Авто", "Auto")).tag(SettingsData.Appearance.system)
                        Text(l("Светлое", "Light")).tag(SettingsData.Appearance.light)
                        Text(l("Тёмное", "Dark")).tag(SettingsData.Appearance.dark)
                    }
                    .pickerStyle(.segmented)
                    Toggle(l("Тактильный отклик", "Haptic feedback"), isOn: $settings.data.hapticsEnabled)
                    Toggle(l("Сохранять фото в истории", "Keep photos in history"), isOn: $settings.data.keepPhotosInHistory)
                }

                apiSection(settings: settings)
                systemModelSection(settings: settings)
                actionButtonSection
                privacySection

                Section(l("Данные", "Data")) {
                    Button(l("Удалить всю историю", "Delete all history"), role: .destructive) {
                        isClearConfirmationPresented = true
                    }
                }

                Section {
                    LabeledContent(l("Версия", "Version"), value: appVersion)
                } footer: {
                    Text(
                        l(
                            "Без нейросети по API задания решают точные алгоритмы на iPhone (математика, физика, химия, информатика) и, если поддерживается, Apple Intelligence. Если API настроен, текст задания сначала читает выбранная вами нейросеть: простые задачи она передаёт точному решателю на iPhone, остальные решает сама.",
                            "Without an AI model via API, tasks are solved by exact algorithms on the iPhone (math, physics, chemistry, computer science) and, where supported, by Apple Intelligence. With an API set up, the task text is first read by the AI model you chose: it hands simple tasks to the exact on-device solver and solves the rest itself."
                        ))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.canvas)
            .tint(Palette.accent)
            .navigationTitle(l("Настройки", "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(l("Готово", "Done")) { dismiss() }
                }
            }
            .onChange(of: settings.data) { _, _ in
                // Запись с задержкой: при наборе адреса настройки не пишутся на каждый символ.
                // Ключ API записывает сам `AppSettings` (тоже с задержкой).
                settings.scheduleSave()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase != .active else { return }
                // Ключ не должен остаться открытым в снимке переключателя приложений.
                isKeyVisible = false
                settings.flushPendingSaves()
            }
            .onDisappear {
                isKeyVisible = false
                settings.flushPendingSaves()
            }
            .task(id: settings.data.languageChoice) {
                systemModel = await AppleIntelligenceProvider().availability(l)
            }
            .confirmationDialog(
                l("Удалить все задания?", "Delete all tasks?"), isPresented: $isClearConfirmationPresented, titleVisibility: .visible
            ) {
                Button(l("Удалить всё", "Delete all"), role: .destructive) {
                    try? context.delete(model: SolvedProblem.self)
                    try? context.save()
                    Haptics.warning()
                }
            }
        }
    }

    // MARK: - API

    private func apiSection(settings: AppSettings) -> some View {
        Section {
            Picker(l("Формат API", "API format"), selection: Bindable(settings).data.apiFormat) {
                ForEach(RemoteAPIFormat.allCases) { format in
                    Text(format.title).tag(format)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(l("Адрес API", "API address")).font(.caption).foregroundStyle(Palette.inkSubtle)
                TextField("https://api.example.com/v1", text: Bindable(settings).data.apiBaseURL)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(l("Ключ API", "API key")).font(.caption).foregroundStyle(Palette.inkSubtle)
                HStack {
                    // Ввод — только в защищённом поле: сторонние клавиатуры его не видят.
                    SecureField("sk-…", text: Bindable(settings).apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        isKeyVisible.toggle()
                    } label: {
                        Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                            .foregroundStyle(Palette.inkSubtle)
                    }
                    .buttonStyle(.plain)
                    .disabled(settings.apiKey.trimmed.isEmpty)
                    .accessibilityLabel(isKeyVisible ? l("Скрыть ключ", "Hide key") : l("Показать ключ", "Show key"))
                }
                if isKeyVisible, !settings.apiKey.trimmed.isEmpty {
                    Text(settings.apiKey)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Palette.inkMuted)
                        .lineLimit(2)
                        .privacySensitive()
                } else if !settings.apiKey.trimmed.isEmpty {
                    Text(maskedKey(settings.apiKey, host: settings.apiKeyHost))
                        .font(.caption)
                        .foregroundStyle(Palette.inkSubtle)
                }
            }

            if settings.isAPIKeyBoundToOtherHost {
                keyHostWarning(settings: settings)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(l("Модель", "Model")).font(.caption).foregroundStyle(Palette.inkSubtle)
                HStack {
                    TextField(l("например, claude-opus-5-5", "e.g. claude-opus-5-5"), text: Bindable(settings).data.apiModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !availableModels.isEmpty {
                        Menu {
                            ForEach(availableModels, id: \.self) { model in
                                Button(model) {
                                    settings.data.apiModel = model
                                    Haptics.selection()
                                }
                            }
                        } label: {
                            Image(systemName: "list.bullet.circle")
                        }
                        .accessibilityLabel(l("Выбрать из списка", "Choose from the list"))
                    }
                }
            }

            Toggle(isOn: Bindable(settings).data.sendImagesToAPI) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(l("Отправлять изображение в нейросеть", "Send the image to the AI model"))
                    Text(
                        l(
                            "Выключено: в API уходит только распознанный текст. Включено: выделенный фрагмент фото уходит в запрос решения (не диспетчеру) — нужно для чертежей и рукописи.",
                            "Off: only the recognized text is sent to the API. On: the selected part of the photo goes into the solution request (not to the dispatcher) — useful for drawings and handwriting."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(Palette.inkSubtle)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                checkConnection(settings.remoteConfigForRequest())
            } label: {
                HStack {
                    Label(l("Проверить и загрузить модели", "Check and load models"), systemImage: "checkmark.shield")
                    if connectionStatus == .checking {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(connectionStatus == .checking)

            Button {
                sendTestQuestion(settings.remoteConfigForRequest())
            } label: {
                Label(l("Отправить тестовый вопрос", "Send a test question"), systemImage: "paperplane")
            }
            .disabled(connectionStatus == .checking || !settings.remoteConfig.isComplete)

            switch connectionStatus {
            case .success(let message):
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(Palette.success)
            case .failure(let message):
                Label(message, systemImage: "xmark.octagon.fill")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkMuted)
            case .idle, .checking:
                EmptyView()
            }
        } header: {
            Text(l("Нейросеть по API", "AI model via API"))
        } footer: {
            Text(
                l(
                    "Укажите данные из личного кабинета вашего сервиса (apimira, OpenRouter и т. п.). Адрес обычно заканчивается на /v1. Большинство сервисов работают в формате OpenAI. Ключ хранится в защищённой Связке ключей iPhone и отправляется только на адрес, для которого его ввели. Когда API настроен, текст каждого задания отправляется на этот адрес — даже простого примера: сначала нейросеть-диспетчер решает, кому его отдать, затем при необходимости решает сама. Изображение уходит только при включённой настройке выше.",
                    "Enter the details from your service's dashboard (apimira, OpenRouter, etc.). The address usually ends with /v1. Most services use the OpenAI format. The key is stored in the secure iPhone Keychain and is sent only to the address it was entered for. With an API set up, the text of every task is sent to this address — even a simple expression: first the dispatcher model decides who solves it, then, if needed, it solves it itself. The image is sent only when the setting above is on."
                ))
        }
    }

    /// Ключ под маской: видно только, чем он заканчивается и для какого адреса сохранён.
    private func maskedKey(_ key: String, host: String?) -> String {
        let trimmed = key.trimmed
        let suffix = trimmed.count > 8 ? "…" + String(trimmed.suffix(4)) : "…"
        guard let host else { return l("Сохранён ключ \(suffix)", "Saved key \(suffix)") }
        return l("Сохранён ключ \(suffix) для \(host)", "Saved key \(suffix) for \(host)")
    }

    /// Адрес API изменился: ключ на новый хост не отправляется без явного согласия.
    private func keyHostWarning(settings: AppSettings) -> some View {
        let bound = settings.apiKeyHost ?? ""
        let current = settings.currentAPIHost ?? ""
        return VStack(alignment: .leading, spacing: 8) {
            Label(
                l(
                    "Ключ сохранён для \(bound). На \(current) он не отправляется — введите ключ для нового адреса.",
                    "The key was saved for \(bound). It is not sent to \(current) — enter the key for the new address."),
                systemImage: "exclamationmark.shield"
            )
            .font(.footnote)
            .foregroundStyle(Palette.inkMuted)
            .fixedSize(horizontal: false, vertical: true)
            Button(l("Это ключ для \(current) — отправлять туда", "This key is for \(current) — send it there")) {
                settings.bindAPIKeyToCurrentHost()
                Haptics.selection()
            }
            .font(.footnote.weight(.semibold))
        }
        .padding(.vertical, 2)
    }

    private func checkConnection(_ config: RemoteAPIConfig) {
        connectionStatus = .checking
        Task {
            do {
                let models = try await RemoteAPIProvider.fetchModels(config)
                availableModels = models
                Haptics.success()
                connectionStatus =
                    models.isEmpty
                    ? .success(l("Подключение работает. Список моделей сервис не вернул — впишите название вручную.", "The connection works. The service returned no model list — type the name manually."))
                    : .success(l("Подключение работает. Моделей: \(models.count) — выберите в списке у поля «Модель».", "The connection works. Models: \(models.count) — pick one from the list next to “Model”."))
            } catch let error as RemoteAPIError {
                Haptics.error()
                connectionStatus = .failure(error.message(l))
            } catch {
                Haptics.error()
                connectionStatus = .failure(error.localizedDescription)
            }
        }
    }

    private func sendTestQuestion(_ config: RemoteAPIConfig) {
        connectionStatus = .checking
        Task {
            do {
                let answer = try await RemoteAPIProvider(config: config).generate(
                    instructions: l("Отвечай кратко.", "Answer briefly."),
                    prompt: l("Сколько будет 2 + 2? Ответь одним числом.", "What is 2 + 2? Answer with a single number."),
                    image: nil, maxTokens: 50)
                Haptics.success()
                connectionStatus = .success(l("Модель ответила: ", "The model answered: ") + String(answer.prefix(80)))
            } catch let error as RemoteAPIError {
                Haptics.error()
                connectionStatus = .failure(error.message(l))
            } catch let error as LanguageModelError {
                Haptics.error()
                connectionStatus = .failure(error.message(l))
            } catch {
                Haptics.error()
                connectionStatus = .failure(error.localizedDescription)
            }
        }
    }

    // MARK: - Apple Intelligence

    private func systemModelSection(settings: AppSettings) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Apple Intelligence", systemImage: "sparkles")
                        .font(.cardTitle)
                    Spacer()
                    if let systemModel {
                        Circle()
                            .fill(systemModel.isAvailable ? Palette.success : Palette.inkTertiary)
                            .frame(width: 10, height: 10)
                    } else {
                        ProgressView()
                    }
                }
                if let systemModel {
                    Text(systemModel.title).font(.subheadline.weight(.semibold))
                    Text(systemModel.detail)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSubtle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
            Toggle(l("Использовать без интернета", "Use when offline"), isOn: Bindable(settings).data.useSystemModel)
        } header: {
            Text(l("Без интернета", "Offline"))
        } footer: {
            Text(
                l(
                    "Если нет интернета или сервис API недоступен, текстовые задания решает модель Apple Intelligence прямо на iPhone (iOS 26+, iPhone 15 Pro и новее) — если она поддерживает язык приложения. Она не видит изображения — только распознанный текст.",
                    "Without internet or when the API service is unavailable, text tasks are solved by the Apple Intelligence model right on the iPhone (iOS 26+, iPhone 15 Pro or later) — if it supports the app language. It does not see images — only the recognized text."
                ))
        }
    }

    // MARK: - Action Button

    private var actionButtonSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label(l("Скриншот и выделение одной кнопкой", "Screenshot and select with one press"), systemImage: "button.programmable")
                    .font(.cardTitle)
                instruction(1, l("Откройте приложение «Команды» и нажмите «+».", "Open the Shortcuts app and tap “+”."))
                instruction(2, l("Добавьте действие «Сделать снимок экрана».", "Add the “Take Screenshot” action."))
                instruction(
                    3,
                    l(
                        "Добавьте действие «Решить скриншот» (AI Homework). В поле «Изображение» должен стоять «Снимок экрана».",
                        "Add the “Solve a screenshot” action (AI Homework). Its “Image” field must be set to “Screenshot”."))
                instruction(4, l("Назовите команду, например «Решить с экрана».", "Name the shortcut, e.g. “Solve from screen”."))
                instruction(
                    5,
                    l(
                        "«Настройки» → «Кнопка действия» → «Команда» → выберите эту команду.",
                        "Settings → Action Button → Shortcut → choose this shortcut."))
                Text(
                    l(
                        "Теперь нажатие кнопки снимает экран, открывает AI Homework, вы обводите задание пальцем — и решение начинается сразу.",
                        "Now a press takes a screenshot and opens AI Homework; you circle the task with your finger and solving starts right away."
                    )
                )
                .font(.footnote)
                .foregroundStyle(Palette.inkSubtle)
            }
            .padding(.vertical, 4)
            ShortcutsLink()
                .shortcutsLinkStyle(.automaticOutline)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
        } header: {
            Text(l("Кнопка действия", "Action Button"))
        } footer: {
            Text(
                l(
                    "Скриншот делает приложение «Команды»: iOS не разрешает приложениям снимать экран других приложений. Кнопка действия есть на iPhone 15 Pro, iPhone 16 и новее.",
                    "The screenshot is taken by the Shortcuts app: iOS does not let apps capture other apps' screens. The Action Button is available on iPhone 15 Pro, iPhone 16 and later."
                ))
        }
    }

    private func instruction(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .foregroundStyle(Palette.inkMuted)
                .frame(width: 22, height: 22)
                .modifier(SurfaceStyle(shape: Circle(), level: .three, strongBorder: true))
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        Section(l("Конфиденциальность", "Privacy")) {
            privacyRow("iphone", l("Без API задания решаются на устройстве, без сети", "Without an API, tasks are solved on the device, offline"))
            privacyRow(
                "arrow.up.forward.app",
                l("С API текст каждого задания уходит только на указанный вами адрес", "With an API, the text of every task goes only to the address you set"))
            privacyRow(
                "photo",
                l("Изображение — только если вы включили «Отправлять изображение в нейросеть»", "The image only if you turned on “Send the image to the AI model”"))
            privacyRow("key.fill", l("Ключ хранится в Связке ключей и уходит только на свой адрес", "The key stays in the Keychain and goes only to its own address"))
            privacyRow("person.crop.circle.badge.xmark", l("Без регистрации и аналитики", "No sign-up and no analytics"))
        }
    }

    private func privacyRow(_ systemImage: String, _ text: String) -> some View {
        Label {
            Text(text).font(.subheadline)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(Palette.inkSubtle)
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}
