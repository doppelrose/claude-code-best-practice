import SwiftUI

/// Содержимое решения: ответ, объяснение, шаги, формулы, оговорки.
/// Используется и на экране результата, и в карточке истории.
struct SolutionContentView: View {
    let solution: Solution
    let analysis: TextAnalysis?
    let problemText: String
    let l: L10n
    /// Открыть настройки нейросети (для нерешённых заданий).
    var onOpenModels: (() -> Void)?
    var onCopied: ((String) -> Void)?
    /// Ответа нет из-за связи с нейросетью (сеть, тайм-аут, приложение свернули) — причина для пользователя.
    var connectionIssue: String?
    /// «Повторить» — для ошибки связи это главное действие вместо «Настроить нейросеть».
    var onRetry: (() -> Void)?

    @State private var collapsedSteps: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header.staggered(0)
            answerCard.staggered(1)

            if !solution.interpretedProblem.isEmpty, solution.interpretedProblem != problemText.trimmed {
                infoCard(title: l("Как понято условие", "How the task was read"), systemImage: "text.viewfinder") {
                    FormulaBlock(text: solution.interpretedProblem, tint: solution.subject.tint)
                }
                .staggered(2)
            }

            if solution.isSolved, !solution.explanation.isEmpty {
                infoCard(title: l("Объяснение", "Explanation"), systemImage: "lightbulb.fill") {
                    Text(solution.explanation)
                        .font(.body)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .staggered(3)
            }

            if !solution.steps.isEmpty {
                stepsSection.staggered(4)
            }

            if !solution.formulas.isEmpty {
                infoCard(title: l("Формулы", "Formulas"), systemImage: "function") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(solution.formulas.enumerated()), id: \.offset) { _, formula in
                            FormulaBlock(text: formula, tint: solution.subject.tint)
                        }
                    }
                }
                .staggered(5)
            }

            if let analysis, !analysis.isEmpty {
                TextToolsSection(analysis: analysis, sourceText: problemText, l: l)
                    .staggered(6)
            }

            if !solution.notes.isEmpty {
                notesCard.staggered(7)
            }
        }
    }

    // MARK: - Header

    /// Ответ дала языковая модель: тогда `problemType` — подпись источника («Ответ модели …»), а не тип задачи.
    private var isModelAnswer: Bool {
        solution.engine == .remoteAPI || solution.engine == .appleIntelligence
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SubjectBadge(subject: solution.subject, l: l)
                ReliabilityBadge(reliability: solution.reliability, l: l)
            }
            if isModelAnswer {
                // Имя модели — второстепенная подпись; главный элемент экрана — ответ.
                if !solution.problemType.isEmpty {
                    Label(solution.problemType, systemImage: "sparkles")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Palette.inkSubtle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(solution.problemType)
                    .font(.headlineTitle)
                    .foregroundStyle(Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(solution.reliability.detail(l))
                .font(.footnote)
                .foregroundStyle(Palette.inkSubtle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Answer

    @ViewBuilder
    private var answerCard: some View {
        if solution.isSolved {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(l("Ответ", "Answer"), systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Palette.accentHover)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = solution.answer
                        Haptics.success()
                        onCopied?(l("Ответ скопирован", "Answer copied"))
                    } label: {
                        Label(l("Копировать", "Copy"), systemImage: "doc.on.doc")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Palette.inkMuted)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .glassCapsule()
                    }
                    .buttonStyle(.pressable)
                }
                Text(solution.answer)
                    .font(.system(.title2).weight(.semibold))
                    .tracking(-0.4)
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
            .glassCard(interactive: true)
            .overlay(alignment: .leading) {
                // Тонкая акцентная полоса слева — единственный цвет в карточке ответа.
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Palette.accent)
                    .frame(width: 2)
                    .padding(.vertical, 18)
            }
        } else if let connectionIssue {
            connectionCard(connectionIssue)
        } else {
            // Задание не решено — честно объясняем почему.
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: solution.reliability == .toolsOnly ? "wrench.and.screwdriver.fill" : "hand.raised.fill")
                        .font(.title3)
                        .foregroundStyle(solution.reliability.color)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(solution.reliability.color.opacity(0.14)))
                    Text(l("Ответа нет — и это честно", "No answer — and that is honest"))
                        .font(.cardTitle)
                }
                Text(solution.explanation)
                    .font(.callout)
                    .foregroundStyle(Palette.inkSubtle)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let onOpenModels {
                    GlassButton(title: l("Настроить нейросеть", "Set up the AI model"), systemImage: "gearshape", action: onOpenModels)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentCard()
        }
    }

    /// Связь с нейросетью не удалась: это не «задание не решаемо», поэтому главное действие — «Повторить».
    private func connectionCard(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.title3)
                    .foregroundStyle(Palette.inkMuted)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Palette.surface3))
                Text(l("Нет связи с нейросетью", "No connection to the AI model"))
                    .font(.cardTitle)
            }
            Text(reason)
                .font(.callout)
                .foregroundStyle(Palette.inkSubtle)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Text(l("Проверьте интернет и попробуйте ещё раз — настройки нейросети менять не нужно.", "Check the internet connection and try again — no need to change the AI model settings."))
                .font(.footnote)
                .foregroundStyle(Palette.inkSubtle)
                .fixedSize(horizontal: false, vertical: true)
            if let onRetry {
                PrimaryButton(title: l("Повторить", "Try again"), systemImage: "arrow.clockwise", action: onRetry)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard()
    }

    // MARK: - Steps

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(l("Решение по шагам", "Step by step"), systemImage: "list.number")
                    .font(.cardTitle)
                Spacer()
                Button {
                    Haptics.tap()
                    withAnimation(Theme.spring) {
                        if collapsedSteps.count == solution.steps.count {
                            collapsedSteps = []
                        } else {
                            collapsedSteps = Set(solution.steps.indices)
                        }
                    }
                } label: {
                    Text(collapsedSteps.count == solution.steps.count ? l("Развернуть", "Expand") : l("Свернуть", "Collapse"))
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.pressable)
            }
            ForEach(Array(solution.steps.enumerated()), id: \.offset) { index, step in
                StepCard(
                    number: index + 1, step: step, tint: solution.subject.tint, isLast: index == solution.steps.count - 1,
                    isExpanded: !collapsedSteps.contains(index)
                ) {
                    Haptics.tap()
                    withAnimation(Theme.spring) {
                        if collapsedSteps.contains(index) {
                            collapsedSteps.remove(index)
                        } else {
                            collapsedSteps.insert(index)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Notes

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(solution.notes.enumerated()), id: \.offset) { _, note in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Palette.inkSubtle)
                        .font(.subheadline)
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: solution.engine == .remoteAPI ? "network" : "lock.shield").font(.caption2)
                Text(
                    solution.engine == .remoteAPI
                        ? l("Решено нейросетью по API", "Solved by an AI model via API")
                        : l("Решено на устройстве · \(solution.engine.title(l))", "Solved on device · \(solution.engine.title(l))")
                )
                .font(.caption2)
            }
            .foregroundStyle(Palette.inkTertiary)
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .insetSurface(cornerRadius: Theme.cardRadius)
    }

    private func infoCard<Content: View>(title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.cardTitle)
                .foregroundStyle(Palette.ink)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard()
    }
}

