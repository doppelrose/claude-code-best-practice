import SwiftData
import SwiftUI

/// Сохранённое решение из истории.
struct ProblemDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var matches: [SolvedProblem]

    @State private var analysis: TextAnalysis?
    @State private var sharedFile: SharedFile?
    @State private var toast: String?
    @State private var isDeleteConfirmationPresented = false

    private var l: L10n { app.l }

    init(problemID: UUID) {
        let id = problemID
        _matches = Query(filter: #Predicate<SolvedProblem> { $0.id == id })
    }

    var body: some View {
        Group {
            if let problem = matches.first {
                content(problem)
            } else {
                ContentUnavailableView(l("Задание удалено", "The task was deleted"), systemImage: "trash")
            }
        }
        .background(AnimatedBackground(colors: matches.first?.subject.palette ?? Theme.brand, intensity: 0.6))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sharedFile) { file in
            ActivityView(items: [file.url])
                .presentationDetents([.medium, .large])
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Toast(message: toast).padding(.bottom, 24)
            }
        }
    }

    private func content(_ problem: SolvedProblem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                problemCard(problem)
                if let solution = problem.solution {
                    SolutionContentView(
                        solution: solution, analysis: analysis, problemText: problem.problemText, l: l,
                        onOpenModels: { app.isSettingsPresented = true },
                        onCopied: { show($0) })
                } else {
                    Text(l("Не удалось прочитать сохранённое решение. Решите задание заново.", "Could not read the saved solution. Please solve the task again."))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    GlassButton(title: l("Решить заново", "Solve again"), systemImage: "arrow.clockwise") {
                        app.startSolve(.text(problem.problemText, subject: problem.subject))
                    }
                    GlassButton(title: "PDF", systemImage: "doc.richtext") {
                        exportPDF(problem)
                    }
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 40)
        }
        .task(id: problem.id) {
            if [Subject.russian, .english, .literature].contains(problem.subject) {
                analysis = LanguageTools.analyze(problem.problemText, lang: problem.language)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Haptics.selection()
                    withAnimation(Theme.bouncy) { problem.isFavorite.toggle() }
                    try? context.save()
                } label: {
                    Image(systemName: problem.isFavorite ? "bookmark.fill" : "bookmark")
                        .foregroundStyle(problem.isFavorite ? Color.yellow : Color.primary)
                }
                .accessibilityLabel(l("Избранное", "Favorite"))

                Menu {
                    if let solution = problem.solution {
                        ShareLink(item: solution.plainText(problem: problem.problemText, l)) {
                            Label(l("Поделиться текстом", "Share as text"), systemImage: "square.and.arrow.up")
                        }
                    }
                    Button {
                        exportPDF(problem)
                    } label: {
                        Label(l("Экспорт в PDF", "Export to PDF"), systemImage: "doc.richtext")
                    }
                    Button {
                        app.startSolve(.text(problem.problemText, subject: problem.subject))
                    } label: {
                        Label(l("Изменить и решить", "Edit and solve"), systemImage: "pencil")
                    }
                    Divider()
                    Button(role: .destructive) {
                        isDeleteConfirmationPresented = true
                    } label: {
                        Label(l("Удалить", "Delete"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(l("Удалить задание?", "Delete this task?"), isPresented: $isDeleteConfirmationPresented, titleVisibility: .visible) {
            Button(l("Удалить", "Delete"), role: .destructive) {
                context.delete(problem)
                try? context.save()
                dismiss()
            }
        }
    }

    private func problemCard(_ problem: SolvedProblem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let data = problem.imageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 240)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            Text(l("Условие", "Task"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(problem.problemText)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Text(problem.createdAt.formatted(.dateTime.day().month(.wide).hour().minute().locale(app.settings.locale)))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 22)
        .padding(.top, 8)
    }

    private func exportPDF(_ problem: SolvedProblem) {
        guard let solution = problem.solution else { return }
        let image = problem.imageData.flatMap { UIImage(data: $0) }
        do {
            sharedFile = SharedFile(
                url: try PDFExporter.export(problem: problem.problemText, solution: solution, image: image, date: problem.createdAt, l: l))
            Haptics.success()
        } catch {
            Haptics.error()
            show(l("Не удалось создать PDF", "Could not create the PDF"))
        }
    }

    private func show(_ message: String) {
        withAnimation(Theme.bouncy) { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(Theme.spring) {
                if toast == message { toast = nil }
            }
        }
    }
}
