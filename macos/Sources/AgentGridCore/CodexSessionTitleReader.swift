import Foundation

public struct CodexSessionTitleReader: Sendable {
    private struct Entry: Decodable {
        let id: String
        let threadName: String
        let updatedAt: String

        enum CodingKeys: String, CodingKey {
            case id
            case threadName = "thread_name"
            case updatedAt = "updated_at"
        }
    }

    public var indexURL: URL

    public init(indexURL: URL? = nil) {
        self.indexURL = indexURL ?? Self.defaultIndexURL()
    }

    public func loadTitles() -> [String: String] {
        guard let data = try? Data(contentsOf: indexURL) else {
            return [:]
        }
        return Self.titles(from: data)
    }

    public static func titles(from data: Data) -> [String: String] {
        let decoder = JSONDecoder()
        var latestEntries: [String: Entry] = [:]

        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard let entry = try? decoder.decode(Entry.self, from: Data(line)),
                  let id = normalized(entry.id),
                  let title = normalized(entry.threadName) else {
                continue
            }

            let normalizedEntry = Entry(
                id: id,
                threadName: title,
                updatedAt: entry.updatedAt
            )
            if let current = latestEntries[id],
               current.updatedAt > normalizedEntry.updatedAt {
                continue
            }
            latestEntries[id] = normalizedEntry
        }

        return latestEntries.mapValues(\.threadName)
    }

    private static func defaultIndexURL() -> URL {
        if let configuredHome = normalized(
            ProcessInfo.processInfo.environment["CODEX_HOME"]
        ) {
            return URL(fileURLWithPath: configuredHome, isDirectory: true)
                .appendingPathComponent("session_index.jsonl")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/session_index.jsonl")
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

public struct CodexSessionTitleSynchronizer: Sendable {
    private var synchronizedTitles: [String: String] = [:]

    public init() {}

    public func needsRefresh(for tasks: [TaskSnapshot]) -> Bool {
        // 标题源是 Codex 的 session_index.jsonl，只对 Codex 会话有意义；
        // Claude 会话的标题来自 UserPromptSubmit，无需进入该同步流程。
        tasks.contains {
            ($0.source == .codexCLI || $0.source == .codexDesktop)
            && !$0.isTerminal
            && synchronizedTitles[$0.id] == nil
        }
    }

    @discardableResult
    public mutating func applyAvailableTitles(
        _ availableTitles: [String: String],
        to catalog: inout TaskCatalog
    ) -> Bool {
        let taskIDs = Set(catalog.projection().tasks.map(\.id))
        let unresolvedTaskIDs = taskIDs.subtracting(synchronizedTitles.keys)
        for taskID in unresolvedTaskIDs {
            guard let title = availableTitles[taskID] else {
                continue
            }
            synchronizedTitles[taskID] = title
        }
        return catalog.applyAvailableTitles(synchronizedTitles)
    }
}
