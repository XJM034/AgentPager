import Foundation
import Testing
@testable import AgentGridCore

@Test("ZCode Hook 安装器注册全部七类事件")
func zcodeHookInstallerRegistersAllSevenEvents() throws {
    let mutation = try ZCodeHookInstaller.install(
        existingData: Data(#"{"custom":"keep"}"#.utf8),
        command: "/tmp/AgentPagerHooks"
    )
    let contents = try #require(mutation.contents)
    let root = try #require(
        JSONSerialization.jsonObject(with: contents) as? [String: Any]
    )
    let hooks = try #require(root["hooks"] as? [String: Any])
    let events = try #require(hooks["events"] as? [String: Any])
    let expected = Set([
        "SessionStart",
        "UserPromptSubmit",
        "PreToolUse",
        "PermissionRequest",
        "PostToolUse",
        "PostToolUseFailure",
        "Stop",
    ])

    #expect(Set(events.keys) == expected)
    #expect(ZCodeHookInstaller.managedEventNames == expected)
}

@Test("ZCode Hook 卸载器只删除受管项并保留混合组与用户字段")
func zcodeHookInstallerUninstallsOnlyManagedHooks() throws {
    let existing = Data(
        """
        {
          "custom": {"keep": true},
          "hooks": {
            "enabled": true,
            "events": {
              "FutureEvent": [{"hooks": [{"type": "command", "command": "future-hook"}]}],
              "SessionStart": [{
                "matcher": "all",
                "hooks": [
                  {"type": "command", "command": "third-party-hook"},
                  {"type": "process", "command": "/tmp/AgentPagerHooks", "args": ["--source", "zcode"], "statusMessage": "Managed by AgentPager (ZCode)"}
                ]
              }],
              "PermissionRequest": [{
                "hooks": [{"type": "process", "command": "/tmp/AgentPagerHooks", "args": ["--source", "zcode"], "statusMessage": "Managed by AgentPager (ZCode)"}]
              }]
            }
          }
        }
        """.utf8
    )

    let mutation = try ZCodeHookInstaller.uninstall(existingData: existing)
    let contents = try #require(mutation.contents)
    let root = try #require(
        JSONSerialization.jsonObject(with: contents) as? [String: Any]
    )
    let hooks = try #require(root["hooks"] as? [String: Any])
    let events = try #require(hooks["events"] as? [String: Any])
    let sessionStart = try #require(events["SessionStart"] as? [[String: Any]])
    let firstGroup = try #require(sessionStart.first)
    let remainingHooks = try #require(firstGroup["hooks"] as? [[String: Any]])

    #expect(mutation.changed)
    #expect(mutation.hasRemainingHooks)
    #expect((root["custom"] as? [String: Any])?["keep"] as? Bool == true)
    #expect(hooks["enabled"] as? Bool == true)
    #expect(events["FutureEvent"] != nil)
    #expect(events["PermissionRequest"] == nil)
    #expect(firstGroup["matcher"] as? String == "all")
    let remainingHook = try #require(remainingHooks.single)
    #expect(remainingHook["command"] as? String == "third-party-hook")
    #expect(!ZCodeHookInstaller.isInstalled(data: contents, command: "/tmp/AgentPagerHooks"))

    let second = try ZCodeHookInstaller.uninstall(existingData: contents)
    #expect(!second.changed)
}

