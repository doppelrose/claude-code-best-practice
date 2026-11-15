import SwiftData
import SwiftUI

/// Страница предмета: что умеет приложение, примеры и история по предмету.
struct SubjectView: View {
    let subject: Subject

    @Environment(AppModel.self) private var app
    @Query(sort: \SolvedProblem.createdAt, order: .reverse) private var problems: [SolvedProblem]
    @State private var hasModel = false

    private var l: L10n { app.l }
    private var subjectProblems: [SolvedProblem] {
        problems.filter { $0.subjectRaw == subject.rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header.staggered(0)
                actions.staggered(1)
                capabilities.staggered(2)
                if !subject.examples(l).isEmpty {
                    examples.staggered(3)
                }
                if !subjectProblems.isEmpty {
                    history.staggered(4)
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 40)
        }
        .background(AnimatedBackground())
        .navigationTitle(subject.title(l))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            hasModel = await app.coordinator.hasLanguageModel()
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            SubjectIcon(subject: subject, size: 56)
            VStack(alignment: .leading, spacing: 6) {
                Text(subject.title(l))
                    .font(.displayMedium)
                    .tracking(-0.5)
                    .foregroundStyle(Palette.ink)
                statusBadge
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if subject.hasLocalEngine {
            Label(l("Точный решатель на устройстве", "Exact on-device solver"), systemImage: "checkmark.seal.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(Palette.success)
        } else if hasModel {
            Label(l("Ответы нейросети", "AI model answers"), systemImage: "sparkles")
                .font(.caption.weight(.medium))
                .foregroundStyle(Palette.accentHover)
        } else {
            Label(l("Нужна нейросеть", "Needs an AI model"), systemImage: "exclamationmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(Palette.inkSubtle)
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            PrimaryButton(title: l("Сфотографировать", "Take a photo"), systemImage: "camera.fill") {
                app.openCamera()
            }
            GlassButton(title: l("Текстом", "Type"), systemImage: "keyboard") {
                app.typeTask(subject: subject)
            }
            .frame(maxWidth: 140)
        }
    }

    private var capabilities: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(l("Что умеет приложение", "What the app can do"))
                .font(.cardTitle)
            ForEach(Array(subject.capabilities(l).enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Palette.inkSubtle)
                        .padding(.top, 3)
                    Text(item)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !subject.hasLocalEngine, !hasModel {
                Button {
                    app.isSettingsPresented = true
                } label: {
                    Label(l("Подключить нейросеть", "Connect an AI model"), systemImage: "gearshape")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.pressable)
                .padding(.top, 4)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var examples: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: l("Попробуйте пример", "Try an example"))
            ForEach(subject.examples(l), id: \.self) { example in
                Button {
                    app.startSolve(.text(example, subject: subject))
                } label: {
                    HStack(spacing: 12) {
                        Text(example)
                            .font(.subheadline)
                            .foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Palette.inkSubtle)
                    }
                    .padding(14)
                    .glassCard(interactive: true)
                }
                .buttonStyle(.pressable)
            }
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: l("Ваши задания", "Your tasks"))
            ForEach(subjectProblems.prefix(5)) { problem in
                NavigationLink(value: AppRoute.problem(problem.id)) {
                    ProblemRow(problem: problem, l: l)
                        .padding(12)
                        .glassCard()
                }
                .buttonStyle(.pressable)
            }
        }
    }
}
