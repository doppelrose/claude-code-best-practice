import CoreML
import Foundation
import UniformTypeIdentifiers

/// Установленная пользователем модель Core ML.
struct InstalledModel: Codable, Identifiable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable {
        /// Языковая модель: вход `input_ids`, выход `logits`, рядом лежит `tokenizer.json`.
        case textGenerator
        /// Классификатор текста (Create ML): определяет школьный предмет.
        case subjectClassifier
        /// Модель загружена, но её интерфейс приложению не подходит.
        case unsupported
    }

    var id: String
    var name: String
    var kind: Kind
    var importedAt: Date
    var sizeBytes: Int64
    var hasTokenizer: Bool
    /// Входы и выходы модели — для экрана «Локальные модели».
    var summary: String
}

/// Необязательный файл `manifest.json` рядом с моделью.
struct ModelManifest: Codable, Sendable {
    var name: String?
    /// Шаблон запроса с подстановками `{system}` и `{prompt}`.
    var promptTemplate: String?
    /// Токены, на которых генерация останавливается.
    var stopTokens: [String]?
    var contextLength: Int?
    var temperature: Double?
}

enum ModelImportError: Error, Sendable {
    case noModelFound
    case copyFailed(String)
    case compileFailed(String)

    func message(_ l: L10n) -> String {
        switch self {
        case .noModelFound:
            return l(
                "В выбранной папке нет модели Core ML (.mlpackage, .mlmodelc или .mlmodel).",
                "The selected folder contains no Core ML model (.mlpackage, .mlmodelc or .mlmodel).")
        case .copyFailed(let detail):
            return l("Не удалось скопировать модель: \(detail)", "Could not copy the model: \(detail)")
        case .compileFailed(let detail):
            return l("Core ML не смог подготовить модель: \(detail)", "Core ML could not prepare the model: \(detail)")
        }
    }
}

/// Хранилище пользовательских моделей: импорт из «Файлов», компиляция, список, удаление.
///
/// Модели лежат в `Application Support/Models/<id>/` и никуда не отправляются.
@MainActor
@Observable
final class CoreMLModelStore {
    private(set) var models: [InstalledModel] = []
    private(set) var isImporting = false
    var lastError: String?

    nonisolated static let modelFileName = "model.mlmodelc"
    nonisolated static let tokenizerFileName = "tokenizer.json"
    nonisolated static let manifestFileName = "manifest.json"
    private nonisolated static let infoFileName = "info.json"

    init() {
        reload()
    }