@Test("ZCode Hook 最小安装保留用户配置、创建备份且重复修复不叠加")
func zcodeHookConfigurationInstallsSafelyAndIdempotently() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let settingsURL = directory.appendingPathComponent("config.json")
    let original = Data(
        """
        {
          "custom": {"keep": true},
          "hooks": {
            "enabled": false,
            "timeoutMs": 9000,
            "events": {
              "FutureEvent": [{"hooks": [{"type": "command", "command": "future-hook"}]}],
              "SessionStart": [{"hooks": [{"type": "command", "command": "user-hook"}]}]
            }
          }
        }
        """.utf8
    )
    try original.write(to: settingsURL)
    let configuration = ZCodeHookConfiguration(settingsURL: settingsURL)
    let command = "/tmp/AgentPagerHooks"

    let first = try configuration.install(
        command: command,
        now: Date(timeIntervalSince1970: 50_000)
    )
    let backupURL = try #require(first.backupURL)
    let installed = try Data(contentsOf: settingsURL)
    let root = try #require(
        JSONSerialization.jsonObject(with: installed) as? [String: Any]
    )
    let hooks = try #require(root["hooks"] as? [String: Any])
    let events = try #require(hooks["events"] as? [String: Any])
    let sessionStart = try #require(events["SessionStart"] as? [[String: Any]])
    let managedHooks = try #require(sessionStart.last?["hooks"] as? [[String: Any]])
    let managedHook = try #require(managedHooks.first)
    let backupAttributes = try FileManager.default.attributesOfItem(
        atPath: backupURL.path
    )
    let backupPermissions = try #require(
        backupAttributes[.posixPermissions] as? NSNumber
    ).intValue & 0o777

    #expect(first.status == .installed)
    #expect(try Data(contentsOf: backupURL) == original)
    #expect(backupPermissions == 0o600)
    #expect((root["custom"] as? [String: Any])?["keep"] as? Bool == true)
    #expect(hooks["enabled"] as? Bool == true)
    #expect(hooks["timeoutMs"] as? Int == 9_000)
    #expect(events["FutureEvent"] != nil)
    #expect(sessionStart.count == 2)
    #expect(events["PermissionRequest"] != nil)
    #expect(events["PostToolUseFailure"] != nil)
    #expect(managedHook["type"] as? String == "process")
    #expect(managedHook["command"] as? String == command)
    #expect(managedHook["args"] as? [String] == ["--source", "zcode"])
    #expect(configuration.isInstalled(command: command))

    let second = try configuration.install(command: command)
    let repaired = try Data(contentsOf: settingsURL)
    let repairedRoot = try #require(
        JSONSerialization.jsonObject(with: repaired) as? [String: Any]
    )
    let repairedHooks = try #require(repairedRoot["hooks"] as? [String: Any])
    let repairedEvents = try #require(repairedHooks["events"] as? [String: Any])
    let repairedSessionStart = try #require(
        repairedEvents["SessionStart"] as? [[String: Any]]
    )

    #expect(second.status == .unchanged)
    #expect(!second.changed)
    #expect(second.backupURL == nil)
    #expect(repairedSessionStart.count == 2)
    let backupFiles = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
    ).filter { $0.lastPathComponent.contains("agentpager-zcode-backup") }
    #expect(backupFiles.count == 1)
}

@Test("ZCode Hook 同秒备份冲突仍保留受管前缀和 absent 后缀")
func zcodeHookConfigurationKeepsManagedNameForBackupCollisions() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let settingsURL = directory.appendingPathComponent("config.json")
    let configuration = ZCodeHookConfiguration(settingsURL: settingsURL)
    let timestamp = 55_000
    let occupiedAbsentURL = directory.appendingPathComponent(
        "config.json.agentpager-zcode-backup-\(timestamp).absent"
    )
    try Data("occupied".utf8).write(to: occupiedAbsentURL)

    let absentInstall = try configuration.install(
        command: "/tmp/AgentPagerHooks",
        now: Date(timeIntervalSince1970: TimeInterval(timestamp))
    )
    let absentBackupURL = try #require(absentInstall.backupURL)
    #expect(
        absentBackupURL.lastPathComponent
            == "config.json.agentpager-zcode-backup-\(timestamp)-1.absent"
    )

    let repaired = try configuration.install(
        command: "/new/AgentPagerHooks",
        now: Date(timeIntervalSince1970: TimeInterval(timestamp))
    )
    let presentBackupURL = try #require(repaired.backupURL)
    let secondRepair = try configuration.install(
        command: "/newer/AgentPagerHooks",
        now: Date(timeIntervalSince1970: TimeInterval(timestamp))
    )
    let secondPresentBackupURL = try #require(secondRepair.backupURL)

    #expect(
        presentBackupURL.lastPathComponent
            == "config.json.agentpager-zcode-backup-\(timestamp)"
    )
    #expect(
        secondPresentBackupURL.lastPathComponent
            == "config.json.agentpager-zcode-backup-\(timestamp)-1"
    )
}

@Test("ZCode Hook 安装遇到损坏结构时拒绝覆盖原文件")
func zcodeHookConfigurationRejectsInvalidStructure() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let settingsURL = directory.appendingPathComponent("config.json")
    let original = Data(#"{"hooks":{"events":"unexpected"}}"#.utf8)
    try original.write(to: settingsURL)
    let configuration = ZCodeHookConfiguration(settingsURL: settingsURL)

    #expect(throws: ZCodeHookConfigurationError.self) {
        try configuration.install(command: "/tmp/AgentPagerHooks")
    }
    #expect(try Data(contentsOf: settingsURL) == original)
}