/// Карточка одного шага: номер, заголовок, формула и пояснение. Плавно сворачивается.
private struct StepCard: View {
    let number: Int
    let step: SolutionStep
    let tint: Color
    let isLast: Bool
    let isExpanded: Bool
    let onToggle: () -> Void

    private var hasBody: Bool {
        !(step.formula ?? "").isEmpty || !step.detail.isEmpty
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Номер шага и соединительная линия.
            VStack(spacing: 4) {
                Text("\(number)")
                    .font(.system(.footnote, design: .monospaced).weight(.medium))
                    .foregroundStyle(Palette.inkMuted)
                    .frame(width: 28, height: 28)
                    .modifier(SurfaceStyle(shape: Circle(), level: .three, strongBorder: true))
                if !isLast {
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(Palette.hairline)
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Button(action: onToggle) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(step.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        if hasBody {
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Palette.inkTertiary)
                                .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!hasBody)

                if isExpanded, hasBody {
                    VStack(alignment: .leading, spacing: 8) {
                        if let formula = step.formula, !formula.isEmpty {
                            FormulaBlock(text: formula, tint: tint)
                        }
                        if !step.detail.isEmpty {
                            Text(step.detail)
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSubtle)
                                .lineSpacing(2)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                }
            }
            .padding(.bottom, isLast ? 0 : 10)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard()
    }
}
