import Foundation
import UIKit

/// Итог решения: само решение и, если уместно, локальный анализ текста.
struct SolveOutcome: Sendable {
    var solution: Solution
    var analysis: TextAnalysis?
}

/// Координирует решение задания.
///
/// Порядок всегда один и тот же:
/// 1. точные алгоритмы на устройстве (математика, физика, химия, информатика) — бесплатно и без сети;
/// 2. нейросеть по API пользователя — с выделенным фрагментом изображения;
/// 3. без интернета (или если API недоступен) — Apple Intelligence на устройстве;
/// 4. честное сообщение об ограничении плюс инструменты анализа текста.
@MainActor
final class SolveCoordinator {
    private let settings: AppSettings

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

    func solve(text: String, subject: Subject, image: UIImage?) async -> SolveOutcome {
        let lang = settings.language
        let l = settings.l
        let pipeline = LocalSolverPipeline(lang: lang)
        let trimmed = text.trimmed

        // 1. Точные алгоритмы — вне главного потока, чтобы интерфейс оставался плавным.
        var local: Solution?
        if !trimmed.isEmpty {
            local = await Task.detached(priority: .userInitiated) {
                pipeline.solve(trimmed, subject: subject)
            }.value
        }

        let needsTextTools = [Subject.russian, .english, .literature].contains(subject) && !trimmed.isEmpty
        let analysis = needsTextTools ? LanguageTools.analyze(trimmed, lang: lang) : nil

        if let local, local.isSolved {
            return SolveOutcome(solution: local, analysis: analysis)
        }

        // Изображение сжимаем один раз: длинная сторона до 1600 px достаточна для чтения формул.
        var imageData: Data?
        if let image {
            let boxed = UncheckedSendable(image)
            imageData = await Task.detached(priority: .userInitiated) {
                ImageTools.jpegData(boxed.value, maxDimension: 1600, quality: 0.82)
            }.value
        }

        // 2–3. Нейросеть по API, затем Apple Intelligence.
        var failures: [String] = []
        providerLoop: for provider in providers() {
            let availability = await provider.availability(l)
            guard availability.isAvailable else { continue }
            // Модели без зрения нечего отправить, если текста нет.
            if provider.engine != .remoteAPI, trimmed.isEmpty { continue }
            do {
                let raw = try await provider.generate(
                    instructions: ModelPrompting.instructions(lang: lang),
                    prompt: ModelPrompting.prompt(
                        problem: trimmed, subject: subject, lang: lang, hasImage: provider.engine == .remoteAPI && imageData != nil),
                    image: provider.engine == .remoteAPI ? imageData : nil,
                    maxTokens: 1_500)
                var solution = ModelPrompting.parse(raw, subject: subject, engine: provider.engine, lang: lang)
                if solution.isSolved {
                    solution.problemType = l("Ответ модели «\(provider.displayName(l))»", "Answer by “\(provider.displayName(l))”")
                    if !failures.isEmpty {
                        solution.notes.append(contentsOf: failures)
                    }
                    return SolveOutcome(solution: solution, analysis: analysis)
                }
                failures.append("\(provider.displayName(l)): \(solution.explanation)")
            } catch LanguageModelError.cancelled {
                break providerLoop
            } catch let error as RemoteAPIError {
                failures.append("\(provider.displayName(l)): \(error.message(l))")
            } catch let error as LanguageModelError {
                failures.append("\(provider.displayName(l)): \(error.message(l))")
            } catch {
                failures.append("\(provider.displayName(l)): \(error.localizedDescription)")
            }
        }

        // 4. Честный отказ: объясняем, чего не хватает, и предлагаем то, что реально работает.
        var fallback = local ?? pipeline.limitationMessage(for: subject)
        fallback.notes.append(contentsOf: failures)
        let fallbackAnalysis =
            analysis ?? (subject.hasLocalEngine || trimmed.isEmpty ? nil : LanguageTools.analyze(trimmed, lang: lang))
        if let fallbackAnalysis, !fallbackAnalysis.isEmpty, local == nil {
            fallback.reliability = .toolsOnly
        }
        return SolveOutcome(solution: fallback, analysis: fallbackAnalysis)
    }
}
