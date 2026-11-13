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

    private var l: L10n { app.l }

    private var filtered: [SolvedProblem] {
        problems.filter { problem in
            (!favoritesOnly || problem.isFavorite)
                && (subjectFilter == nil || problem.subjectRaw == subjectFilter?.rawValue)
                && problem.matches(search)
        }
    }

    private var sections: [(day: Date, items: [SolvedProblem])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.createdAt) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    private var usedSubjects: [Subject] {
        let raw = Set(problems.map { $0.subjectRaw })
        return Subject.allCases.filter { raw.contains($0.rawValue) }
    }

    var body: some View {
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

            ForEach(sections, id: \.day) { section in
                Section {
                    ForEach(section.items) { problem in
                        NavigationLink(value: AppRoute.problem(problem.id)) {
                            ProblemRow(problem: problem, l: l)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                delete(problem)
                            } label: {
                                Label(l("Удалить", "Delete"), systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                toggleFavorite(problem)
                            } label: {
                                Label(
                                    problem.isFavorite ? l("Убрать", "Unfavorite") : l("В избранное", "Favorite"),
                                    systemImage: problem.isFavorite ? "bookmark.slash" : "bookmark")
                            }
                            .tint(.yellow)
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
                                delete(problem)
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
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        isClearConfirmationPresented = true
                    } label: {
                        Label(l("Очистить историю", "Clear history"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(problems.isEmpty)
            }
        }
        .confirmationDialog(
            l("Удалить все задания?", "Delete all tasks?"), isPresented: $isClearConfirmationPresented, titleVisibility: .visible
        ) {
            Button(l("Удалить всё", "Delete all"), role: .destructive) { clearAll() }
        } message: {
            Text(l("Это действие нельзя отменить.", "This cannot be undone."))
        }
    }

    private var subjectChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: l("Все предметы", "All subjects"), isSelected: subjectFilter == nil, colors: Theme.brand) {
                    subjectFilter = nil
                }
                ForEach(usedSubjects) { subject in
                    chip(title: subject.title(l), isSelected: subjectFilter == subject, colors: subject.palette) {
                        subjectFilter = subjectFilter == subject ? nil : subject
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func chip(title: String, isSelected: Bool, colors: [Color], action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            withAnimation(Theme.spring, action)
        } label: {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background {
                    Capsule(style: .continuous)
                        .fill(isSelected ? AnyShapeStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(Color.primary.opacity(0.07)))
                }
        }
        .buttonStyle(.pressable)
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
        try? context.save()
    }

    private func delete(_ problem: SolvedProblem) {
        Haptics.warning()
        withAnimation(Theme.spring) { context.delete(problem) }
        try? context.save()
    }

    private func clearAll() {
        Haptics.warning()
        withAnimation(Theme.spring) {
            for problem in problems { context.delete(problem) }
        }
        try? context.save()
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
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(problem.isSolved ? problem.answer : l("Не решено", "Not solved"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(problem.isSolved ? problem.subject.tint : Color.secondary)
                    .lineLimit(1)
                Text(problem.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            if problem.isFavorite {
                Image(systemName: "bookmark.fill")
                    .foregroundStyle(.yellow)
                    .font(.footnote)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = problem.thumbnailData, let image = UIImage(data: data) {
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
