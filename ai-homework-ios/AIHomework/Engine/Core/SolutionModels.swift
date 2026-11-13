import Foundation

// MARK: - Subject

/// Школьный предмет.
enum Subject: String, Codable, CaseIterable, Sendable, Identifiable {
    case math
    case physics
    case chemistry
    case russian
    case english
    case history
    case social
    case biology
    case geography
    case literature
    case informatics
    case other

    var id: String { rawValue }

    func title(_ l: L10n) -> String {
        switch self {
        case .math: return l("Математика", "Math")
        case .physics: return l("Физика", "Physics")
        case .chemistry: return l("Химия", "Chemistry")
        case .russian: return l("Русский язык", "Russian")
        case .english: return l("Английский язык", "English")
        case .history: return l("История", "History")
        case .social: return l("Обществознание", "Social studies")
        case .biology: return l("Биология", "Biology")
        case .geography: return l("География", "Geography")
        case .literature: return l("Литература", "Literature")
        case .informatics: return l("Информатика", "Computer science")
        case .other: return l("Другое", "Other")
        }
    }

    /// Имя SF Symbol.
    var symbolName: String {
        switch self {
        case .math: return "function"
        case .physics: return "atom"
        case .chemistry: return "flask.fill"
        case .russian: return "textformat.abc"
        case .english: return "character.bubble.fill"
        case .history: return "building.columns.fill"
        case .social: return "person.3.fill"
        case .biology: return "leaf.fill"
        case .geography: return "globe.europe.africa.fill"
        case .literature: return "book.fill"
        case .informatics: return "chevron.left.forwardslash.chevron.right"
        case .other: return "sparkles"
        }
    }

    /// Есть ли для предмета детерминированный локальный решатель (без языковой модели).
    var hasLocalEngine: Bool {
        switch self {
        case .math, .physics, .chemistry, .informatics: return true
        default: return false
        }
    }

    /// Предметы, которые показываются на главном экране как «популярные».
    static let featured: [Subject] = [
        .math, .physics, .chemistry, .russian, .english, .history, .social, .informatics,
    ]
}

// MARK: - Solution

/// Один шаг пошагового решения.
struct SolutionStep: Codable, Hashable, Sendable {
    var title: String
    var detail: String
    var formula: String?

    init(_ title: String, _ detail: String = "", formula: String? = nil) {
        self.title = title
        self.detail = detail
        self.formula = formula
    }
}

/// Насколько можно доверять результату. Показывается пользователю явно.
enum SolutionReliability: String, Codable, Sendable {
    /// Точное вычисление локальным движком.
    case exact
    /// Численное приближение (корни найдены численно и т.п.).
    case approximate
    /// Условие текстовой задачи интерпретировано эвристически — нужно проверить «Дано».
    case heuristic
    /// Текст сгенерирован локальной языковой моделью и может содержать ошибки.
    case generated
    /// Доступны только инструменты анализа текста, готового ответа нет.
    case toolsOnly
    /// Задание не решено.
    case unsupported
}

/// Какой механизм выдал результат.
enum SolutionEngine: String, Codable, Sendable {
    case math
    case physics
    case chemistry
    case informatics
    case languageTools
    case appleIntelligence
    case coreML
    case none
}

/// Результат решения задания.
struct Solution: Codable, Hashable, Sendable {
    var subject: Subject
    /// Тип задания, например «Квадратное уравнение».
    var problemType: String
    /// Как приложение поняло условие (нормализованная запись).
    var interpretedProblem: String
    /// Краткий ответ. Пустая строка, если задание не решено.
    var answer: String
    /// Объяснение простым языком.
    var explanation: String
    var steps: [SolutionStep]
    /// Использованные формулы.
    var formulas: [String]
    var reliability: SolutionReliability
    var engine: SolutionEngine
    /// Предупреждения и честные оговорки об ограничениях.
    var notes: [String]

    init(
        subject: Subject,
        problemType: String,
        interpretedProblem: String = "",
        answer: String,
        explanation: String = "",
        steps: [SolutionStep] = [],
        formulas: [String] = [],
        reliability: SolutionReliability,
        engine: SolutionEngine,
        notes: [String] = []
    ) {
        self.subject = subject
        self.problemType = problemType
        self.interpretedProblem = interpretedProblem
        self.answer = answer
        self.explanation = explanation
        self.steps = steps
        self.formulas = formulas
        self.reliability = reliability
        self.engine = engine
        self.notes = notes
    }

    /// Есть ли настоящий ответ (а не сообщение об ограничении).
    var isSolved: Bool {
        switch reliability {
        case .exact, .approximate, .heuristic, .generated: return !answer.isEmpty
        case .toolsOnly, .unsupported: return false
        }
    }

    /// Задание не решено — с честным объяснением причины.
    static func unsupported(
        subject: Subject,
        problemType: String,
        reason: String,
        notes: [String] = [],
        engine: SolutionEngine = .none
    ) -> Solution {
        Solution(
            subject: subject,
            problemType: problemType,
            answer: "",
            explanation: reason,
            reliability: .unsupported,
            engine: engine,
            notes: notes
        )
    }

    /// Плоский текст решения — для копирования, «Поделиться» и PDF.
    func plainText(problem: String, _ l: L10n) -> String {
        var lines: [String] = []
        lines.append("\(subject.title(l)) · \(problemType)")
        lines.append("")
        lines.append(l("Условие:", "Problem:"))
        lines.append(problem)
        if !interpretedProblem.isEmpty, interpretedProblem != problem {
            lines.append("")
            lines.append(l("Распознано как:", "Interpreted as:") + " " + interpretedProblem)
        }
        if !answer.isEmpty {
            lines.append("")
            lines.append(l("Ответ:", "Answer:") + " " + answer)
        }
        if !explanation.isEmpty {
            lines.append("")
            lines.append(l("Объяснение:", "Explanation:"))
            lines.append(explanation)
        }
        if !steps.isEmpty {
            lines.append("")
            lines.append(l("Решение по шагам:", "Step-by-step solution:"))
            for (index, step) in steps.enumerated() {
                lines.append("\(index + 1). \(step.title)")
                if let formula = step.formula, !formula.isEmpty {
                    lines.append("   \(formula)")
                }
                if !step.detail.isEmpty {
                    lines.append("   \(step.detail)")
                }
            }
        }
        if !formulas.isEmpty {
            lines.append("")
            lines.append(l("Формулы:", "Formulas:"))
            for formula in formulas {
                lines.append("• \(formula)")
            }
        }
        if !notes.isEmpty {
            lines.append("")
            for note in notes {
                lines.append("⚠︎ \(note)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
