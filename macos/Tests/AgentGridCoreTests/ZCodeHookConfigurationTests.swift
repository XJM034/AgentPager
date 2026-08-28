import Foundation
import Testing
@testable import AgentGridCore

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

    #expect(try Data(contentsOf: backupURL) == original)
    #expect((root["custom"] as? [String: Any])?["keep"] as? Bool == true)
    #expect(hooks["enabled"] as? Bool == true)
    #expect(hooks["timeoutMs"] as? Int == 9_000)
    #expect(events["FutureEvent"] != nil)
    #expect(sessionStart.count == 2)
    #expect(events["PermissionRequest"] == nil)
    #expect(events["PostToolUseFailure"] == nil)
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

    #expect(!second.changed)
    #expect(repairedSessionStart.count == 2)
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
