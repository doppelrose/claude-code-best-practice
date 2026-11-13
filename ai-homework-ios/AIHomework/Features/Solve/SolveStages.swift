import SwiftUI

// MARK: - Review

/// Проверка распознанного условия: текст можно исправить, предмет — поменять.
struct ReviewStage: View {
    @Bindable var model: SolveViewModel
    let onSolve: () -> Void

    @Namespace private var chipNamespace
    @FocusState private var isEditing: Bool
    private var l: L10n { model.l }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let image = model.recognizedImage ?? model.image {
                    imagePreview(image)
                }
                if let confidence = model.ocrConfidence {
                    confidenceRow(confidence)
                }
                subjectPicker
                editor
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 6)
            .padding(.bottom, 120)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: l("Решить", "Solve"), systemImage: "sparkles", colors: model.subject.palette + [Theme.brand[2]]) {
                isEditing = false
                onSolve()
            }
            .disabled(!model.canSolve)
            .padding(.horizontal, Theme.screenPadding)
            .padding(.vertical, 12)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(l("Готово", "Done")) { isEditing = false }
            }
        }
    }

    private func imagePreview(_ image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .overlay {
                    // Рамки найденных строк — видно, что именно прочитано.
                    GeometryReader { proxy in
                        ForEach(model.recognizedLines) { line in
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(model.subject.tint.opacity(0.9), lineWidth: 1.5)
                                .background(RoundedRectangle(cornerRadius: 4).fill(model.subject.tint.opacity(0.12)))
                                .frame(
                                    width: line.boundingBox.width * proxy.size.width + 6,
                                    height: line.boundingBox.height * proxy.size.height + 4
                                )
                                .position(
                                    x: line.boundingBox.midX * proxy.size.width,
                                    y: line.boundingBox.midY * proxy.size.height)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .frame(maxHeight: 220)
                .frame(maxWidth: .infinity)
            if model.hasImage {
                Button {
                    model.reselectRegion()
                } label: {
                    Label(l("Выбрать другую область", "Choose another area"), systemImage: "crop")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(12)
        .glassCard()
    }

    private func confidenceRow(_ confidence: Double) -> some View {
        let percent = Int((confidence * 100).rounded())
        let (title, color): (String, Color) =
            confidence >= 0.85
            ? (l("Распознано уверенно", "Recognized confidently"), .green)
            : confidence >= 0.6
                ? (l("Проверьте текст", "Please check the text"), .orange)
                : (l("Распознано неуверенно — исправьте текст", "Low confidence — please fix the text"), .red)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "text.viewfinder").foregroundStyle(color)
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(percent)%").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            if model.usedMathPass {
                Text(l("Найдены формулы — распознано в режиме без автозамены слов.", "Formulas detected — recognized without word autocorrection."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var subjectPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(l("Предмет", "Subject")).font(.headline)
                Spacer()
                if model.isSubjectManual {
                    Button(l("Определить автоматически", "Detect automatically")) {
                        model.resetSubjectToAutomatic()
                    }
                    .font(.caption.weight(.semibold))
                } else {
                    Label(l("определён автоматически", "detected automatically"), systemImage: "wand.and.stars")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Subject.allCases) { subject in
                            subjectChip(subject)
                                .id(subject)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: model.subject) { _, newValue in
                    withAnimation(Theme.spring) { proxy.scrollTo(newValue, anchor: .center) }
                }
            }
        }
    }

    private func subjectChip(_ subject: Subject) -> some View {
        let isSelected = model.subject == subject
        return Button {
            model.chooseSubject(subject)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: subject.symbolName).font(.caption.weight(.bold))
                Text(subject.title(l)).font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background {
                if isSelected {
                    // Одна и та же «капсула» плавно переезжает между чипами.
                    Capsule(style: .continuous)
                        .fill(subject.gradient)
                        .matchedGeometryEffect(id: "subject-chip", in: chipNamespace)
                } else {
                    Capsule(style: .continuous).fill(Color.primary.opacity(0.07))
                }
            }
        }
        .buttonStyle(.pressable)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l("Условие", "Task")).font(.headline)
            ZStack(alignment: .topLeading) {
                if model.text.isEmpty {
                    Text(l("Введите или исправьте условие задания", "Type or correct the task"))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                }
                TextEditor(text: $model.text)
                    .focused($isEditing)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 130)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.sentences)
            }
            .font(.body)
            .padding(12)
            .contentCard(cornerRadius: 20)
            .onChange(of: model.text) { _, _ in
                model.textDidChange()
            }
            Text(l("Формулы пишите так: x^2 − 5x + 6 = 0, sqrt(16), 3/4.", "Write formulas like: x^2 − 5x + 6 = 0, sqrt(16), 3/4."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Result

/// Результат: условие, решение и панель действий.
struct ResultStage: View {
    let model: SolveViewModel
    let onToast: (String) -> Void
    let onExportPDF: () -> Void
    let onResolve: () -> Void

    @Environment(AppModel.self) private var app
    private var l: L10n { model.l }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                problemCard
                if let solution = model.solution {
                    SolutionContentView(
                        solution: solution, analysis: model.analysis, problemText: model.text, l: l,
                        onOpenModels: {
                            app.isSettingsPresented = true
                        },
                        onCopied: onToast)
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 6)
            .padding(.bottom, 130)
        }
        .safeAreaInset(edge: .bottom) {
            actionBar
        }
    }

    private var problemCard: some View {
        HStack(alignment: .top, spacing: 12) {
            if let image = model.recognizedImage ?? model.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(l("Условие", "Task")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(model.text.trimmed)
                    .font(.callout)
                    .lineLimit(5)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 22)
    }

    private var actionBar: some View {
        GlassGroup {
            HStack(spacing: 0) {
                barButton(l("Изменить", "Edit"), "pencil") { model.editProblem() }
                barButton(l("Заново", "Retry"), "arrow.clockwise") { onResolve() }
                if let solution = model.solution {
                    ShareLink(item: solution.plainText(problem: model.text.trimmed, l)) {
                        barLabel(l("Поделиться", "Share"), "square.and.arrow.up")
                    }
                    .buttonStyle(.pressable)
                }
                barButton("PDF", "doc.richtext") { onExportPDF() }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .glassCapsule()
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.bottom, 6)
    }

    private func barLabel(_ title: String, _ systemImage: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage).font(.system(size: 18, weight: .semibold))
            Text(title).font(.caption2.weight(.medium))
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func barButton(_ title: String, _ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            barLabel(title, systemImage)
        }
        .buttonStyle(.pressable)
    }
}
