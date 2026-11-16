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
/// 1. смотрит на распознанный текст задания (изображение диспетчеру не отправляется) и выбирает маршрут;
/// 2. «программа» — переписывает условие и отдаёт его точному решателю на iPhone;
///    такой ответ помечается «Проверьте „Дано“», если запись отличается от распознанного текста;
/// 3. «нейросеть» — задание решается полноценно по API. Изображение уходит только в этот запрос
///    и только если пользователь включил «Отправлять изображение в нейросеть».
/// Если точный решатель не справился с переписанным условием, задание всё равно уходит в API.
/// Если диспетчер ответил непонятно, пусто, ошибкой 400 или не успел — задание решается как обычно;
/// API отключается на это решение только при сетевых и авторизационных ошибках.
///
/// Без API (или без интернета): точный решатель → Apple Intelligence (если поддерживает язык) →
/// честное сообщение об ограничении. Каждый шаг ограничен по времени, поэтому решение не может «висеть» бесконечно.
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

    /// Настроена ли нейросеть по API. Задание без распознанного текста можно отдать в `solve`:
    /// если отправка изображения выключена, решение вернёт понятное объяснение, что сделать.
    var canSolveImagesRemotely: Bool {
        settings.remoteConfig.isComplete
    }

    /// Уйдёт ли изображение в нейросеть по API (API настроен и пользователь разрешил отправку).
    var sendsImagesToAPI: Bool {
        settings.remoteConfig.isComplete && settings.data.sendImagesToAPI
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

        let config = settings.remoteConfigForRequest()
        let remote = config.isComplete ? RemoteAPIProvider(config: config) : nil
        var remoteUsable = remote != nil
        let sendImages = settings.data.sendImagesToAPI

        // Текста нет, а изображение отправлять нельзя — честно говорим, что сделать.
        if trimmed.isEmpty, image != nil, remote != nil, !sendImages {
            return SolveOutcome(solution: imageSendingDisabled(subject: subject, l), subject: subject, analysis: nil)
        }

        // 1. Нейросеть-диспетчер выбирает маршрут. Ей уходит только текст (AUD-48).
        var decision: TaskRoute.Target?
        var modelProblem = trimmed
        var triedExactly: Set<String> = []
        var exactFailure: Solution?

        if let remote, !trimmed.isEmpty {
            let name = remote.displayName(l)
            onPhase(.routing(model: name))
            do {
                if let route = try await remote.route(text: trimmed, subjectHint: subject, image: nil, lang: lang) {
                    decision = route.target
                    if !subjectLocked, let routed = route.subject { subject = routed }
                    if !route.problem.isEmpty { modelProblem = route.problem }

                    if route.target == .local {
                        // 2. «Программа»: условие в записи нейросети решает точный алгоритм.
                        onPhase(.exact)
                        triedExactly.insert(route.problem)
                        let solved = await solveExactly(route.problem, subject: subject, pipeline: pipeline)
                        if var solution = solved, solution.isSolved {
                            markRewrittenByModel(&solution, original: trimmed, rewritten: route.problem, model: name, l)
                            return await outcome(solution, subject: subject, text: trimmed, lang: lang)
                        }
                        exactFailure = solved
                    }
                }
            } catch LanguageModelError.cancelled {
                return await outcome(pipeline.limitationMessage(for: subject), subject: subject, text: trimmed, lang: lang)
            } catch {
                switch TaskRouting.fallback(after: error) {
                case .disableRemote:
                    // Нет связи, неверный ключ или адрес — полное решение по этому API тоже не выйдет.
                    remoteUsable = false
                    notes.append("\(name): \(describe(error, l))")
                case .continueWithRemote:
                    // Сбой только у диспетчера — решаем как обычно, в том числе по API.
                    break
                }
            }
        }

        // 3. Точный решатель по исходному тексту — если диспетчера нет, он не ответил
        //    или его запись не подошла. Если диспетчер явно выбрал нейросеть, его решение уважаем.
        if decision != .model, !trimmed.isEmpty, !triedExactly.contains(trimmed) {
            onPhase(.exact)
            let solved = await solveExactly(trimmed, subject: subject, pipeline: pipeline)
            if let solved, solved.isSolved {
                return await outcome(solved, subject: subject, text: trimmed, lang: lang, notes: notes)
            }
            exactFailure = exactFailure ?? solved
        }

        // 4. Решение нейросетью: сначала по API, затем Apple Intelligence на устройстве.
        var providers: [any LanguageModelProvider] = []
        if let remote, remoteUsable { providers.append(remote) }
        if settings.data.useSystemModel { providers.append(AppleIntelligenceProvider()) }

        // Изображение сжимаем один раз и только если оно правда уйдёт в запрос решения.
        var imageData: Data?
        if remote != nil, remoteUsable, sendImages, let image {
            let boxed = UncheckedSendable(image)
            imageData = await Task.detached(priority: .userInitiated) {
                ImageTools.jpegData(boxed.value, maxDimension: 1600, quality: 0.82)
            }.value
        }

        providerLoop: for provider in providers {
            let isRemote = provider.engine == .remoteAPI
            let requestImage = isRemote ? imageData : nil
            // Нечего отправить: нет ни текста, ни разрешённого изображения.
            if modelProblem.isEmpty, requestImage == nil { continue }
            let availability = await provider.availability(l)
            guard availability.isAvailable else { continue }
            let name = provider.displayName(l)
            onPhase(.model(name: name))

            do {
                let raw: String
                var droppedImage = false
                if isRemote {
                    // У запроса по API свой общий лимит времени (см. RemoteAPIProvider).
                    let answer = try await solveRemotely(provider, problem: modelProblem, subject: subject, lang: lang, image: requestImage)
                    raw = answer.text
                    droppedImage = answer.droppedImage
                } else {
                    let instructions = ModelPrompting.instructions(lang: lang)
                    let prompt = ModelPrompting.prompt(problem: modelProblem, subject: subject, lang: lang, hasImage: false)
                    raw = try await Deadline.run(seconds: Self.systemModelTimeout) {
                        try await provider.generate(instructions: instructions, prompt: prompt, image: nil, maxTokens: 1_500)
                    }
                }
                var solution = ModelPrompting.parse(raw, subject: subject, engine: provider.engine, lang: lang)
                if solution.isSolved {
                    solution.problemType = l("Ответ модели «\(name)»", "Answer by “\(name)”")
                    if droppedImage {
                        solution.notes.append(
                            l(
                                "Модель не приняла изображение — задание решено по распознанному тексту. Сверьте условие.",
                                "The model did not accept the image — the task was solved from the recognized text. Check the task."))
                    }
                    return await outcome(solution, subject: subject, text: trimmed, lang: lang, notes: notes)
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
        var result = await outcome(fallback, subject: subject, text: trimmed, lang: lang)
        if result.analysis == nil, !subject.hasLocalEngine, !trimmed.isEmpty {
            let analysis = await textAnalysis(trimmed, lang: lang)
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

    /// Полное решение по API. Если модель не принимает изображения (HTTP 400), задание
    /// повторяется только с текстом — когда текст есть. Второе значение — изображение отброшено.
    private func solveRemotely(
        _ provider: any LanguageModelProvider, problem: String, subject: Subject, lang: AppLanguage, image: Data?
    ) async throws -> (text: String, droppedImage: Bool) {
        let instructions = ModelPrompting.instructions(lang: lang)
        let prompt = ModelPrompting.prompt(problem: problem, subject: subject, lang: lang, hasImage: image != nil)
        do {
            let raw = try await provider.generate(
                instructions: instructions, prompt: prompt, image: image, maxTokens: RemoteAPIProvider.solveMaxTokens)
            return (text: raw, droppedImage: false)
        } catch RemoteAPIError.http(let status, _) where status == 400 && image != nil && !problem.trimmed.isEmpty {
            let textOnly = ModelPrompting.prompt(problem: problem, subject: subject, lang: lang, hasImage: false)
            let raw = try await provider.generate(
                instructions: instructions, prompt: textOnly, image: nil, maxTokens: RemoteAPIProvider.solveMaxTokens)
            return (text: raw, droppedImage: true)
        }
    }

    /// Точный ответ на условие, которое переписала нейросеть: вычисление точное, но условие
    /// прочитано не алгоритмом. Метка понижается до «Проверьте „Дано“», пометка — первой.
    private func markRewrittenByModel(_ solution: inout Solution, original: String, rewritten: String, model name: String, _ l: L10n) {
        let check = TaskRouting.rewrite(original: original, rewritten: rewritten)
        guard check != .unchanged else { return }
        if solution.reliability == .exact { solution.reliability = .heuristic }
        if solution.interpretedProblem.isEmpty { solution.interpretedProblem = rewritten }
        let note: String
        switch check {
        case .numbersChanged:
            note = l(
                "Условие прочитала нейросеть «\(name)», и в её записи есть числа, которых нет в распознанном тексте. Обязательно сверьте запись с заданием: \(rewritten)",
                "The task was read by the model “\(name)”, and its version contains numbers that are not in the recognized text. Be sure to compare it with the task: \(rewritten)")
        case .rewritten, .unchanged:
            note = l(
                "Условие прочитала нейросеть «\(name)» и передала точному решателю на iPhone в записи: \(rewritten). Вычисление точное — сверьте запись с заданием.",
                "The task was read by the model “\(name)” and handed to the exact on-device solver as: \(rewritten). The computation is exact — compare this version with the task.")
        }
        solution.notes.insert(note, at: 0)
    }

    /// Нет распознанного текста, а отправка изображения в нейросеть выключена.
    private func imageSendingDisabled(subject: Subject, _ l: L10n) -> Solution {
        Solution.unsupported(
            subject: subject,
            problemType: l("Нужен текст условия", "Task text needed"),
            reason: l(
                "На изображении не удалось распознать текст, а отправка изображения в нейросеть выключена. Включите «Отправлять изображение в нейросеть» в настройках или введите условие вручную.",
                "No text could be recognized in the image, and sending images to the AI model is turned off. Turn on “Send the image to the AI model” in Settings or type the task in."),
            notes: [
                l(
                    "Изображение остаётся на iPhone, пока вы не включите эту настройку.",
                    "The image stays on the iPhone until you turn this setting on.")
            ])
    }

    private func outcome(
        _ solution: Solution, subject: Subject, text: String, lang: AppLanguage, notes: [String] = []
    ) async -> SolveOutcome {
        var solution = solution
        solution.notes.append(contentsOf: notes)
        let needsTextTools = [Subject.russian, .english, .literature].contains(subject) && !text.isEmpty
        var analysis: TextAnalysis?
        if needsTextTools {
            analysis = await textAnalysis(text, lang: lang)
        }
        return SolveOutcome(solution: solution, subject: subject, analysis: analysis)
    }

    /// Анализ текста — единственная точка вызова `LanguageTools` из координатора.
    /// NaturalLanguage-часть выполняется в фоне; на главном потоке остаётся только
    /// проверка орфографии `UITextChecker`.
    private func textAnalysis(_ text: String, lang: AppLanguage) async -> TextAnalysis {
        await LanguageTools.analyzeInBackground(text, lang: lang)
    }

    /// Пояснение к ошибке для истории и PDF: без сырого текста ответа сервера (AUD-96).
    private func describe(_ error: Error, _ l: L10n) -> String {
        switch error {
        case let error as RemoteAPIError: return error.storedMessage(l)
        case let error as LanguageModelError: return error.message(l)
        case is Deadline.Exceeded:
            return l("Модель не ответила вовремя.", "The model did not answer in time.")
        default: return error.localizedDescription
        }
    }
}
