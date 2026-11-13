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
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text("AI Homework")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    Image(systemName: "sparkles")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.brandGradient)
                }
            }
            Spacer()
            GlassIconButton(systemImage: "gearshape.fill", size: 46, accessibilityLabel: l("Настройки", "Settings")) {
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
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .foregroundStyle(.primary)
                    Text(
                        l(
                            "Сфотографируйте задание — решение и объяснение появятся за секунды.",
                            "Snap a task — the solution and explanation appear in seconds.")
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                    Text(l("Открыть камеру", "Open camera"))
                }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 13)
                .background {
                    Capsule(style: .continuous)
                        .fill(Theme.brandGradient)
                        .shadow(color: Theme.brand[1].opacity(0.45), radius: 14, y: 7)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .padding(.horizontal, 20)
            .glassCard(cornerRadius: 34, interactive: true)
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
                    systemImage: "photo.on.rectangle.angled", colors: [Color(hex: 0x0EA5E9), Color(hex: 0x6366F1)]
                ) { app.openPhotos() }
                QuickActionTile(
                    title: l("Вставить", "Paste"), subtitle: l("Из буфера обмена", "From clipboard"),
                    systemImage: "doc.on.clipboard.fill", colors: [Color(hex: 0xF59E0B), Color(hex: 0xEF4444)]
                ) { app.pasteFromClipboard() }
                QuickActionTile(
                    title: l("Сканер", "Scanner"), subtitle: l("Страница учебника", "Textbook page"),
                    systemImage: "doc.viewfinder.fill", colors: [Color(hex: 0x10B981), Color(hex: 0x14B8A6)]
                ) { app.openScanner() }
                QuickActionTile(
                    title: l("Ввести", "Type"), subtitle: l("Условие текстом", "Task as text"),
                    systemImage: "keyboard.fill", colors: [Color(hex: 0xA855F7), Color(hex: 0xEC4899)]
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
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                Text(subject.hasLocalEngine ? l("Точный решатель", "Exact solver") : l("Нужна модель", "Needs a model"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .glassCard(cornerRadius: 20)
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
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.brandGradient))
                VStack(alignment: .leading, spacing: 3) {
                    Text(l("История заданий", "Task history"))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    let favorites = problems.filter { $0.isFavorite }.count
                    Text(l("Решено: \(problems.count) · В избранном: \(favorites)", "Solved: \(problems.count) · Favorites: \(favorites)"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.tertiary)
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
                Image(systemName: "button.programmable")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 52, height: 52)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.orange.opacity(0.15)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(l("Кнопка действия", "Action Button"))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(l("Одно нажатие — и камера уже готова снимать задание", "One press and the camera is ready for your task"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .glassCard()
        }
        .buttonStyle(.pressable)
    }

    private var privacyFooter: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
            Text(
                l(
                    "Фото и задания обрабатываются только на этом iPhone. Без регистрации, серверов и API-ключей.",
                    "Photos and tasks are processed only on this iPhone. No sign-up, servers or API keys."))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }
}

/// Плитка быстрого действия.
private struct QuickActionTile: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let colors: [Color]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .glassCard(cornerRadius: 22, interactive: true)
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
                    Image(systemName: "bookmark.fill").foregroundStyle(.yellow).font(.caption)
                }
                Image(systemName: problem.isSolved ? "checkmark.circle.fill" : "questionmark.circle")
                    .foregroundStyle(problem.isSolved ? Color.green : Color.secondary)
                    .font(.caption)
            }
            Text(problem.problemText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            Text(problem.isSolved ? problem.answer : l("Не решено", "Not solved"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(problem.subject.tint)
                .lineLimit(1)
        }
        .padding(14)
        .frame(width: 210, height: 150, alignment: .topLeading)
        .glassCard(cornerRadius: 22)
    }
}
