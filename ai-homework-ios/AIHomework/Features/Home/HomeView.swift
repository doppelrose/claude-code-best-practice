import SwiftData
import SwiftUI

/// Главный экран.
struct HomeView: View {
    let namespace: Namespace.ID

    @Environment(AppModel.self) private var app
    @Query(sort: \SolvedProblem.createdAt, order: .reverse) private var problems: [SolvedProblem]

    private var l: L10n { app.l }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header.staggered(0)
                hero.staggered(1)
                quickActions.staggered(2)
                if !problems.isEmpty {
                    recentSection.staggered(3)
                }
                subjectsSection.staggered(4)
                historyCard.staggered(5)
                actionButtonCard.staggered(6)
                privacyFooter
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(AnimatedBackground())
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Header

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return l("Доброе утро", "Good morning")
        case 12..<18: return l("Добрый день", "Good afternoon")
        case 18..<23: return l("Добрый вечер", "Good evening")
        default: return l("Доброй ночи", "Good night")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.inkSubtle)
                Text("AI Homework")
                    .font(.displayLarge)
                    .tracking(-0.8)
                    .foregroundStyle(Palette.ink)
            }
            Spacer()
            GlassIconButton(systemImage: "gearshape", size: 42, accessibilityLabel: l("Настройки", "Settings")) {
                Haptics.tap()
                app.isSettingsPresented = true
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        Button {
            app.openCamera()
        } label: {
            VStack(spacing: 18) {
                Group {
                    if app.activeFlow == nil {
                        AIOrb(size: 118)
                            .matchedGeometryEffect(id: "hero-orb", in: namespace)
                    } else {
                        Color.clear.frame(width: 118, height: 118)
                    }
                }
                VStack(spacing: 6) {
                    Text(l("Решить задание", "Solve a task"))
                        .font(.displayMedium)
                        .tracking(-0.5)
                        .foregroundStyle(Palette.ink)
                    Text(
                        l(
                            "Сфотографируйте задание — решение и объяснение появятся за секунды.",
                            "Snap a task — the solution and explanation appear in seconds.")
                    )
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSubtle)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                    Text(l("Открыть камеру", "Open camera"))
                }
                .font(.buttonLabel)
                .foregroundStyle(Palette.onAccent)
                .padding(.horizontal, 22)
                .frame(height: 44)
                .background {
                    RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                        .fill(Palette.accent)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .padding(.horizontal, 20)
            .glassCard(cornerRadius: Theme.panelRadius, interactive: true)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
        .accessibilityLabel(l("Решить задание: открыть камеру", "Solve a task: open camera"))
    }

    // MARK: - Quick actions

    private var quickActions: some View {
        GlassGroup(spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                QuickActionTile(
                    title: l("Из галереи", "From photos"), subtitle: l("Фото или скриншот", "Photo or screenshot"),
                    systemImage: "photo.on.rectangle.angled"
                ) { app.openPhotos() }
                QuickActionTile(
                    title: l("Вставить", "Paste"), subtitle: l("Из буфера обмена", "From clipboard"),
                    systemImage: "doc.on.clipboard"
                ) { app.pasteFromClipboard() }
                QuickActionTile(
                    title: l("Сканер", "Scanner"), subtitle: l("Страница учебника", "Textbook page"),
                    systemImage: "doc.viewfinder"
                ) { app.openScanner() }
                QuickActionTile(
                    title: l("Ввести", "Type"), subtitle: l("Условие текстом", "Task as text"),
                    systemImage: "keyboard"
                ) { app.typeTask() }
            }
        }
    }

    // MARK: - Recent

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: l("Последние решения", "Recent solutions"), actionTitle: l("Все", "All")) {
                app.path.append(.history)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(problems.prefix(10)) { problem in
                        NavigationLink(value: AppRoute.problem(problem.id)) {
                            RecentCard(problem: problem, l: l)
                        }
                        .buttonStyle(.pressable)
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 6)
            }
            .scrollTargetBehavior(.viewAligned)
            .padding(.horizontal, -Theme.screenPadding)
            .contentMargins(.horizontal, Theme.screenPadding, for: .scrollContent)
        }
    }

    // MARK: - Subjects

    private var subjectsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: l("Популярные предметы", "Popular subjects"))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(Subject.featured) { subject in
                    NavigationLink(value: AppRoute.subject(subject)) {
                        HStack(spacing: 12) {
                            SubjectIcon(subject: subject, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(subject.title(l))
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                Text(subject.hasLocalEngine ? l("Точный решатель", "Exact solver") : l("Через нейросеть", "Via AI model"))
                                    .font(.caption)
                                    .foregroundStyle(Palette.inkSubtle)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .glassCard()
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
    }

    // MARK: - History & Action Button

    private var historyCard: some View {
        NavigationLink(value: AppRoute.history) {
            HStack(spacing: 14) {
                CardIcon(systemImage: "clock.arrow.circlepath")
                VStack(alignment: .leading, spacing: 3) {
                    Text(l("История заданий", "Task history"))
                        .font(.cardTitle)
                        .foregroundStyle(Palette.ink)
                    let favorites = problems.filter { $0.isFavorite }.count
                    Text(l("Решено: \(problems.count) · В избранном: \(favorites)", "Solved: \(problems.count) · Favorites: \(favorites)"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSubtle)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.inkTertiary)
            }
            .padding(16)
            .glassCard()
        }
        .buttonStyle(.pressable)
    }

    private var actionButtonCard: some View {
        Button {
            Haptics.tap()
            app.isSettingsPresented = true
        } label: {
            HStack(spacing: 14) {
                CardIcon(systemImage: "button.programmable")
                VStack(alignment: .leading, spacing: 3) {
                    Text(l("Кнопка действия", "Action Button"))
                        .font(.cardTitle)
                        .foregroundStyle(Palette.ink)
                    Text(l("Одно нажатие — скриншот, обведите задание, решение готово", "One press — screenshot, circle the task, get the solution"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSubtle)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.inkTertiary)
            }
            .padding(16)
            .glassCard()
        }
        .buttonStyle(.pressable)
    }

    private var privacyFooter: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
            Text(
                l(
                    "Точные задачи решаются прямо на iPhone. Остальное — в вашей нейросети по API; ключ хранится в Связке ключей.",
                    "Exact tasks are solved right on the iPhone. Everything else goes to your AI model via API; the key stays in the Keychain."))
        }
        .font(.caption)
        .foregroundStyle(Palette.inkTertiary)
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }
}

/// Плитка быстрого действия.
private struct QuickActionTile: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                CardIcon(systemImage: systemImage, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.cardTitle).foregroundStyle(Palette.ink)
                    Text(subtitle).font(.caption).foregroundStyle(Palette.inkSubtle).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .glassCard()
        }
        .buttonStyle(.pressable)
    }
}

/// Карточка недавнего решения.
private struct RecentCard: View {
    let problem: SolvedProblem
    let l: L10n

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SubjectIcon(subject: problem.subject, size: 30)
                Spacer()
                if problem.isFavorite {
                    Image(systemName: "bookmark.fill").foregroundStyle(Palette.inkSubtle).font(.caption)
                }
                Image(systemName: problem.isSolved ? "checkmark.circle.fill" : "questionmark.circle")
                    .foregroundStyle(problem.isSolved ? Palette.success : Palette.inkTertiary)
                    .font(.caption)
            }
            Text(problem.problemText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            Text(problem.isSolved ? problem.answer : l("Не решено", "Not solved"))
                .font(.system(.footnote, design: .monospaced).weight(.medium))
                .foregroundStyle(Palette.inkMuted)
                .lineLimit(1)
        }
        .padding(14)
        .frame(width: 210, height: 150, alignment: .topLeading)
        .glassCard()
    }
}
