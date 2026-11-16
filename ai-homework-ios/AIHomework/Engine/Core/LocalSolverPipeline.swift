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

    private func subject(of engine: Engine) -> Subject {
        switch engine {
        case .math: return .math
        case .physics: return .physics
        case .chemistry: return .chemistry
        case .informatics: return .informatics
        }
    }

    /// Признаки, по которым решатель «чужого» предмета вправе ответить.
    ///
    /// Если решатель выбранного предмета не справился, следующий решатель отвечает, только когда
    /// задание явно его: иначе геометрия получает «M(BC) = 23 г/моль», а неоднозначная
    /// реакция — «упрощение выражения Fe + O²» с меткой «точно».
    private func hasStrongEvidence(for engine: Engine, text: String, chemistry: ChemistrySolver.FormulaEvidence) -> Bool {
        switch engine {
        case .chemistry:
            return chemistry != .none
        case .math:
            // Символы элементов в «уравнении» — не переменные.
            return chemistry == .none
        case .physics:
            if PhysicsSolver(lang: lang).extractGivens(MathNormalizer.normalize(text)).count >= 2 { return true }
            return SubjectDetector().detect(text).subject == .physics
        case .informatics:
            // Решатель срабатывает только на названия систем счисления и единиц информации.
            return true
        }
    }

    /// Решение точными локальными алгоритмами. `nil` — задание им не по силам.
    func solve(_ text: String, subject: Subject) -> Solution? {
        let trimmed = text.trimmed
        guard !trimmed.isEmpty else { return nil }
        var engines = order(for: subject)
        guard !engines.isEmpty else { return nil }
        let chemistry = ChemistrySolver.formulaEvidence(in: trimmed)
        // Уравнение реакции сначала разбирает химия, какой бы предмет ни был выбран.
        if chemistry == .reaction, let index = engines.firstIndex(of: .chemistry), index > 0 {
            engines.remove(at: index)
            engines.insert(.chemistry, at: 0)
        }
        var firstFailure: Solution?
        for engine in engines {
            // В уравнении реакции «переменные» — символы элементов: математика его не трактует.
            if engine == .math, chemistry == .reaction { continue }
            let own = self.subject(of: engine) == subject
            guard own || hasStrongEvidence(for: engine, text: trimmed, chemistry: chemistry) else { continue }
            guard let solution = run(engine, trimmed) else { continue }
            if solution.isSolved { return solution }
            // Решатель узнал задание, но не справился — запоминаем его объяснение.
            if firstFailure == nil { firstFailure = solution }
        }
        return firstFailure
    }

    /// Честное сообщение для случая, когда точные алгоритмы не подошли, а нейросеть недоступна.
    func limitationMessage(for subject: Subject) -> Solution {
        let l = L10n(lang)
        let reason: String
        if subject.hasLocalEngine {
            reason = l(
                "Точные алгоритмы на устройстве решают примеры, уравнения, неравенства, системы, производные, задачи «в одну формулу» и другие типовые вычисления. Это задание требует понимания текста и рассуждений — для него нужна нейросеть, а она сейчас недоступна.",
                "The exact on-device algorithms solve expressions, equations, inequalities, systems, derivatives, single-formula problems and other standard computations. This task requires understanding text and reasoning — it needs an AI model, which is not available right now."
            )
        } else {
            reason = l(
                "Для развёрнутого ответа по предмету «\(subject.title(l))» нужна нейросеть, а она сейчас недоступна. Приложение не выдумывает ответы: ниже доступны только инструменты анализа текста, которые работают на устройстве.",
                "A full answer in “\(subject.title(l))” needs an AI model, which is not available right now. The app does not make answers up: only the on-device text analysis tools are offered below."
            )
        }
        return Solution.unsupported(
            subject: subject,
            problemType: l("Нужна нейросеть", "AI model required"),
            reason: reason,
            notes: [
                l(
                    "Подключите нейросеть в «Настройки → Нейросеть по API» (адрес, ключ и модель вашего сервиса). Без интернета используется Apple Intelligence (iOS 26+), если он доступен на устройстве.",
                    "Connect a model in Settings → AI model via API (your service's address, key and model). Offline, Apple Intelligence (iOS 26+) is used when available on the device."
                )
            ])
    }
}
