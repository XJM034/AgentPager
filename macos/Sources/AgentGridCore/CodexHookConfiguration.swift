import Foundation

public struct HookConfigurationChange: Equatable, Sendable {
    public var changed: Bool
    public var backupURL: URL?

    public init(changed: Bool, backupURL: URL? = nil) {
        self.changed = changed
        self.backupURL = backupURL
    }
}

public struct CodexHookConfiguration: Sendable {
    public let hooksURL: URL

    public init(hooksURL: URL? = nil) {
        self.hooksURL = hooksURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/hooks.json")
    }

    public func isInstalled() -> Bool {
        CodexHookInstaller.isInstalled(
            data: try? Data(contentsOf: hooksURL)
        )
    }

    public func install(
        command: String,
        now: Date = .now
    ) throws -> HookConfigurationChange {
        let existing = try? Data(contentsOf: hooksURL)
        let mutation = try CodexHookInstaller.install(
            existingData: existing,
            command: command
        )
        guard mutation.changed, let contents = mutation.contents else {
            return HookConfigurationChange(changed: false)
        }

        try createParentDirectory()
        let backupURL = try backup(
            existing,
            prefix: "hooks.json.agentgrid-backup",
            now: now
        )
        try contents.write(to: hooksURL, options: .atomic)
        return HookConfigurationChange(
            changed: true,
            backupURL: backupURL
        )
    }

    public func uninstall(
        now: Date = .now
    ) throws -> HookConfigurationChange {
        let existing = try? Data(contentsOf: hooksURL)
        let mutation = try CodexHookInstaller.uninstall(existingData: existing)
        guard mutation.changed else {
            return HookConfigurationChange(changed: false)
        }

        let backupURL = try backup(
            existing,
            prefix: "hooks.json.agentgrid-backup",
            now: now
        )
        if let contents = mutation.contents {
            try contents.write(to: hooksURL, options: .atomic)
        } else if FileManager.default.fileExists(atPath: hooksURL.path) {
            try FileManager.default.removeItem(at: hooksURL)
        }
        return HookConfigurationChange(
            changed: true,
            backupURL: backupURL
        )
    }

    public func restoreLatestBackup(
        now: Date = .now
    ) throws -> HookConfigurationChange {
        guard let backupURL = latestBackupURL() else {
            return HookConfigurationChange(changed: false)
        }
        let restored = try Data(contentsOf: backupURL)
        let existing = try? Data(contentsOf: hooksURL)
        guard restored != existing else {
            return HookConfigurationChange(changed: false)
        }

        try createParentDirectory()
        let recoveryURL = try backup(
            existing,
            prefix: "hooks.json.agentgrid-before-restore",
            now: now
        )
        try restored.write(to: hooksURL, options: .atomic)
        return HookConfigurationChange(
            changed: true,
            backupURL: recoveryURL
        )
    }

    private func createParentDirectory() throws {
        try FileManager.default.createDirectory(
            at: hooksURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private func backup(
        _ data: Data?,
        prefix: String,
        now: Date
    ) throws -> URL? {
        guard let data else {
            return nil
        }
        let baseURL = hooksURL.deletingLastPathComponent()
            .appendingPathComponent(
                "\(prefix)-\(Int(now.timeIntervalSince1970))"
            )
        var url = baseURL
        var suffix = 1
        while FileManager.default.fileExists(atPath: url.path) {
            url = URL(fileURLWithPath: "\(baseURL.path)-\(suffix)")
            suffix += 1
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    private func latestBackupURL() -> URL? {
        let directory = hooksURL.deletingLastPathComponent()
        let prefix = "hooks.json.agentgrid-backup-"
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        return files
            .filter { $0.lastPathComponent.hasPrefix(prefix) }
            .max { lhs, rhs in
                let lhsDate = try? lhs.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate
                let rhsDate = try? rhs.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate
                if lhsDate == rhsDate {
                    return lhs.lastPathComponent < rhs.lastPathComponent
                }
                return (lhsDate ?? .distantPast) < (rhsDate ?? .distantPast)
            }
    }
}
