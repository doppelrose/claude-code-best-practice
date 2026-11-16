import Foundation
import OSLog
import SwiftData

/// Все операции с историей в одном месте: открытие хранилища, сохранение с обработкой ошибок,
/// поиск записи по идентификатору, удаление и очистка фото.
///
/// Ошибки не проглатываются: они пишутся в системный журнал, а вызывающий код получает `false`
/// и показывает пользователю сообщение.
@MainActor
enum HistoryStore {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AIHomework", category: "history")

    // MARK: - Container

    /// Открывает хранилище истории с версионированной схемой.
    ///
    /// Порядок: версионированная схема → прежний способ открытия (то же хранилище, без плана миграции) →
    /// хранилище в памяти. В последнем случае `isTemporary == true`: история в этом запуске не сохранится,
    /// и пользователь видит предупреждение.
    static func makeContainer() -> (container: ModelContainer, isTemporary: Bool) {
        let schema = Schema(versionedSchema: HomeworkSchemaV1.self)
        do {
            let configuration = ModelConfiguration(schema: schema)
            let container = try ModelContainer(
                for: schema, migrationPlan: HomeworkMigrationPlan.self, configurations: [configuration])
            return (container, false)
        } catch {
            logger.error("Versioned history store failed to open: \(String(describing: error), privacy: .public)")
        }
        do {
            // Тот же файл хранилища, что открывался до появления версий схемы.
            return (try ModelContainer(for: SolvedProblem.self), false)
        } catch {
            logger.error("History store failed to open: \(String(describing: error), privacy: .public)")
        }
        do {
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return (try ModelContainer(for: schema, configurations: [memory]), true)
        } catch {
            fatalError("Could not create an in-memory history store: \(error)")
        }
    }

    // MARK: - Saving

    /// Сохраняет изменения. `false` — запись не удалась (причина в журнале).
    @discardableResult
    static func save(_ context: ModelContext) -> Bool {
        guard context.hasChanges else { return true }
        do {
            try context.save()
            return true
        } catch {
            logger.error("History save failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    static func saveFailedMessage(_ l: L10n) -> String {
        l("Не удалось сохранить историю", "Could not save the history")
    }

    // MARK: - Lookup

    /// Запись по идентификатору; `nil`, если её уже удалили.
    static func record(id: UUID, in context: ModelContext) -> SolvedProblem? {
        var descriptor = FetchDescriptor<SolvedProblem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        do {
            return try context.fetch(descriptor).first
        } catch {
            logger.error("History fetch failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Число записей, подходящих под условие.
    static func count(_ predicate: Predicate<SolvedProblem>? = nil, in context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<SolvedProblem>(predicate: predicate)
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    // MARK: - Deleting

    /// Поштучное удаление: так `@Query` на всех экранах сразу видит изменения,
    /// а файлы фото (`externalStorage`) удаляются вместе с записями.
    @discardableResult
    static func delete(_ problems: [SolvedProblem], in context: ModelContext) -> Bool {
        for problem in problems {
            context.delete(problem)
        }
        return save(context)
    }

    /// Удаляет всю историю. Единственный способ очистки — и в истории, и в настройках.
    @discardableResult
    static func deleteAll(in context: ModelContext) -> Bool {
        do {
            let all = try context.fetch(FetchDescriptor<SolvedProblem>())
            return delete(all, in: context)
        } catch {
            logger.error("History fetch for deletion failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// Убирает фото и миниатюры из всех записей, сами решения остаются.
    /// Возвращает число записей, у которых было фото, или `nil` при ошибке.
    static func removeAllPhotos(in context: ModelContext) -> Int? {
        do {
            let all = try context.fetch(FetchDescriptor<SolvedProblem>())
            var cleared = 0
            for problem in all {
                // Фото и миниатюра сохраняются вместе; само фото не читаем, чтобы не загружать файлы.
                if problem.thumbnailData != nil { cleared += 1 }
                problem.imageData = nil
                problem.thumbnailData = nil
            }
            return save(context) ? cleared : nil
        } catch {
            logger.error("History fetch for photo removal failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