    nonisolated static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Models", isDirectory: true)
    }

    nonisolated static func folder(forID id: String) -> URL {
        directory.appendingPathComponent(id, isDirectory: true)
    }

    /// Типы, которые можно выбрать в «Файлах»: пакет модели, скомпилированная модель или папка с комплектом.
    static var importableTypes: [UTType] {
        var types: [UTType] = [.folder]
        for identifier in ["com.apple.coreml.mlpackage", "com.apple.coreml.model"] {
            if let type = UTType(identifier) { types.append(type) }
        }
        for fileExtension in ["mlpackage", "mlmodel", "mlmodelc"] {
            if let type = UTType(filenameExtension: fileExtension) { types.append(type) }
        }
        return types
    }

    func reload() {
        let fileManager = FileManager.default
        let folders = (try? fileManager.contentsOfDirectory(at: CoreMLModelStore.directory, includingPropertiesForKeys: nil)) ?? []
        var loaded: [InstalledModel] = []
        for folder in folders {
            let infoURL = folder.appendingPathComponent(CoreMLModelStore.infoFileName)
            guard let data = try? Data(contentsOf: infoURL), let model = try? JSONDecoder().decode(InstalledModel.self, from: data) else { continue }
            loaded.append(model)
        }
        models = loaded.sorted { $0.importedAt > $1.importedAt }
    }

    func model(withID id: String?) -> InstalledModel? {
        guard let id else { return nil }
        return models.first { $0.id == id }
    }

    func importModel(from url: URL, l: L10n) async -> InstalledModel? {
        isImporting = true
        lastError = nil
        defer { isImporting = false }
        do {
            let installed = try await CoreMLModelStore.install(from: url)
            reload()
            return installed
        } catch let error as ModelImportError {
            lastError = error.message(l)
        } catch {
            lastError = ModelImportError.copyFailed(error.localizedDescription).message(l)
        }
        return nil
    }

    func delete(_ model: InstalledModel) {
        try? FileManager.default.removeItem(at: CoreMLModelStore.folder(forID: model.id))
        Task { await CoreMLGeneratorCache.shared.evict(model.id) }
        reload()
    }

    // MARK: - Installation (off the main actor)

    private nonisolated static func install(from url: URL) async throws -> InstalledModel {
        let fileManager = FileManager.default
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        // Что именно выбрал пользователь: саму модель или папку с комплектом.
        let modelExtensions = ["mlmodelc", "mlpackage", "mlmodel"]
        var source: URL?
        var tokenizer: URL?
        var manifest: URL?
        if modelExtensions.contains(url.pathExtension.lowercased()) {
            source = url
            let sibling = url.deletingLastPathComponent()
            let tokenizerCandidate = sibling.appendingPathComponent(tokenizerFileName)
            if fileManager.fileExists(atPath: tokenizerCandidate.path) { tokenizer = tokenizerCandidate }
        } else {
            let items = (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            for preferred in modelExtensions where source == nil {
                source = items.first { $0.pathExtension.lowercased() == preferred }
            }
            tokenizer = items.first { $0.lastPathComponent == tokenizerFileName }
            manifest = items.first { $0.lastPathComponent == manifestFileName }
        }
        guard let source else { throw ModelImportError.noModelFound }

        let id = UUID().uuidString
        let folder = CoreMLModelStore.folder(forID: id)
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw ModelImportError.copyFailed(error.localizedDescription)
        }
        let compiledURL = folder.appendingPathComponent(modelFileName)

        do {
            if source.pathExtension.lowercased() == "mlmodelc" {
                try fileManager.copyItem(at: source, to: compiledURL)
            } else {
                let temporary: URL
                do {
                    temporary = try await MLModel.compileModel(at: source)
                } catch {
                    throw ModelImportError.compileFailed(error.localizedDescription)
                }
                try fileManager.moveItem(at: temporary, to: compiledURL)
            }
            if let tokenizer { try fileManager.copyItem(at: tokenizer, to: folder.appendingPathComponent(tokenizerFileName)) }
            if let manifest { try fileManager.copyItem(at: manifest, to: folder.appendingPathComponent(manifestFileName)) }
        } catch let error as ModelImportError {
            try? fileManager.removeItem(at: folder)
            throw error
        } catch {
            try? fileManager.removeItem(at: folder)
            throw ModelImportError.copyFailed(error.localizedDescription)
        }

        // Изучаем интерфейс модели.
        var kind = InstalledModel.Kind.unsupported
        var summary = ""
        do {
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .cpuOnly
            let model = try MLModel(contentsOf: compiledURL, configuration: configuration)
            let description = model.modelDescription
            let inputs = description.inputDescriptionsByName
            let outputs = description.outputDescriptionsByName
            summary = "in: " + inputs.keys.sorted().joined(separator: ", ") + " · out: " + outputs.keys.sorted().joined(separator: ", ")
            var stateful = false
            if #available(iOS 18.0, *) {
                stateful = !description.stateDescriptionsByName.isEmpty
            }
            if inputs.keys.contains(where: { CoreMLTextGenerator.inputNames.contains($0) }), !stateful {
                kind = .textGenerator
            } else if inputs.count == 1, inputs.values.first?.type == .string, description.predictedFeatureName != nil {
                kind = .subjectClassifier
            }
            if stateful { summary += " · stateful" }
        } catch {
            try? fileManager.removeItem(at: folder)
            throw ModelImportError.compileFailed(error.localizedDescription)
        }

        var manifestName: String?
        if let manifest, let data = try? Data(contentsOf: manifest) {
            manifestName = (try? JSONDecoder().decode(ModelManifest.self, from: data))?.name
        }
        let displayName = manifestName ?? source.deletingPathExtension().lastPathComponent
        let installed = InstalledModel(
            id: id, name: displayName, kind: kind, importedAt: Date(), sizeBytes: folderSize(folder),
            hasTokenizer: tokenizer != nil, summary: summary)
        if let data = try? JSONEncoder().encode(installed) {
            try? data.write(to: folder.appendingPathComponent(infoFileName))
        }
        return installed
    }

    private nonisolated static func folderSize(_ folder: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}
