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

@Test("ZCode Hook 解码全部七类事件、可选字段与未知字段")
func zcodeHookDecodesAllOfficialEventsConservatively() throws {
    let samples: [(String, ZCodeHookEvent)] = [
        (#"{"session_id":"session-1","hook_event_name":"SessionStart","source":"startup","future":{"nested":true}}"#, .sessionStart),
        (#"{"sessionId":"session-1","hookEventName":"UserPromptSubmit","prompt":"synthetic prompt","futureField":42}"#, .userPromptSubmit),
        (#"{"session_id":"session-1","hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"/Users/example/private.txt"},"tool_use_id":"tool-1"}"#, .preToolUse),
        (#"{"sessionId":"session-1","hookEventName":"PermissionRequest","toolName":"Bash","toolInput":{"command":"printenv SECRET"},"toolCallId":"tool-2","requestId":"request-1","reason":"needs local approval"}"#, .permissionRequest),
        (#"{"session_id":"session-1","hook_event_name":"PostToolUse","tool_name":"Read","tool_response":{"content":"private source"},"tool_use_id":"tool-1"}"#, .postToolUse),
        (#"{"sessionId":"session-1","hookEventName":"PostToolUseFailure","toolName":"Read","toolUseId":"tool-3","error":"No such file or directory: /Users/example/private.txt","errorDetails":{"trace":"secret"}}"#, .postToolUseFailure),
        (#"{"session_id":"session-1","hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"private response"}"#, .stop),
    ]

    let payloads = try samples.map { source, expectedEvent in
        let payload = try JSONDecoder().decode(
            ZCodeHookPayload.self,
            from: Data(source.utf8)
        )
        #expect(payload.event == expectedEvent)
        #expect(payload.sessionID == "session-1")
        return payload
    }

    #expect(payloads[0].cwd.isEmpty)
    #expect(payloads[0].toolName == nil)
    #expect(payloads[3].toolUseID == "tool-2")
    #expect(payloads[3].requestID == "request-1")
    #expect(payloads[5].toolUseID == "tool-3")
    #expect(payloads[5].errorCategory == .notFound)
}

@Test("ZCode 项目名不会把用户主目录名发送到共享快照")
func zcodeProjectNameHidesBareUserHomeDirectory() {
    let payload = ZCodeHookPayload(
        sessionID: "session-1",
        hookEventName: "SessionStart",
        cwd: "/Users/example"
    )

    #expect(payload.projectName == "ZCode")
}
