import Foundation
import UIKit

/// Итог решения: само решение, предмет (его могла уточнить нейросеть) и, если уместно, локальный анализ текста.
struct SolveOutcome: Sendable {
    var solution: Solution
    var subject: Subject
    var analysis: TextAnalysis?
}

/// Что происходит прямо сейчас — показывается на экране решения.
enum SolvePhase: Equatable, Sendable {
    /// Нейросеть-диспетчер выбирает, кто будет решать.
    case routing(model: String)
    /// Работает точный решатель на iPhone.
    case exact
    /// Задание решает нейросеть.
    case model(name: String)
}

/// Координирует решение задания.
///
/// Если настроена нейросеть по API, она работает диспетчером:
/// 1. смотрит на задание (фрагмент изображения и распознанный текст) и выбирает маршрут;
/// 2. «программа» — переписывает условие и отдаёт его точному решателю на iPhone;
/// 3. «нейросеть» — задание решается полноценно по API.
/// Если точный решатель не справился с переписанным условием, задание всё равно уходит в API.
///
/// Без API (или без интернета): точный решатель → Apple Intelligence → честное сообщение об ограничении.
/// Каждый шаг ограничен по времени, поэтому решение не может «висеть» бесконечно.
@MainActor
final class SolveCoordinator {
    private let settings: AppSettings

    /// Точные алгоритмы обычно отвечают за миллисекунды; дольше — значит, задание им не по силам.
    private static let exactTimeout: Double = 6
    /// Apple Intelligence на устройстве.
    private static let systemModelTimeout: Double = 60

    init(settings: AppSettings) {
        self.settings = settings
    }

    // MARK: - Subject

    func detectSubject(_ text: String) async -> SubjectGuess {
        let lang = settings.language
        return await Task.detached(priority: .userInitiated) {
            LocalSolverPipeline(lang: lang).detectSubject(text)
        }.value
    }

    // MARK: - Models

    /// Провайдеры в порядке предпочтения: нейросеть по API, затем Apple Intelligence.
    func providers() -> [any LanguageModelProvider] {
        var result: [any LanguageModelProvider] = []
        let config = settings.remoteConfig
        if config.isComplete {
            result.append(RemoteAPIProvider(config: config))
        }
        if settings.data.useSystemModel {
            result.append(AppleIntelligenceProvider())
        }
        return result
    }

    /// Есть ли прямо сейчас хоть одна работоспособная модель.
    func hasLanguageModel() async -> Bool {
        let l = settings.l
        for provider in providers() {
            if await provider.availability(l).isAvailable { return true }
        }
        return false
    }

    /// Настроена ли нейросеть по API (умеет работать с изображением без распознанного текста).
    var canSolveImagesRemotely: Bool {
        settings.remoteConfig.isComplete
    }

    // MARK: - Solving

