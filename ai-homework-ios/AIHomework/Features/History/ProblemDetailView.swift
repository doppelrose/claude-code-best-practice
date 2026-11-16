import SwiftData
import SwiftUI

/// Сохранённое решение из истории.
struct ProblemDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var matches: [SolvedProblem]

    @State private var analysis: TextAnalysis?
    /// Решение и фото раскодируются один раз (`.task`), а не при каждом пересчёте экрана.
    @State private var solution: Solution?
    @State private var image: UIImage?
    @State private var isDecoded = false
    @State private var sharedFile: SharedFile?
    @State private var toast: String?
    @State private var toastKind: ToastKind = .success
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
        .background(AnimatedBackground())
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sharedFile) { file in
            ActivityView(items: [file.url])
                .presentationDetents([.medium, .large])
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Toast(message: toast, kind: toastKind).padding(.bottom, 24)
            }
        }
    }

    private func content(_ problem: SolvedProblem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                problemCard(problem)
                if let solution {
                    SolutionContentView(
                        solution: solution, analysis: analysis, problemText: problem.problemText, l: l,
                        onOpenModels: { app.isSettingsPresented = true },
                        onCopied: { show($0, kind: .success) })
                } else if isDecoded {
                    Text(l("Не удалось прочитать сохранённое решение. Решите задание заново.", "Could not read the saved solution. Please solve the task again."))
                        .foregroundStyle(Palette.inkSubtle)
                }
                HStack(spacing: 10) {
                    GlassButton(title: l("Решить заново", "Solve again"), systemImage: "arrow.clockwise") {
                        reopen(problem, autoSolve: true)
                    }
                    GlassButton(title: "PDF", systemImage: "doc.richtext") {
                        exportPDF(problem)
                    }
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 40)
        }
        .task(id: decodeKey(problem)) {
            await decode(problem)
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Haptics.selection()
                    withAnimation(Theme.bouncy) { problem.isFavorite.toggle() }
                    report(HistoryStore.save(context))
                } label: {
                    Image(systemName: problem.isFavorite ? "bookmark.fill" : "bookmark")
                        .foregroundStyle(problem.isFavorite ? Palette.accentHover : Palette.ink)
                }
                .accessibilityLabel(l("Избранное", "Favorite"))

                Menu {
                    if let solution {
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
                        reopen(problem, autoSolve: false)
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
                if HistoryStore.delete([problem], in: context) {
                    dismiss()
                } else {
                    show(HistoryStore.saveFailedMessage(l), kind: .error)
                }
            }
        }
    }

    private func problemCard(_ problem: SolvedProblem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 240)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            Text(l("Условие", "Task"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.inkSubtle)
            Text(problem.problemText)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Text(problem.createdAt.formatted(.dateTime.day().month(.wide).hour().minute().locale(app.settings.locale)))
                .font(.caption2)
                .foregroundStyle(Palette.inkTertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .padding(.top, 8)
    }

    private func exportPDF(_ problem: SolvedProblem) {
        guard let solution else { return }
        do {
            sharedFile = SharedFile(
                url: try PDFExporter.export(problem: problem.problemText, solution: solution, image: image, date: problem.createdAt, l: l))
            Haptics.success()
        } catch {
            Haptics.error()
            show(l("Не удалось создать PDF", "Could not create the PDF"), kind: .error)
        }
    }

    /// Ключ раскодирования: меняется, когда запись пересохранили («Решить заново») или убрали фото.
    private func decodeKey(_ problem: SolvedProblem) -> String {
        "\(problem.id.uuidString)|\(problem.solutionData.count)|\(problem.answer)|\(problem.thumbnailData?.count ?? -1)"
    }

    private func decode(_ problem: SolvedProblem) async {
        solution = problem.solution
        isDecoded = true
        if [Subject.russian, .english, .literature].contains(problem.subject) {
            analysis = await LanguageTools.analyzeInBackground(problem.problemText, lang: problem.language)
        } else {
            analysis = nil
        }
        // Фото (до 1600 px) раскодируется вне главного потока.
        if let data = problem.imageData {
            let decoded = await Task.detached(priority: .userInitiated) {
                UncheckedSendable(ImageTools.downsampled(data))
            }.value
            guard !Task.isCancelled else { return }
            image = decoded.value
        } else {
            image = nil
        }
    }

    /// «Решить заново» (`autoSolve`) или «Изменить и решить»: тот же текст, сохранённое фото и та же запись истории.
    private func reopen(_ problem: SolvedProblem, autoSolve: Bool) {
        let restored = RestoredProblem(
            recordID: problem.id,
            text: problem.isImageOnly ? "" : problem.problemText,
            subject: problem.subject,
            imageData: problem.imageData,
            autoSolve: autoSolve)
        app.startSolve(.restored(restored))
    }

    private func report(_ succeeded: Bool) {
        if !succeeded { show(HistoryStore.saveFailedMessage(l), kind: .error) }
    }

    private func show(_ message: String, kind: ToastKind) {
        withAnimation(Theme.bouncy) {
            toastKind = kind
            toast = message
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(Theme.spring) {
                if toast == message { toast = nil }
            }
        }
    }
}
