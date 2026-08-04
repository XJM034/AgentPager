import Foundation
import Testing
@testable import AgentGridCore

@Test("Claude Hook Configuration 安装时保留配置并创建可恢复备份")
func claudeHookConfigurationInstallsWithBackup() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let settingsURL = directory.appendingPathComponent("settings.json")
    let original = Data(
        """
        {
          "custom": {"enabled": true},
          "hooks": {
            "Stop": [{"hooks": [{"type": "command", "command": "user-stop"}]}]
          }
        }
        """.utf8
    )
    try original.write(to: settingsURL)
    let configuration = ClaudeHookConfiguration(settingsURL: settingsURL)

    let change = try configuration.install(
        command: "'/tmp/AgentPagerHooks' --source claude",
        now: Date(timeIntervalSince1970: 10_000)
    )
    let backupURL = try #require(change.backupURL)
    let installed = try Data(contentsOf: settingsURL)

    #expect(change.changed)
    #expect(try Data(contentsOf: backupURL) == original)
    #expect(configuration.isInstalled())
    let root = try #require(
        JSONSerialization.jsonObject(with: installed) as? [String: Any]
    )
    #expect((root["custom"] as? [String: Any])?["enabled"] as? Bool == true)
}

@Test("Claude Hook Configuration 卸载只移除 AgentPager 管理项")
func claudeHookConfigurationUninstallsWithoutTouchingUserHooks() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let settingsURL = directory.appendingPathComponent("settings.json")
    let configuration = ClaudeHookConfiguration(settingsURL: settingsURL)

    _ = try configuration.install(command: "'/tmp/AgentPagerHooks' --source claude")
    var root = try #require(
        JSONSerialization.jsonObject(
            with: Data(contentsOf: settingsURL)
        ) as? [String: Any]
    )
    root["custom"] = "保留"
    try JSONSerialization.data(
        withJSONObject: root,
        options: [.prettyPrinted, .sortedKeys]
    ).write(to: settingsURL)

    let installed = try Data(contentsOf: settingsURL)
    let change = try configuration.uninstall(
        now: Date(timeIntervalSince1970: 30_000)
    )
    let backupURL = try #require(change.backupURL)
    let remaining = try #require(
        JSONSerialization.jsonObject(
            with: Data(contentsOf: settingsURL)
        ) as? [String: Any]
    )

    #expect(change.changed)
    #expect(try Data(contentsOf: backupURL) == installed)
    #expect(remaining["custom"] as? String == "保留")
    #expect(!configuration.isInstalled())
}

@Test("Claude Hook Configuration 可恢复最近备份并保护恢复前文件")
func claudeHookConfigurationRestoresLatestBackupSafely() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let settingsURL = directory.appendingPathComponent("settings.json")
    let original = Data("{\"custom\":\"原始配置\"}".utf8)
    try original.write(to: settingsURL)
    let configuration = ClaudeHookConfiguration(settingsURL: settingsURL)
    _ = try configuration.install(
        command: "'/tmp/AgentPagerHooks' --source claude",
        now: Date(timeIntervalSince1970: 20_000)
    )
    let beforeRestore = try Data(contentsOf: settingsURL)

    let change = try configuration.restoreLatestBackup(
        now: Date(timeIntervalSince1970: 20_001)
    )
    let recoveryURL = try #require(change.backupURL)

    #expect(change.changed)
    #expect(try Data(contentsOf: settingsURL) == original)
    #expect(try Data(contentsOf: recoveryURL) == beforeRestore)
}
