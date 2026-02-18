import Foundation
import SwiftData

enum PersistenceController {
    static let currentSchemaVersion = 1

    private static let storeDirectoryName = "FocusedDayPlanner"
    private static let storeFileName = "FocusedDayPlanner.store"
    private static let metadataFileName = "StoreMetadata.json"

    static func makeModelContainer() throws -> ModelContainer {
        let schema = Schema([
            DayPlan.self,
            TodoItem.self,
            LinearLink.self
        ])

        let storeDirectory = try ensureStoreDirectory()
        let storeURL = storeDirectory.appendingPathComponent(storeFileName)
        try importLegacyStoreIfNeeded(targetStoreURL: storeURL)
        try migrateIfNeeded(storeDirectory: storeDirectory)

        let config = ModelConfiguration(schema: schema, url: storeURL)
        return try ModelContainer(for: schema, configurations: [config])
    }

    static func storeLocationDescription() -> String {
        do {
            let directory = try ensureStoreDirectory()
            return directory.appendingPathComponent(storeFileName).path
        } catch {
            return "Unavailable (\(error.localizedDescription))"
        }
    }

    static func storeDirectoryURL() -> URL? {
        try? ensureStoreDirectory()
    }

    private static func ensureStoreDirectory() throws -> URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw PersistenceError.appSupportUnavailable
        }

        let directory = appSupport.appendingPathComponent(storeDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func importLegacyStoreIfNeeded(targetStoreURL: URL) throws {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: targetStoreURL.path) else { return }

        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }

        let bundleID = Bundle.main.bundleIdentifier
        var candidates: [URL] = [
            appSupport.appendingPathComponent("default.store"),
            appSupport.appendingPathComponent("FocusedDayPlanner.store")
        ]
        if let bundleID {
            candidates.append(appSupport.appendingPathComponent("\(bundleID).store"))
            candidates.append(appSupport.appendingPathComponent(bundleID, isDirectory: true).appendingPathComponent("default.store"))
        }

        guard let sourceStore = candidates.first(where: { $0.path != targetStoreURL.path && fileManager.fileExists(atPath: $0.path) }) else {
            return
        }

        try fileManager.copyItem(at: sourceStore, to: targetStoreURL)

        let sourceShm = URL(filePath: sourceStore.path + "-shm")
        let sourceWal = URL(filePath: sourceStore.path + "-wal")
        let targetShm = URL(filePath: targetStoreURL.path + "-shm")
        let targetWal = URL(filePath: targetStoreURL.path + "-wal")

        if fileManager.fileExists(atPath: sourceShm.path) {
            try? fileManager.copyItem(at: sourceShm, to: targetShm)
        }
        if fileManager.fileExists(atPath: sourceWal.path) {
            try? fileManager.copyItem(at: sourceWal, to: targetWal)
        }
    }

    private static func migrateIfNeeded(storeDirectory: URL) throws {
        let metadataURL = storeDirectory.appendingPathComponent(metadataFileName)
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        var metadata: StoreMetadata
        if FileManager.default.fileExists(atPath: metadataURL.path) {
            let data = try Data(contentsOf: metadataURL)
            metadata = try decoder.decode(StoreMetadata.self, from: data)
        } else {
            metadata = StoreMetadata(schemaVersion: currentSchemaVersion, updatedAt: .now)
        }

        if metadata.schemaVersion > currentSchemaVersion {
            throw PersistenceError.futureSchema(version: metadata.schemaVersion)
        }

        if metadata.schemaVersion < currentSchemaVersion {
            // Reserved for future schema migrations.
            var version = metadata.schemaVersion
            while version < currentSchemaVersion {
                version += 1
                applyMigration(toVersion: version, storeDirectory: storeDirectory)
            }
            metadata.schemaVersion = currentSchemaVersion
        }

        metadata.updatedAt = .now
        let encoded = try encoder.encode(metadata)
        try encoded.write(to: metadataURL, options: .atomic)
    }

    private static func applyMigration(toVersion version: Int, storeDirectory: URL) {
        // Intentionally empty for v1. Add version-specific migration logic here.
        _ = storeDirectory
        _ = version
    }
}

private struct StoreMetadata: Codable {
    var schemaVersion: Int
    var updatedAt: Date
}

enum PersistenceError: LocalizedError {
    case appSupportUnavailable
    case futureSchema(version: Int)

    var errorDescription: String? {
        switch self {
        case .appSupportUnavailable:
            return "Application Support directory is unavailable."
        case let .futureSchema(version):
            return "Store was created by a newer app schema version (\(version))."
        }
    }
}
