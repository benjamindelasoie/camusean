import Foundation
import Testing
@testable import camusean

@Suite("ModelContainerLoader.deleteStoreFiles")
struct ModelContainerLoaderTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelContainerLoaderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("removes .store, -wal, and -shm when all three are present")
    func deletesAllSidecars() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let storeURL = dir.appendingPathComponent("Test.store")
        let walURL = URL(filePath: storeURL.path + "-wal")
        let shmURL = URL(filePath: storeURL.path + "-shm")

        try Data("store".utf8).write(to: storeURL)
        try Data("wal".utf8).write(to: walURL)
        try Data("shm".utf8).write(to: shmURL)

        try ModelContainerLoader.deleteStoreFiles(at: storeURL)

        #expect(!FileManager.default.fileExists(atPath: storeURL.path))
        #expect(!FileManager.default.fileExists(atPath: walURL.path))
        #expect(!FileManager.default.fileExists(atPath: shmURL.path))
    }

    @Test("no-op when no store files exist")
    func noOpWhenAbsent() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let storeURL = dir.appendingPathComponent("Missing.store")

        // Must not throw even though nothing is on disk.
        try ModelContainerLoader.deleteStoreFiles(at: storeURL)
    }

    @Test("removes only the sidecars that exist")
    func deletesPartialSet() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let storeURL = dir.appendingPathComponent("Partial.store")
        let walURL = URL(filePath: storeURL.path + "-wal")

        try Data("store".utf8).write(to: storeURL)
        // no -wal, no -shm

        try ModelContainerLoader.deleteStoreFiles(at: storeURL)

        #expect(!FileManager.default.fileExists(atPath: storeURL.path))
        #expect(!FileManager.default.fileExists(atPath: walURL.path))
    }
}
