import SwiftData
import SwiftUI

/// История заданий: поиск, избранное, фильтр по предмету, группировка по дням.
struct HistoryView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \SolvedProblem.createdAt, order: .reverse) private var problems: [SolvedProblem]

    @State private var search = ""
    @State private var favoritesOnly = false
    @State private var subjectFilter: Subject?
    @State private var isClearConfirmationPresented = false
    /// Запись, удаление которой ждёт подтверждения.
    @State private var pendingDeletion: SolvedProblem?
    @State private var errorMessage: String?

    private var l: L10n { app.l }

    private var filtered: [SolvedProblem] {
        problems.filter { problem in
            (!favoritesOnly || problem.isFavorite)
                && (subjectFilter == nil || problem.subjectRaw == subjectFilter?.rawValue)
                && problem.matches(search)
        }
    }

    /// Включён ли фильтр: тогда «Удалить» касается только показанных заданий.
    private var isFiltering: Bool {
        favoritesOnly || subjectFilter != nil || !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func sections(of items: [SolvedProblem]) -> [(day: Date, items: [SolvedProblem])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: items) { calendar.startOfDay(for: $0.createdAt) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    private var usedSubjects: [Subject] {
        let raw = Set(problems.map { $0.subjectRaw })
        return Subject.allCases.filter { raw.contains($0.rawValue) }
    }

    var body: some View {
        // Фильтр считается один раз за проход.
        let visible = filtered
        List {
            Section {
                Picker(l("Показать", "Show"), selection: $favoritesOnly.animation(Theme.spring)) {
                    Text(l("Все", "All")).tag(false)
                    Text(l("Избранное", "Favorites")).tag(true)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

                if usedSubjects.count > 1 {
                    subjectChips
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
                }
            }

            ForEach(Self.sections(of: visible), id: \.day) { section in
                Section {
                    ForEach(section.items) { problem in
                        NavigationLink(value: AppRoute.problem(problem.id)) {
                            ProblemRow(problem: problem, l: l)
                        }
                        // Полный свайп не удаляет сразу: удаление всегда подтверждается.
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                pendingDeletion = problem
                            } label: {
                                Label(l("Удалить", "Delete"), systemImage: "trash")
                            }
                            .tint(.red)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                toggleFavorite(problem)
                            } label: {
                                Label(
                                    problem.isFavorite ? l("Убрать", "Unfavorite") : l("В избранное", "Favorite"),
                                    systemImage: problem.isFavorite ? "bookmark.slash" : "bookmark")
                            }
                            .tint(Palette.accent)
                        }
                        .contextMenu {
                            Button {
                                toggleFavorite(problem)
                            } label: {
                                Label(
                                    problem.isFavorite ? l("Убрать из избранного", "Remove from favorites") : l("В избранное", "Add to favorites"),
                                    systemImage: "bookmark")
                            }
                            Button {
                                UIPasteboard.general.string = problem.answer
                                Haptics.success()
                            } label: {
                                Label(l("Скопировать ответ", "Copy answer"), systemImage: "doc.on.doc")
                            }
                            .disabled(!problem.isSolved)
                            Button(role: .destructive) {
                                pendingDeletion = problem
                            } label: {
                                Label(l("Удалить", "Delete"), systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text(dayTitle(section.day))
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AnimatedBackground(intensity: 0.6))
        .searchable(text: $search, prompt: l("Поиск по условию и ответу", "Search tasks and answers"))
        .navigationTitle(l("История", "History"))
        .overlay {
            if problems.isEmpty {
                ContentUnavailableView {
                    Label(l("Пока пусто", "Nothing yet"), systemImage: "clock")
                } description: {
                    Text(l("Решённые задания появятся здесь.", "Solved tasks will appear here."))
                } actions: {
                    Button(l("Решить задание", "Solve a task")) { app.openCamera() }
                        .buttonStyle(.borderedProminent)
                }
            } else if visible.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        isClearConfirmationPresented = true
                    } label: {
                        if isFiltering {
                            Label(l("Удалить показанные (\(visible.count))", "Delete shown (\(visible.count))"), systemImage: "trash")
                        } else {
                            Label(l("Очистить историю", "Clear history"), systemImage: "trash")
                        }
                    }
                    .disabled(visible.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(problems.isEmpty)
            }
        }
        .confirmationDialog(
            isFiltering
                ? l("Удалить показанные задания: \(visible.count)?", "Delete the \(visible.count) shown tasks?")
                : l("Удалить все задания?", "Delete all tasks?"),
            isPresented: $isClearConfirmationPresented, titleVisibility: .visible
        ) {
            Button(isFiltering ? l("Удалить показанные", "Delete shown") : l("Удалить всё", "Delete all"), role: .destructive) {
                clearAll(isFiltering ? visible : nil)
            }
        } message: {
            Text(
                isFiltering
                    ? l(
                        "Будут удалены только задания, которые сейчас показаны с учётом фильтра и поиска. Остальные останутся. Это действие нельзя отменить.",
                        "Only the tasks shown with the current filter and search will be deleted. The rest stay. This cannot be undone.")
                    : l("Это действие нельзя отменить.", "This cannot be undone."))
        }
        .confirmationDialog(
            l("Удалить задание?", "Delete this task?"),
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button(l("Удалить", "Delete"), role: .destructive) {
                if let problem = pendingDeletion { delete(problem) }
                pendingDeletion = nil
            }
        } message: {
            if pendingDeletion?.isFavorite == true {
                Text(l("Это задание в избранном. Это действие нельзя отменить.", "This task is in favorites. This cannot be undone."))
            } else {
                Text(l("Это действие нельзя отменить.", "This cannot be undone."))
            }
        }
        .alert(
            l("Не получилось", "Something went wrong"),
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var subjectChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: l("Все предметы", "All subjects"), isSelected: subjectFilter == nil) {
                    subjectFilter = nil
                }
                ForEach(usedSubjects) { subject in
                    chip(title: subject.title(l), isSelected: subjectFilter == subject) {
                        subjectFilter = subjectFilter == subject ? nil : subject
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        FilterChip(title: title, isSelected: isSelected) {
            Haptics.selection()
            withAnimation(Theme.spring, action)
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return l("Сегодня", "Today") }
        if calendar.isDateInYesterday(day) { return l("Вчера", "Yesterday") }
        return day.formatted(.dateTime.day().month(.wide).year().locale(app.settings.locale))
    }

    private func toggleFavorite(_ problem: SolvedProblem) {
        Haptics.selection()
        withAnimation(Theme.spring) { problem.isFavorite.toggle() }
        report(HistoryStore.save(context))
    }

    private func delete(_ problem: SolvedProblem) {
        Haptics.warning()
        var succeeded = false
        withAnimation(Theme.spring) { succeeded = HistoryStore.delete([problem], in: context) }
        report(succeeded)
    }

    /// `items == nil` — вся история; иначе только показанные с учётом фильтра.
    private func clearAll(_ items: [SolvedProblem]?) {
        Haptics.warning()
        var succeeded = false
        withAnimation(Theme.spring) {
            if let items {
                succeeded = HistoryStore.delete(items, in: context)
            } else {
                succeeded = HistoryStore.deleteAll(in: context)
            }
        }
        report(succeeded)
    }

    private func report(_ succeeded: Bool) {
        if !succeeded { errorMessage = HistoryStore.saveFailedMessage(l) }
    }
}

/// Раскодированные миниатюры истории: JPEG не декодируется заново при каждом пересчёте строки.
@MainActor
enum ThumbnailCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 300
        return cache
    }()

    static func image(for problem: SolvedProblem) -> UIImage? {
        guard let data = problem.thumbnailData else { return nil }
        // Размер данных в ключе: после пересохранения или удаления фото старая картинка не покажется.
        let key = "\(problem.id.uuidString)-\(data.count)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

/// Строка задания в списках.
struct ProblemRow: View {
    let problem: SolvedProblem
    let l: L10n

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                Text(problem.problemText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(problem.isSolved ? problem.answer : l("Не решено", "Not solved"))
                    .font(.system(.footnote, design: .monospaced).weight(.medium))
                    .foregroundStyle(problem.isSolved ? Palette.inkMuted : Palette.inkTertiary)
                    .lineLimit(1)
                Text(problem.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(Palette.inkTertiary)
            }
            Spacer(minLength: 0)
            if problem.isFavorite {
                Image(systemName: "bookmark.fill")
                    .foregroundStyle(Palette.inkSubtle)
                    .font(.footnote)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = ThumbnailCache.image(for: problem) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    SubjectIcon(subject: problem.subject, size: 20)
                        .offset(x: 4, y: 4)
                }
        } else {
            SubjectIcon(subject: problem.subject, size: 48)
        }
    }
}
