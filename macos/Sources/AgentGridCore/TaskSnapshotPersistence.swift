import Foundation

public struct TaskSnapshotPersistence: Sendable {
    public let fileURL: URL

    public init(fileURL: URL = Self.defaultFileURL) {
        self.fileURL = fileURL
    }

    public func load() -> [TaskSnapshot] {
        guard let data = try? Data(contentsOf: fileURL) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return (try? decoder.decode([TaskSnapshot].self, from: data)) ?? []
    }

    public func save(_ tasks: [TaskSnapshot]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]

        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try encoder.encode(tasks).write(to: fileURL, options: .atomic)
    }

    public static var defaultFileURL: URL {
        let applicationSupport =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
        return applicationSupport
            .appendingPathComponent("AgentGrid", isDirectory: true)
            .appendingPathComponent("tasks.json")
    }
}
