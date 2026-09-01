import Foundation
import SwiftData

// Loads the app's ModelContainer, plus a destructive reset path so the UI can recover from a
// corrupt store instead of crashing on launch.
enum ModelContainerLoader {
    // MUST track the newest schema version, bumped in the SAME commit that adds one. The
    // `Word`/`Book` typealiases point at the current version, so an older value here builds a
    // container whose entities don't match the app's models — the new stage never runs and
    // SwiftData traps. Bump this, the typealiases, and CamuseanMigrationPlan together.
    private static let schema = Schema(versionedSchema: CamuseanSchemaV4.self)

    static let configuration = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: false
    )

    static func load() -> Result<ModelContainer, Error> {
        do {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: CamuseanMigrationPlan.self,
                configurations: [configuration]
            )
            return .success(container)
        } catch {
            return .failure(error)
        }
    }

    static func resetStore() throws {
        try deleteStoreFiles(at: configuration.url)
    }

    // Exposed for tests so file deletion can run against a temp URL, not the real container.
    static func deleteStoreFiles(at storeURL: URL) throws {
        let fm = FileManager.default
        let sidecars = [
            storeURL,
            URL(filePath: storeURL.path + "-wal"),
            URL(filePath: storeURL.path + "-shm"),
        ]
        for url in sidecars where fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }
}
