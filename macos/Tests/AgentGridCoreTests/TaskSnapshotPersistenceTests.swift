import Foundation
import Testing
@testable import AgentGridCore

struct TaskSnapshotPersistenceTests {
    @Test
    func roundTripOnlyStoresTaskMetadata() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let persistence = TaskSnapshotPersistence(
            fileURL: directory.appendingPathComponent("tasks.json")
        )
        let task = TaskSnapshot(
            id: "task-1",
            source: .codexCLI,
            projectName: "AgentGrid",
            lifecycle: .running,
            activity: .editing,
            startedAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 120),
            isPinned: true
        )

        try persistence.save([task])

        #expect(persistence.load() == [task])
    }

    @Test
    func corruptedSnapshotFailsClosed() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory.appendingPathComponent("tasks.json")
        try Data("not-json".utf8).write(to: fileURL)

        #expect(TaskSnapshotPersistence(fileURL: fileURL).load().isEmpty)
    }
}
