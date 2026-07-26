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
            title: "AgentGrid · 优化像素动画",
            userPrompt: "这段用户原话不能写入磁盘",
            latestStep: "rm -rf 这段命令也不能写入磁盘",
            tokenUsage: TokenUsage(input: 100, output: 20, total: 120),
            subagents: [
                SubagentSnapshot(
                    id: "child-1",
                    path: "/root/private_worker",
                    latestStep: "子代理命令不能写入磁盘"
                ),
            ],
            lifecycle: .running,
            activity: .editing,
            startedAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 120),
            isPinned: true
        )

        try persistence.save([task])

        let loaded = try #require(persistence.load().first)
        #expect(loaded.title == task.title)
        #expect(loaded.tokenUsage == task.tokenUsage)
        #expect(loaded.userPrompt == nil)
        #expect(loaded.latestStep == nil)
        #expect(loaded.subagents.isEmpty)

        let storedText = try String(contentsOf: persistence.fileURL, encoding: .utf8)
        #expect(!storedText.contains("用户原话"))
        #expect(!storedText.contains("rm -rf"))
        #expect(!storedText.contains("private_worker"))
        #expect(!storedText.contains("子代理命令"))
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
