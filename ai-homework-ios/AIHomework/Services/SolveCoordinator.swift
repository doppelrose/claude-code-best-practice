import CoreML
import Foundation
import NaturalLanguage

/// Итог решения: само решение и, если уместно, локальный анализ текста.
struct SolveOutcome: Sendable {
    var solution: Solution
    var analysis: TextAnalysis?
}

/// Координирует решение задания.
///
/// Порядок всегда один и тот же:
/// 1. точные локальные алгоритмы (математика, физика, химия, информатика);
/// 2. локальная языковая модель — только если она действительно доступна;
/// 3. честное сообщение об ограничении плюс инструменты анализа текста.
///
/// Ни на одном шаге данные не покидают устройство.
@MainActor
final class SolveCoordinator {
    private let settings: AppSettings
    private let modelStore: CoreMLModelStore

    init(settings: AppSettings, modelStore: CoreMLModelStore) {
        self.settings = settings
        self.modelStore = modelStore
    }

    // MARK: - Subject

    /// Определение предмета: словари и структурные признаки, а при наличии
    /// установленного классификатора Core ML — ещё и он.
    func detectSubject(_ text: String) async -> SubjectGuess {
        let lang = settings.language
        var guess = await Task.detached(priority: .userInitiated) {
            LocalSolverPipeline(lang: lang).detectSubject(text)
        }.value
        if guess.confidence < 0.6, let classified = classifyWithInstalledModel(text), classified != guess.subject {
            guess = SubjectGuess(subject: classified, confidence: 0.6, ranked: [classified] + guess.ranked.filter { $0 != classified })
        }
        return guess
    }

    /// Пользовательский классификатор текста (Create ML), метки которого совпадают с `Subject.rawValue`.
    private func classifyWithInstalledModel(_ text: String) -> Subject? {
        guard let classifier = modelStore.models.first(where: { $0.kind == .subjectClassifier }) else { return nil }
        let url = CoreMLModelStore.folder(forID: classifier.id).appendingPathComponent(CoreMLModelStore.modelFileName)
        guard let model = try? NLModel(contentsOf: url), let label = model.predictedLabel(for: text) else { return nil }
        return Subject(rawValue: label.lowercased())
    }

    // MARK: - Models

    /// Провайдеры в порядке предпочтения: выбранная пользователем модель Core ML, затем системная.
    func providers() -> [any LanguageModelProvider] {
        var result: [any LanguageModelProvider] = []
        if let model = modelStore.model(withID: settings.data.activeCoreMLModelID), model.kind == .textGenerator {
            result.append(CoreMLModelProvider(model: model))
        }
        if settings.data.useSystemModel {
            result.append(AppleIntelligenceProvider())
        }
        return result
    }

    private func firstAvailableProvider() async -> (any LanguageModelProvider)? {
        let l = settings.l
        for provider in providers() {
            if await provider.availability(l).isAvailable { return provider }
        }
        return nil
    }

    /// Есть ли прямо сейчас работоспособная языковая модель.
    func hasLanguageModel() async -> Bool {
        await firstAvailableProvider() != nil
    }

    // MARK: - Solving

    func solve(text: String, subject: Subject) async -> SolveOutcome {
        let lang = settings.language
        let l = settings.l
        let pipeline = LocalSolverPipeline(lang: lang)

        // 1. Точные алгоритмы — вне главного потока, чтобы интерфейс оставался плавным.
        let local = await Task.detached(priority: .userInitiated) {
            pipeline.solve(text, subject: subject)
        }.value

        let needsTextTools = [Subject.russian, .english, .literature].contains(subject)
        let analysis = needsTextTools ? LanguageTools.analyze(text, lang: lang) : nil

        if let local, local.isSolved {
            return SolveOutcome(solution: local, analysis: analysis)
        }

        // 2. Локальная языковая модель.
        var modelFailure: String?
        if let provider = await firstAvailableProvider() {
            do {
                let raw = try await provider.generate(
                    instructions: ModelPrompting.instructions(lang: lang),
                    prompt: ModelPrompting.prompt(problem: text, subject: subject, lang: lang),
                    maxTokens: 700)
                var solution = ModelPrompting.parse(raw, subject: subject, engine: provider.engine, lang: lang)
                if solution.isSolved {
                    solution.problemType = l("Ответ модели «\(provider.displayName(l))»", "Answer by “\(provider.displayName(l))”")
                    if let local, !local.explanation.isEmpty {
                        solution.notes.append(l("Точный решатель не справился: ", "The exact solver could not handle it: ") + local.explanation)
                    }
                    return SolveOutcome(solution: solution, analysis: analysis)
                }
                modelFailure = solution.explanation
            } catch let error as LanguageModelError {
                modelFailure = error.message(l)
            } catch {
                modelFailure = error.localizedDescription
            }
        }

        // 3. Честный отказ: объясняем, чего не хватает, и предлагаем то, что реально работает.
        var fallback = local ?? pipeline.limitationMessage(for: subject)
        if let modelFailure {
            fallback.notes.append(l("Языковая модель: ", "Language model: ") + modelFailure)
        }
        let fallbackAnalysis = analysis ?? (subject.hasLocalEngine ? nil : LanguageTools.analyze(text, lang: lang))
        if let fallbackAnalysis, !fallbackAnalysis.isEmpty, local == nil {
            fallback.reliability = .toolsOnly
        }
        return SolveOutcome(solution: fallback, analysis: fallbackAnalysis)
    }
}
