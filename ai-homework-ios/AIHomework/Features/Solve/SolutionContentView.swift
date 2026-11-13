import SwiftUI

/// Содержимое решения: ответ, объяснение, шаги, формулы, оговорки.
/// Используется и на экране результата, и в карточке истории.
struct SolutionContentView: View {
    let solution: Solution
    let analysis: TextAnalysis?
    let problemText: String
    let l: L10n
    /// Открыть экран локальных моделей (для нерешённых заданий).
    var onOpenModels: (() -> Void)?
    var onCopied: ((String) -> Void)?

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

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SubjectBadge(subject: solution.subject, l: l)
                ReliabilityBadge(reliability: solution.reliability, l: l)
            }
            Text(solution.problemType)
                .font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(solution.reliability.detail(l))
                .font(.footnote)
                .foregroundStyle(.secondary)
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
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    Button {
                        UIPasteboard.general.string = solution.answer
                        Haptics.success()
                        onCopied?(l("Ответ скопирован", "Answer copied"))
                    } label: {
                        Label(l("Копировать", "Copy"), systemImage: "doc.on.doc")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color.white.opacity(0.22)))
                    }
                    .buttonStyle(.pressable)
                }
                Text(solution.answer)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
            .background {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(solution.subject.gradient)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.22), Color.white.opacity(0)], startPoint: .top, endPoint: .center))
                    }
                    .shadow(color: solution.subject.tint.opacity(0.4), radius: 20, x: 0, y: 12)
            }
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
                        .font(.headline)
                }
                Text(solution.explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let onOpenModels {
                    GlassButton(title: l("Локальные модели", "On-device models"), systemImage: "cpu", action: onOpenModels)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentCard()
        }
    }

    // MARK: - Steps

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(l("Решение по шагам", "Step by step"), systemImage: "list.number")
                    .font(.headline)
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
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill").font(.caption2)
                Text(l("Решено на устройстве · \(solution.engine.title(l))", "Solved on device · \(solution.engine.title(l))"))
                    .font(.caption2)
            }
            .foregroundStyle(.tertiary)
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.smallRadius + 4, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        }
    }

    private func infoCard<Content: View>(title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
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
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(tint))
                if !isLast {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(tint.opacity(0.25))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Button(action: onToggle) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(step.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        if hasBody {
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
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
                                .foregroundStyle(.secondary)
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
        .contentCard(cornerRadius: 20)
    }
}