@Test("ZCode Hook 遇到无法安全解析的事件组时拒绝覆盖")
func zcodeHookConfigurationRejectsMalformedManagedEventGroup() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let settingsURL = directory.appendingPathComponent("config.json")
    let original = Data(
        #"{"hooks":{"events":{"SessionStart":[{"matcher":"all","hooks":"unexpected"}]}}}"#.utf8
    )
    try original.write(to: settingsURL)
    let configuration = ZCodeHookConfiguration(settingsURL: settingsURL)

    #expect(throws: ZCodeHookConfigurationError.self) {
        try configuration.install(command: "/tmp/AgentPagerHooks")
    }
    #expect(try Data(contentsOf: settingsURL) == original)
}

@Test("ZCode Hook 原子写入失败时恢复原配置且不留下半写内容")
func zcodeHookConfigurationRollsBackFailedWrite() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let settingsURL = directory.appendingPathComponent("config.json")
    let original = Data(#"{"custom":"keep"}"#.utf8)
    try original.write(to: settingsURL)
    let configuration = ZCodeHookConfiguration(
        settingsURL: settingsURL,
        replacementWriter: { _, target in
            try Data("partial".utf8).write(to: target)
            throw CocoaError(.fileWriteUnknown)
        }
    )

    #expect(throws: ZCodeHookFileError.writeFailed) {
        try configuration.install(
            command: "/tmp/AgentPagerHooks",
            now: Date(timeIntervalSince1970: 60_000)
        )
    }
    #expect(try Data(contentsOf: settingsURL) == original)
    let backupURL = directory
        .appendingPathComponent("config.json.agentpager-zcode-backup-60000")
    #expect(try Data(contentsOf: backupURL) == original)
}

@Test("ZCode Hook 配置卸载保留安装后新增字段并创建恢复点")
func zcodeHookConfigurationUninstallsSafely() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let settingsURL = directory.appendingPathComponent("config.json")
    try Data(#"{"custom":{"before":true}}"#.utf8).write(to: settingsURL)
    let configuration = ZCodeHookConfiguration(settingsURL: settingsURL)
    _ = try configuration.install(
        command: "/tmp/AgentPagerHooks",
        now: Date(timeIntervalSince1970: 70_000)
    )

    var installedRoot = try #require(
        JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any]
    )
    installedRoot["afterInstall"] = "keep"
    let beforeUninstall = try JSONSerialization.data(
        withJSONObject: installedRoot,
        options: [.prettyPrinted, .sortedKeys]
    )
    try beforeUninstall.write(to: settingsURL)

    let change = try configuration.uninstall(
        now: Date(timeIntervalSince1970: 70_001)
    )
    let backupURL = try #require(change.backupURL)
    let remaining = try #require(
        JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any]
    )

    #expect(change.status == .uninstalled)
    #expect(try Data(contentsOf: backupURL) == beforeUninstall)
    #expect(remaining["afterInstall"] as? String == "keep")
    #expect(!configuration.isInstalled(command: "/tmp/AgentPagerHooks"))

    let second = try configuration.uninstall()
    #expect(second.status == .alreadyUninstalled)
    #expect(second.backupURL == nil)
}

@Test("ZCode Hook 恢复需要确认并拒绝覆盖确认后的新改动")
func zcodeHookConfigurationRestoresWithFreshConfirmation() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let settingsURL = directory.appendingPathComponent("config.json")
    let original = Data(#"{"custom":"original"}"#.utf8)
    try original.write(to: settingsURL)
    let configuration = ZCodeHookConfiguration(settingsURL: settingsURL)
    let installation = try configuration.install(
        command: "/tmp/AgentPagerHooks",
        now: Date(timeIntervalSince1970: 80_000)
    )
    let originalBackupURL = try #require(installation.backupURL)

    let firstPreparation = try configuration.prepareRestoreLatestBackup()
    let stalePlan = try #require(firstPreparation.restorePlan)
    #expect(firstPreparation.status == .restoreConfirmationRequired)

    let userChanged = Data(#"{"custom":"added-after-confirmation"}"#.utf8)
    try userChanged.write(to: settingsURL)
    #expect(throws: ZCodeHookFileError.configurationChangedAfterConfirmation) {
        try configuration.restoreLatestBackup(using: stalePlan)
    }
    #expect(try Data(contentsOf: settingsURL) == userChanged)

    let secondPreparation = try configuration.prepareRestoreLatestBackup()
    let freshPlan = try #require(secondPreparation.restorePlan)
    let restored = try configuration.restoreLatestBackup(
        using: freshPlan,
        now: Date(timeIntervalSince1970: 80_001)
    )
    let recoveryURL = try #require(restored.backupURL)

    #expect(restored.status == .restored)
    #expect(
        restored.restoredFromURL?.standardizedFileURL
            == originalBackupURL.standardizedFileURL
    )
    #expect(try Data(contentsOf: settingsURL) == original)
    #expect(try Data(contentsOf: recoveryURL) == userChanged)
    #expect(FileManager.default.fileExists(atPath: originalBackupURL.path))
}

