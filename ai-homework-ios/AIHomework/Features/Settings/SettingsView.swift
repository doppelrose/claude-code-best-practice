import AppIntents
import SwiftData
import SwiftUI

/// Настройки: язык, оформление, кнопка действия, локальные модели, приватность и данные.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var systemModel: ModelAvailability?
    @State private var isImporterPresented = false
    @State private var isClearConfirmationPresented = false

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

                actionButtonSection
                modelsSection(settings: settings)
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
                            "AI Homework решает задания прямо на iPhone: Vision для распознавания, собственные математические, физические и химические движки и, по желанию, локальная языковая модель.",
                            "AI Homework solves tasks right on your iPhone: Vision for recognition, built-in math, physics and chemistry engines and, optionally, an on-device language model."
                        ))
                }
            }
            .navigationTitle(l("Настройки", "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(l("Готово", "Done")) { dismiss() }
                }
            }
            .onChange(of: settings.data) { _, _ in
                settings.save()
                Haptics.selection()
            }
            .task(id: settings.data.languageChoice) {
                systemModel = await AppleIntelligenceProvider().availability(l)
            }
            .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: CoreMLModelStore.importableTypes) { result in
                switch result {
                case .success(let url):
                    Task {
                        if let installed = await app.modelStore.importModel(from: url, l: l) {
                            Haptics.success()
                            if installed.kind == .textGenerator, installed.hasTokenizer {
                                settings.data.activeCoreMLModelID = installed.id
                            }
                        } else {
                            Haptics.error()
                        }
                    }
                case .failure(let error):
                    app.modelStore.lastError = error.localizedDescription
                }
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

    // MARK: - Action Button

    private var actionButtonSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label(l("Решать одним нажатием", "Solve with one press"), systemImage: "button.programmable")
                    .font(.headline)
                instruction(1, l("Откройте «Настройки» → «Кнопка действия».", "Open Settings → Action Button."))
                instruction(
                    2,
                    l(
                        "iOS 18 и новее: выберите «Элемент управления» → AI Homework → «Решить задание» или «Сканировать задание».",
                        "iOS 18 or later: choose Controls → AI Homework → Solve homework or Scan homework."))
                instruction(
                    3,
                    l(
                        "iOS 17: выберите «Команда» → AI Homework → «Решить задание».",
                        "iOS 17: choose Shortcut → AI Homework → Solve homework."))
                Text(
                    l(
                        "Теперь нажатие кнопки сразу открывает камеру. В «Командах» можно выбрать и другой способ: сканер, галерею, буфер обмена или ввод текста.",
                        "Now a press opens the camera right away. In Shortcuts you can pick another input: scanner, photos, clipboard or typing."
                    )
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
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
                    "Кнопка действия есть на iPhone 15 Pro, iPhone 16 и новее. Эти же действия доступны в Пункте управления, на экране блокировки и через Siri: «Решить задание в AI Homework».",
                    "The Action Button is available on iPhone 15 Pro, iPhone 16 and later. The same actions work in Control Center, on the Lock Screen and with Siri: “Solve homework with AI Homework”."
                ))
        }
    }

    private func instruction(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.orange))
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Models

    private func modelsSection(settings: AppSettings) -> some View {
        Section {
            // Системная модель Apple Intelligence.
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Apple Intelligence", systemImage: "sparkles")
                        .font(.headline)
                    Spacer()
                    if let systemModel {
                        Circle()
                            .fill(systemModel.isAvailable ? Color.green : Color.orange)
                            .frame(width: 10, height: 10)
                    } else {
                        ProgressView()
                    }
                }
                if let systemModel {
                    Text(systemModel.title).font(.subheadline.weight(.semibold))
                    Text(systemModel.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
            Toggle(l("Использовать системную модель", "Use the system model"), isOn: Bindable(settings).data.useSystemModel)

            // Пользовательские модели Core ML.
            ForEach(app.modelStore.models) { model in
                CoreMLModelRow(
                    model: model, isActive: settings.data.activeCoreMLModelID == model.id, l: l
                ) {
                    if model.kind == .textGenerator, model.hasTokenizer {
                        settings.data.activeCoreMLModelID = settings.data.activeCoreMLModelID == model.id ? nil : model.id
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        if settings.data.activeCoreMLModelID == model.id { settings.data.activeCoreMLModelID = nil }
                        app.modelStore.delete(model)
                    } label: {
                        Label(l("Удалить", "Delete"), systemImage: "trash")
                    }
                }
            }

            Button {
                isImporterPresented = true
            } label: {
                HStack {
                    Label(l("Установить модель Core ML", "Install a Core ML model"), systemImage: "square.and.arrow.down")
                    if app.modelStore.isImporting {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(app.modelStore.isImporting)

            if let error = app.modelStore.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text(l("Локальные модели", "On-device models"))
        } footer: {
            Text(
                l(
                    "Математика, физика, химия и информатика решаются точными алгоритмами без всякой модели. Модель нужна только для текстовых заданий (история, литература, обществознание и др.). Поддерживаются: системная модель Apple (iOS 26+, устройства с Apple Intelligence) и собственные языковые модели Core ML — папка с model.mlpackage и tokenizer.json (вход input_ids, выход logits). Классификатор текста Create ML с метками предметов улучшит их определение. Подробности — в README проекта.",
                    "Math, physics, chemistry and computer science are solved by exact algorithms without any model. A model is only needed for text tasks (history, literature, social studies, etc.). Supported: the Apple system model (iOS 26+, Apple Intelligence devices) and your own Core ML language models — a folder with model.mlpackage and tokenizer.json (input_ids input, logits output). A Create ML text classifier with subject labels improves subject detection. See the project README for details."
                ))
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        Section(l("Конфиденциальность", "Privacy")) {
            privacyRow("iphone", l("Фото и задания обрабатываются на устройстве", "Photos and tasks are processed on device"))
            privacyRow("network.slash", l("Ничего не отправляется на серверы", "Nothing is sent to servers"))
            privacyRow("person.crop.circle.badge.xmark", l("Без регистрации и аналитики", "No sign-up and no analytics"))
            privacyRow("key.slash", l("Не нужны API-ключи", "No API keys needed"))
        }
    }

    private func privacyRow(_ systemImage: String, _ text: String) -> some View {
        Label {
            Text(text).font(.subheadline)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(.green)
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}

/// Строка установленной модели.
private struct CoreMLModelRow: View {
    let model: InstalledModel
    let isActive: Bool
    let l: L10n
    let onSelect: () -> Void

    private var kindTitle: String {
        switch model.kind {
        case .textGenerator:
            return model.hasTokenizer ? l("Языковая модель", "Language model") : l("Языковая модель без токенизатора", "Language model, no tokenizer")
        case .subjectClassifier: return l("Определение предмета", "Subject detection")
        case .unsupported: return l("Не поддерживается", "Unsupported")
        }
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: model.kind == .subjectClassifier ? "tag.fill" : "cpu")
                    .foregroundStyle(model.kind == .unsupported ? Color.secondary : Color.purple)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text("\(kindTitle) · \(ByteCountFormatter.string(fromByteCount: model.sizeBytes, countStyle: .file))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !model.summary.isEmpty {
                        Text(model.summary)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                if isActive {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
