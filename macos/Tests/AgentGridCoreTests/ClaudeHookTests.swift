import Foundation
import Testing
@testable import AgentGridCore

@Test("Claude Hook 安装覆盖全部生命周期事件并保留用户配置")
func claudeHookInstallerInstallsAllEvents() throws {
    let existing = Data(
        """
        {
          "custom": true,
          "hooks": {
            "SessionStart": [
              {
                "hooks": [
                  {"type": "command", "command": "/tmp/custom-hook", "timeout": 5}
                ]
              }
            ]
          }
        }
        """.utf8
    )

    let mutation = try ClaudeHookInstaller.install(
        existingData: existing,
        command: "'/Applications/AgentPager Bridge.app/Contents/MacOS/AgentPagerHooks' --source claude"
    )
    let installedContents = try #require(mutation.contents)
    let root = try #require(
        JSONSerialization.jsonObject(with: installedContents) as? [String: Any]
    )
    let hooks = try #require(root["hooks"] as? [String: Any])
    let sessionStartGroups = try #require(hooks["SessionStart"] as? [[String: Any]])

    #expect(root["custom"] as? Bool == true)
    // 用户已有项 + AgentPager 管理项
    #expect(sessionStartGroups.count == 2)
    #expect(ClaudeHookInstaller.isInstalled(data: mutation.contents))

    // 带 matcher 的事件必须写入 matcher 字段
    let preToolUseGroups = try #require(hooks["PreToolUse"] as? [[String: Any]])
    #expect(preToolUseGroups.first?["matcher"] as? String == "*")

    // PermissionRequest 必须带 24 小时超时
    let permissionGroups = try #require(hooks["PermissionRequest"] as? [[String: Any]])
    let permissionHooks = try #require(permissionGroups.first?["hooks"] as? [[String: Any]])
    #expect(permissionHooks.first?["timeout"] as? Int == 86_400)
}

@Test("Claude Hook 安装幂等：重复安装不叠加管理项")
func claudeHookInstallerIsIdempotent() throws {
    let command = "'/tmp/AgentPagerHooks' --source claude"
    let first = try ClaudeHookInstaller.install(existingData: nil, command: command)
    let second = try ClaudeHookInstaller.install(
        existingData: first.contents,
        command: command
    )
    let root = try #require(
        JSONSerialization.jsonObject(with: second.contents!) as? [String: Any]
    )
    let hooks = try #require(root["hooks"] as? [String: Any])
    let groups = try #require(hooks["SessionStart"] as? [[String: Any]])

    // 重复安装只保留一个管理项
    #expect(groups.count == 1)
    #expect(ClaudeHookInstaller.isInstalled(data: second.contents))
}

@Test("Claude Hook 卸载只删除 AgentPager 管理项")
func claudeHookUninstallOnlyRemovesManagedGroups() throws {
    let installed = try ClaudeHookInstaller.install(
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
        command: "'/tmp/AgentPagerHooks' --source claude"
    )

    let uninstalled = try ClaudeHookInstaller.uninstall(existingData: installed.contents)
    let uninstalledContents = try #require(uninstalled.contents)
    let root = try #require(
        JSONSerialization.jsonObject(with: uninstalledContents) as? [String: Any]
    )
    let hooks = try #require(root["hooks"] as? [String: Any])
    let stopGroups = try #require(hooks["Stop"] as? [[String: Any]])
    #expect(stopGroups.count == 1)
    #expect(!ClaudeHookInstaller.isInstalled(data: uninstalledContents))
}

@Test("Claude hookCommand 带上 --source claude")
func claudeHookCommandIncludesSource() {
    let command = ClaudeHookInstaller.hookCommand(for: "/tmp/AgentPagerHooks")
    #expect(command.contains("--source claude"))
    #expect(command.hasPrefix("'/tmp/AgentPagerHooks'"))
}

@Test("Claude 权限响应格式符合 hookSpecificOutput 规范")
func claudePermissionOutputShape() throws {
    let data = try ClaudeHookOutput.permission(.allow)
    let object = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    let hookSpecificOutput = try #require(object["hookSpecificOutput"] as? [String: Any])
    let decision = try #require(hookSpecificOutput["decision"] as? [String: Any])

    #expect(object["continue"] as? Bool == true)
    #expect(hookSpecificOutput["hookEventName"] as? String == "PermissionRequest")
    #expect(decision["behavior"] as? String == "allow")
}
