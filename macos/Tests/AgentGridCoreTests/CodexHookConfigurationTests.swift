import Foundation
import Testing
@testable import AgentGridCore

@Test("Hook Configuration 安装时保留配置并创建可恢复备份")
func hookConfigurationInstallsWithBackup() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let hooksURL = directory.appendingPathComponent("hooks.json")
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
    try original.write(to: hooksURL)
    let configuration = CodexHookConfiguration(hooksURL: hooksURL)

    let change = try configuration.install(
        command: "/tmp/AgentGridHooks",
        now: Date(timeIntervalSince1970: 10_000)
    )
    let backupURL = try #require(change.backupURL)
    let installed = try Data(contentsOf: hooksURL)

    #expect(change.changed)
    #expect(try Data(contentsOf: backupURL) == original)
    #expect(configuration.isInstalled())
    let root = try #require(
        JSONSerialization.jsonObject(with: installed) as? [String: Any]
    )
    #expect((root["custom"] as? [String: Any])?["enabled"] as? Bool == true)
}

@Test("Hook Configuration 卸载只移除 AgentGrid 管理项")
func hookConfigurationUninstallsWithoutTouchingUserHooks() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let hooksURL = directory.appendingPathComponent("hooks.json")
    let configuration = CodexHookConfiguration(hooksURL: hooksURL)

    _ = try configuration.install(command: "/tmp/AgentGridHooks")
    var root = try #require(
        JSONSerialization.jsonObject(
            with: Data(contentsOf: hooksURL)
        ) as? [String: Any]
    )
    root["custom"] = "保留"
    try JSONSerialization.data(
        withJSONObject: root,
        options: [.prettyPrinted, .sortedKeys]
    ).write(to: hooksURL)

    let installed = try Data(contentsOf: hooksURL)
    let change = try configuration.uninstall(
        now: Date(timeIntervalSince1970: 30_000)
    )
    let backupURL = try #require(change.backupURL)
    let remaining = try #require(
        JSONSerialization.jsonObject(
            with: Data(contentsOf: hooksURL)
        ) as? [String: Any]
    )

    #expect(change.changed)
    #expect(try Data(contentsOf: backupURL) == installed)
    #expect(remaining["custom"] as? String == "保留")
    #expect(!configuration.isInstalled())
}

@Test("Hook Configuration 可恢复最近备份并保护恢复前文件")
func hookConfigurationRestoresLatestBackupSafely() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let hooksURL = directory.appendingPathComponent("hooks.json")
    let original = Data("{\"custom\":\"原始配置\"}".utf8)
    try original.write(to: hooksURL)
    let configuration = CodexHookConfiguration(hooksURL: hooksURL)
    _ = try configuration.install(
        command: "/tmp/AgentGridHooks",
        now: Date(timeIntervalSince1970: 20_000)
    )
    let beforeRestore = try Data(contentsOf: hooksURL)

    let change = try configuration.restoreLatestBackup(
        now: Date(timeIntervalSince1970: 20_001)
    )
    let recoveryURL = try #require(change.backupURL)

    #expect(change.changed)
    #expect(try Data(contentsOf: hooksURL) == original)
    #expect(try Data(contentsOf: recoveryURL) == beforeRestore)
}
