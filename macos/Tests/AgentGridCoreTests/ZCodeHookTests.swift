import Foundation
import Testing
@testable import AgentGridCore

@Test("ZCode Hook 同时解码 snake_case 与 camelCase 核心字段")
func zcodeHookDecodesObservedAliases() throws {
    let snakeCase = Data(
        """
        {
          "session_id": "zcode-session-1",
          "hook_event_name": "PreToolUse",
          "cwd": "/private/work/AgentPager",
          "tool_name": "Read",
          "tool_input": {"file_path": "/private/work/AgentPager/Secret.swift"},
          "tool_use_id": "tool-1"
        }
        """.utf8
    )
    let camelCase = Data(
        """
        {
          "sessionId": "zcode-session-1",
          "hookEventName": "PostToolUse",
          "cwd": "/private/work/AgentPager",
          "toolName": "Read",
          "toolInput": {"filePath": "/private/work/AgentPager/Secret.swift"},
          "tool_use_id": "tool-1"
        }
        """.utf8
    )

    let before = try JSONDecoder().decode(ZCodeHookPayload.self, from: snakeCase)
    let after = try JSONDecoder().decode(ZCodeHookPayload.self, from: camelCase)

    #expect(before.sessionID == "zcode-session-1")
    #expect(before.event == .preToolUse)
    #expect(before.toolName == "Read")
    #expect(before.toolUseID == "tool-1")
    #expect(after.sessionID == before.sessionID)
    #expect(after.event == .postToolUse)
    #expect(after.toolName == before.toolName)
    #expect(after.toolUseID == before.toolUseID)
}