    func solve(
        text: String, subject initialSubject: Subject, subjectLocked: Bool, image: UIImage?,
        onPhase: (SolvePhase) -> Void = { _ in }
    ) async -> SolveOutcome {
        let lang = settings.language
        let l = settings.l
        let pipeline = LocalSolverPipeline(lang: lang)
        let trimmed = text.trimmed
        var subject = initialSubject
        var notes: [String] = []

        let config = settings.remoteConfig
        let remote = config.isComplete ? RemoteAPIProvider(config: config) : nil
        var remoteUsable = remote != nil

        // Изображение сжимаем один раз: длинная сторона до 1600 px достаточна для чтения формул.
        var imageData: Data?
        if remote != nil, let image {
            let boxed = UncheckedSendable(image)
            imageData = await Task.detached(priority: .userInitiated) {
                ImageTools.jpegData(boxed.value, maxDimension: 1600, quality: 0.82)
            }.value
        }

        // 1. Нейросеть-диспетчер выбирает маршрут.
        var decision: TaskRoute.Target?
        var modelProblem = trimmed
        var triedExactly: Set<String> = []
        var exactFailure: Solution?

        if let remote, !trimmed.isEmpty || imageData != nil {
            let name = remote.displayName(l)
            onPhase(.routing(model: name))
            do {
                if let route = try await remote.route(text: trimmed, subjectHint: subject, image: imageData, lang: lang) {
                    decision = route.target
                    if !subjectLocked, let routed = route.subject { subject = routed }
                    if !route.problem.isEmpty { modelProblem = route.problem }

                    if route.target == .local {
                        // 2. «Программа»: условие в записи нейросети решает точный алгоритм.
                        onPhase(.exact)
                        triedExactly.insert(route.problem)
                        let solved = await solveExactly(route.problem, subject: subject, pipeline: pipeline)
                        if var solution = solved, solution.isSolved {
                            solution.notes.append(
                                l(
                                    "Нейросеть «\(name)» прочитала задание и передала его точному решателю на iPhone в записи: \(route.problem)",
                                    "The model “\(name)” read the task and handed it to the exact on-device solver as: \(route.problem)"))
                            return outcome(solution, subject: subject, text: trimmed, lang: lang)
                        }
                        exactFailure = solved
                    }
                }
            } catch LanguageModelError.cancelled {
                return outcome(pipeline.limitationMessage(for: subject), subject: subject, text: trimmed, lang: lang)
            } catch {
                // Диспетчер недоступен — значит, и решать по этому API сейчас не выйдет.
                remoteUsable = false
                notes.append("\(name): \(describe(error, l))")
            }
        }

        // 3. Точный решатель по исходному тексту — если диспетчера нет, он не ответил
        //    или его запись не подошла. Если диспетчер явно выбрал нейросеть, его решение уважаем.
        if decision != .model, !trimmed.isEmpty, !triedExactly.contains(trimmed) {
            onPhase(.exact)
            let solved = await solveExactly(trimmed, subject: subject, pipeline: pipeline)
            if let solved, solved.isSolved {
                return outcome(solved, subject: subject, text: trimmed, lang: lang, notes: notes)
            }
            exactFailure = exactFailure ?? solved
        }

        // 4. Решение нейросетью: сначала по API, затем Apple Intelligence на устройстве.
        var providers: [any LanguageModelProvider] = []
        if let remote, remoteUsable { providers.append(remote) }
        if settings.data.useSystemModel { providers.append(AppleIntelligenceProvider()) }

        providerLoop: for provider in providers {
            let isRemote = provider.engine == .remoteAPI
            // Моделям без зрения нечего отправить, если текста нет.
            if !isRemote, modelProblem.isEmpty { continue }
            let availability = await provider.availability(l)
            guard availability.isAvailable else { continue }
            let name = provider.displayName(l)
            onPhase(.model(name: name))

            let instructions = ModelPrompting.instructions(lang: lang)
            let prompt = ModelPrompting.prompt(
                problem: modelProblem, subject: subject, lang: lang, hasImage: isRemote && imageData != nil)
            let image = isRemote ? imageData : nil
            do {
                let raw: String
                if isRemote {
                    // У запроса по API свой общий лимит времени (см. RemoteAPIProvider).
                    raw = try await provider.generate(instructions: instructions, prompt: prompt, image: image, maxTokens: 1_500)
                } else {
                    raw = try await Deadline.run(seconds: Self.systemModelTimeout) {
                        try await provider.generate(instructions: instructions, prompt: prompt, image: nil, maxTokens: 1_500)
                    }
                }
                var solution = ModelPrompting.parse(raw, subject: subject, engine: provider.engine, lang: lang)
                if solution.isSolved {
                    solution.problemType = l("Ответ модели «\(name)»", "Answer by “\(name)”")
                    return outcome(solution, subject: subject, text: trimmed, lang: lang, notes: notes)
                }
                notes.append("\(name): \(solution.explanation)")
            } catch LanguageModelError.cancelled {
                break providerLoop
            } catch {
                notes.append("\(name): \(describe(error, l))")
            }
        }

        // 5. Честный отказ: объясняем, чего не хватает, и предлагаем то, что реально работает.
        var fallback = exactFailure ?? pipeline.limitationMessage(for: subject)
        fallback.notes.append(contentsOf: notes)
        var result = outcome(fallback, subject: subject, text: trimmed, lang: lang)
        if result.analysis == nil, !subject.hasLocalEngine, !trimmed.isEmpty {
            let analysis = LanguageTools.analyze(trimmed, lang: lang)
            if !analysis.isEmpty {
                result.analysis = analysis
                if exactFailure == nil { result.solution.reliability = .toolsOnly }
            }
        }
        return result
    }

    // MARK: - Helpers

    /// Точный решатель вне главного потока и с лимитом времени: зависнуть он не может.
    private func solveExactly(_ text: String, subject: Subject, pipeline: LocalSolverPipeline) async -> Solution? {
        let problem = text.trimmed
        guard !problem.isEmpty else { return nil }
        return await Deadline.compute(seconds: Self.exactTimeout) {
            pipeline.solve(problem, subject: subject)
        } ?? nil
    }

    private func outcome(
        _ solution: Solution, subject: Subject, text: String, lang: AppLanguage, notes: [String] = []
    ) -> SolveOutcome {
        var solution = solution
        solution.notes.append(contentsOf: notes)
        let needsTextTools = [Subject.russian, .english, .literature].contains(subject) && !text.isEmpty
        let analysis = needsTextTools ? LanguageTools.analyze(text, lang: lang) : nil
        return SolveOutcome(solution: solution, subject: subject, analysis: analysis)
    }

    private func describe(_ error: Error, _ l: L10n) -> String {
        switch error {
        case let error as RemoteAPIError: return error.message(l)
        case let error as LanguageModelError: return error.message(l)
        case is Deadline.Exceeded:
            return l("Модель не ответила вовремя.", "The model did not answer in time.")
        default: return error.localizedDescription
        }
    }
}
