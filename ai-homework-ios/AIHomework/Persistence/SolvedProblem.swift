import Foundation
import SwiftData

/// Запись истории: задание и его решение. Хранится локально в SwiftData.
@Model
final class SolvedProblem {
    var id: UUID
    var createdAt: Date
    /// Текст условия (распознанный или введённый).
    var problemText: String
    var subjectRaw: String
    var problemType: String
    var answer: String
    var isSolved: Bool
    var isFavorite: Bool
    var languageRaw: String
    /// Решение целиком в JSON — так модель данных не ломается при развитии структуры `Solution`.
    var solutionData: Data
    @Attribute(.externalStorage) var imageData: Data?
    var thumbnailData: Data?

    init(
        problemText: String,
        solution: Solution,
        language: AppLanguage,
        imageData: Data? = nil,
        thumbnailData: Data? = nil
    ) {
        id = UUID()
        createdAt = Date()
        self.problemText = problemText
        subjectRaw = solution.subject.rawValue
        problemType = solution.problemType
        answer = solution.answer
        isSolved = solution.isSolved
        isFavorite = false
        languageRaw = language.rawValue
        solutionData = (try? JSONEncoder().encode(solution)) ?? Data()
        self.imageData = imageData
        self.thumbnailData = thumbnailData
    }

    var subject: Subject {
        Subject(rawValue: subjectRaw) ?? .other
    }

    var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .ru
    }

    var solution: Solution? {
        try? JSONDecoder().decode(Solution.self, from: solutionData)
    }

    func update(with solution: Solution) {
        subjectRaw = solution.subject.rawValue
        problemType = solution.problemType
        answer = solution.answer
        isSolved = solution.isSolved
        solutionData = (try? JSONEncoder().encode(solution)) ?? solutionData
    }

    /// Совпадает ли запись с поисковым запросом.
    func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        return problemText.lowercased().contains(needle) || answer.lowercased().contains(needle)
            || problemType.lowercased().contains(needle)
    }
}

extension SolvedProblem {
    /// Задание решалось только по картинке: вместо условия сохранена подпись-заглушка.
    var isImageOnly: Bool {
        HistoryPlaceholder.imageOnlyTitles.contains(problemText)
    }
}

/// Подписи для заданий без распознанного текста (сохраняются в `problemText`).
enum HistoryPlaceholder {
    static func imageOnlyTitle(_ l: L10n) -> String {
        l("Задание на изображении", "Task in the image")
    }

    /// Все языковые варианты подписи — запись могла быть сохранена на другом языке интерфейса.
    static let imageOnlyTitles: Set<String> = ["Задание на изображении", "Task in the image"]
}

// MARK: - Версии схемы

/// Текущая схема истории, зафиксированная как первая версия.
///
/// Модель `SolvedProblem` не меняется: схема лишь получает номер, чтобы будущие изменения
/// проходили через `HomeworkMigrationPlan`, а не ломали хранилище после обновления.
/// Когда модель понадобится изменить: скопировать текущую в `HomeworkSchemaV1` как вложенный тип,
/// добавить `HomeworkSchemaV2` и этап миграции.
enum HomeworkSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [SolvedProblem.self] }
}

enum HomeworkMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [HomeworkSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
