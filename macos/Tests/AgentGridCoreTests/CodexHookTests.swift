import Foundation
import Testing
@testable import AgentGridCore

@Test("Hook 安装保留用户已有配置")
func hookInstallerPreservesExistingHooks() throws {
    let existing = Data(
        """
        {
          "custom": true,
          "hooks": {
            "SessionStart": [
              {
                "matcher": "startup",
                "hooks": [
                  {"type": "command", "command": "/tmp/custom-hook", "timeout": 5}
                ]
              }
            ]
          }
        }
        """.utf8
    )

    let mutation = try CodexHookInstaller.install(
        existingData: existing,
        command: "/Applications/AgentGrid Bridge.app/Contents/MacOS/AgentGridHooks"
    )
    let installedContents = try #require(mutation.contents)
    let root = try #require(
        JSONSerialization.jsonObject(with: installedContents) as? [String: Any]
    )
    let hooks = try #require(root["hooks"] as? [String: Any])
    let groups = try #require(hooks["SessionStart"] as? [[String: Any]])

    #expect(root["custom"] as? Bool == true)
    #expect(groups.count == 2)
    #expect(CodexHookInstaller.isInstalled(data: mutation.contents))
}

@Test("Hook 卸载只删除 AgentGrid 管理项")
func hookUninstallOnlyRemovesManagedGroups() throws {
    let installed = try CodexHookInstaller.install(
        existingData: Data(
            """
            {
              "hooks": {
                "Stop": [
                  {"hooks": [{"type": "command", "command": "/tmp/custom"}]}
                ]
              }
            }
            """.utf8
        ),
        command: "/tmp/AgentGridHooks"
    )

    let uninstalled = try CodexHookInstaller.uninstall(existingData: installed.contents)
    let uninstalledContents = try #require(uninstalled.contents)
    let root = try #require(
        JSONSerialization.jsonObject(with: uninstalledContents) as? [String: Any]
    )
    let hooks = try #require(root["hooks"] as? [String: Any])
    let stopGroups = try #require(hooks["Stop"] as? [[String: Any]])
    #expect(stopGroups.count == 1)
    #expect(!CodexHookInstaller.isInstalled(data: uninstalled.contents))
}
