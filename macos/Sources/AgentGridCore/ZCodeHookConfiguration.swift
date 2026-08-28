import Foundation

/// ZCode 用户级 Hook 配置入口。Issue #4 只提供安装/修复与状态读取；
/// 卸载、完整备份管理和恢复流程留给 Issue #5。
public struct ZCodeHookConfiguration: Sendable {
    public let settingsURL: URL

    public init(settingsURL: URL? = nil) {
        self.settingsURL = settingsURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".zcode/cli/config.json")
    }

    public func isInstalled(command: String) -> Bool {
        ZCodeHookInstaller.isInstalled(
            data: try? Data(contentsOf: settingsURL),
            command: command
        )
    }

    public func install(
        command: String,
        now: Date = .now
    ) throws -> HookConfigurationChange {
        let existing: Data?
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            existing = try Data(contentsOf: settingsURL)
        } else {
            existing = nil
        }
        let mutation = try ZCodeHookInstaller.install(
            existingData: existing,
            command: command
        )
        guard mutation.changed, let contents = mutation.contents else {
            return HookConfigurationChange(changed: false)
        }

        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let backupURL = try backup(existing, now: now)
        try contents.write(to: settingsURL, options: .atomic)
        return HookConfigurationChange(changed: true, backupURL: backupURL)
    }

    private func backup(_ data: Data?, now: Date) throws -> URL? {
        guard let data else { return nil }
        let baseURL = settingsURL.deletingLastPathComponent()
            .appendingPathComponent(
                "config.json.agentpager-zcode-backup-\(Int(now.timeIntervalSince1970))"
            )
        var backupURL = baseURL
        var suffix = 1
        while FileManager.default.fileExists(atPath: backupURL.path) {
            backupURL = URL(fileURLWithPath: "\(baseURL.path)-\(suffix)")
            suffix += 1
        }
        try data.write(to: backupURL, options: .atomic)
        return backupURL
    }
}