@Test("ZCode Hook 首次安装记录原文件不存在并可恢复为不存在")
func zcodeHookConfigurationRestoresAbsentOriginal() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let settingsURL = directory.appendingPathComponent("config.json")
    let configuration = ZCodeHookConfiguration(settingsURL: settingsURL)

    let installation = try configuration.install(
        command: "/tmp/AgentPagerHooks",
        now: Date(timeIntervalSince1970: 90_000)
    )
    let absentBackupURL = try #require(installation.backupURL)
    #expect(absentBackupURL.pathExtension == "absent")
    #expect(FileManager.default.fileExists(atPath: settingsURL.path))

    let preparation = try configuration.prepareRestoreLatestBackup()
    let plan = try #require(preparation.restorePlan)
    let restored = try configuration.restoreLatestBackup(
        using: plan,
        now: Date(timeIntervalSince1970: 90_001)
    )

    #expect(restored.status == .restored)
    #expect(!FileManager.default.fileExists(atPath: settingsURL.path))
    #expect(FileManager.default.fileExists(atPath: absentBackupURL.path))
}

@Test("ZCode Hook 无效 JSON 与无备份状态都明确且不覆盖")
func zcodeHookConfigurationReportsInvalidJSONAndMissingBackup() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let settingsURL = directory.appendingPathComponent("config.json")
    let configuration = ZCodeHookConfiguration(settingsURL: settingsURL)

    let noBackup = try configuration.prepareRestoreLatestBackup()
    #expect(noBackup.status == .noBackup)

    let invalid = Data("{invalid".utf8)
    try invalid.write(to: settingsURL)
    #expect(throws: ZCodeHookFileError.invalidJSON) {
        try configuration.install(command: "/tmp/AgentPagerHooks")
    }
    #expect(try Data(contentsOf: settingsURL) == invalid)
}

@Test("ZCode Hook 修复返回明确状态并备份旧受管配置")
func zcodeHookConfigurationReportsRepairStatus() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let settingsURL = directory.appendingPathComponent("config.json")
    let stale = Data(
        """
        {
          "hooks": {
            "events": {
              "SessionStart": [{
                "hooks": [{
                  "type": "process",
                  "command": "/old/AgentPagerHooks",
                  "args": ["--source", "zcode"],
                  "statusMessage": "Managed by AgentPager (ZCode)"
                }]
              }]
            }
          }
        }
        """.utf8
    )
    try stale.write(to: settingsURL)
    let configuration = ZCodeHookConfiguration(settingsURL: settingsURL)

    #expect(configuration.containsManagedHooks())
    #expect(!configuration.isInstalled(command: "/new/AgentPagerHooks"))

    let repair = try configuration.install(
        command: "/new/AgentPagerHooks",
        now: Date(timeIntervalSince1970: 100_000)
    )
    let backupURL = try #require(repair.backupURL)

    #expect(repair.status == .repaired)
    #expect(try Data(contentsOf: backupURL) == stale)
    #expect(configuration.containsManagedHooks())
    #expect(configuration.isInstalled(command: "/new/AgentPagerHooks"))
}

@Test("ZCode Hook 修复只替换受管 Hook 并保留同组第三方 Hook")
func zcodeHookRepairPreservesThirdPartyHookInManagedGroup() throws {
    let existing = Data(
        """
        {
          "hooks": {
            "events": {
              "SessionStart": [{
                "matcher": "all",
                "hooks": [
                  {"type": "command", "command": "third-party-hook"},
                  {
                    "type": "process",
                    "command": "/old/AgentPagerHooks",
                    "args": ["--source", "zcode"],
                    "statusMessage": "Managed by AgentPager (ZCode)"
                  }
                ]
              }]
            }
          }
        }
        """.utf8
    )

    let mutation = try ZCodeHookInstaller.install(
        existingData: existing,
        command: "/new/AgentPagerHooks"
    )
    let contents = try #require(mutation.contents)
    let root = try #require(
        JSONSerialization.jsonObject(with: contents) as? [String: Any]
    )
    let hooks = try #require(root["hooks"] as? [String: Any])
    let events = try #require(hooks["events"] as? [String: Any])
    let groups = try #require(events["SessionStart"] as? [[String: Any]])
    let preservedHooks = try #require(groups.first?["hooks"] as? [[String: Any]])

    #expect(groups.first?["matcher"] as? String == "all")
    #expect(preservedHooks.count == 1)
    #expect(preservedHooks.first?["command"] as? String == "third-party-hook")
    #expect(groups.count == 2)
}
