import Foundation

/// Конвейер детерминированных локальных решателей.
///
/// Здесь нет ни сети, ни языковой модели — только алгоритмы. Если ни один решатель
/// не справился, конвейер возвращает `nil`, и вызывающий код либо обращается к локальной
/// языковой модели (если она установлена), либо честно сообщает об ограничении.
struct LocalSolverPipeline: Sendable {
    let lang: AppLanguage

    init(lang: AppLanguage) {
        self.lang = lang
    }

    func detectSubject(_ text: String) -> SubjectGuess {
        SubjectDetector().detect(text)
    }

    private enum Engine {
        case math, physics, chemistry, informatics
    }

    /// Порядок попыток: сначала решатель выбранного предмета, затем остальные точные решатели.
    private func order(for subject: Subject) -> [Engine] {
        switch subject {
        case .math: return [.math, .informatics, .physics, .chemistry]
        case .physics: return [.physics, .math, .chemistry]
        case .chemistry: return [.chemistry, .math, .physics]
        case .informatics: return [.informatics, .math]
        case .other: return [.chemistry, .informatics, .physics, .math]
        // В гуманитарных предметах числа в тексте — это даты и номера, а не примеры:
        // вычислять «1941−1945» было бы выдумыванием ответа.
        case .russian, .english, .history, .social, .biology, .geography, .literature: return []
        }
    }

    private func run(_ engine: Engine, _ text: String) -> Solution? {
        switch engine {
        case .math: return MathSolver(lang: lang).solve(text)
        case .physics: return PhysicsSolver(lang: lang).solve(text)
        case .chemistry: return ChemistrySolver(lang: lang).solve(text)
        case .informatics: return InformaticsSolver(lang: lang).solve(text)
        }
    }

    /// Решение точными локальными алгоритмами. `nil` — задание им не по силам.
    func solve(_ text: String, subject: Subject) -> Solution? {
        let trimmed = text.trimmed
        guard !trimmed.isEmpty else { return nil }
        var firstFailure: Solution?
        for engine in order(for: subject) {
            guard let solution = run(engine, trimmed) else { continue }
            if solution.isSolved { return solution }
            // Решатель узнал задание, но не справился — запоминаем его объяснение.
            if firstFailure == nil { firstFailure = solution }
        }
        return firstFailure
    }

    /// Честное сообщение для случая, когда локальные алгоритмы не подошли, а языковой модели нет.
    func limitationMessage(for subject: Subject) -> Solution {
        let l = L10n(lang)
        let reason: String
        if subject.hasLocalEngine {
            reason = l(
                "Локальные алгоритмы решают примеры, уравнения, неравенства, системы, производные, задачи «в одну формулу» и другие типовые вычисления. Это задание требует понимания текста и рассуждений — для него нужна локальная языковая модель, а она сейчас недоступна.",
                "The local algorithms solve expressions, equations, inequalities, systems, derivatives, single-formula problems and other standard computations. This task requires understanding text and reasoning — it needs an on-device language model, which is not available right now."
            )
        } else {
            reason = l(
                "Для развёрнутого ответа по предмету «\(subject.title(l))» нужна локальная языковая модель, а она сейчас недоступна. Приложение не выдумывает ответы: ниже доступны только инструменты анализа текста, которые работают на устройстве.",
                "A full answer in “\(subject.title(l))” needs an on-device language model, which is not available right now. The app does not make answers up: only the on-device text analysis tools are offered below."
            )
        }
        return Solution.unsupported(
            subject: subject,
            problemType: l("Нужна локальная языковая модель", "On-device language model required"),
            reason: reason,
            notes: [
                l(
                    "Подключить модель можно в «Настройки → Локальные модели»: системная модель Apple Intelligence (iOS 26+) или собственная модель Core ML.",
                    "You can connect a model in Settings → On-device models: the system Apple Intelligence model (iOS 26+) or your own Core ML model."
                )
            ])
    }
}
