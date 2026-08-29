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

@Test("ZCode 权限输出精确匹配 Gate 0 JSON 且 fallback 为空")
func zcodePermissionOutputMatchesGateZeroExactly() throws {
    #expect(
        String(data: try ZCodeHookOutput.permission(.allow), encoding: .utf8) ==
            #"{"hookSpecificOutput":{"decision":{"behavior":"allow"},"hookEventName":"PermissionRequest"}}"# + "\n"
    )
    #expect(
        String(data: try ZCodeHookOutput.permission(.deny), encoding: .utf8) ==
            #"{"hookSpecificOutput":{"decision":{"behavior":"deny"},"hookEventName":"PermissionRequest"}}"# + "\n"
    )
    #expect(ZCodeHookOutput.fallback.isEmpty)
}

@Test("ZCode 手机裁决等待为 Hook 外层超时保留确定性余量")
func zcodePermissionTimingLeavesOuterSafetyMargin() {
    #expect(ZCodePermissionTiming.bridgeDecisionTimeoutMilliseconds == 45_000)
    #expect(ZCodePermissionTiming.clientResponseTimeoutMilliseconds == 50_000)
    #expect(ZCodePermissionTiming.hookOuterTimeoutMilliseconds == 60_000)
    #expect(
        ZCodePermissionTiming.bridgeDecisionTimeoutMilliseconds <
            ZCodePermissionTiming.clientResponseTimeoutMilliseconds
    )
    #expect(
        ZCodePermissionTiming.clientResponseTimeoutMilliseconds + 10_000 <=
            ZCodePermissionTiming.hookOuterTimeoutMilliseconds
    )
}

@Test("ZCode pending request ID 由来源 Session 与 tool_use_id 稳定形成且不泄露原值")
func zcodePendingRequestIDIsStableUniqueAndOpaque() throws {
    let first = try #require(
        ZCodePendingRequestID.make(sessionID: "session/private:1", toolUseID: "tool/private:1")
    )
    let same = try #require(
        ZCodePendingRequestID.make(sessionID: "session/private:1", toolUseID: "tool/private:1")
    )
    let secondTool = try #require(
        ZCodePendingRequestID.make(sessionID: "session/private:1", toolUseID: "tool/private:2")
    )
    let secondSession = try #require(
        ZCodePendingRequestID.make(sessionID: "session/private:2", toolUseID: "tool/private:1")
    )

    #expect(first == same)
    #expect(first != secondTool)
    #expect(first != secondSession)
    #expect(first.hasPrefix("zcode:"))
    #expect(!first.contains("session/private"))
    #expect(!first.contains("tool/private"))
    #expect(ZCodePendingRequestID.make(sessionID: "", toolUseID: "tool-1") == nil)
    #expect(ZCodePendingRequestID.make(sessionID: "session-1", toolUseID: nil) == nil)
}

@Test("ZCode terminal lifecycle 历史有界且淘汰后仍明确为 unknown")
func zcodePermissionRegistryBoundsTerminalHistory() throws {
    var registry = ZCodePermissionRegistry(terminalHistoryLimit: 2)

    #expect(registry.register("zcode:first", channelAvailable: true) == .registered)
    #expect(try registry.resolve("zcode:first", decision: .allow) == .approved)
    #expect(registry.register("zcode:second", channelAvailable: true) == .registered)
    #expect(try registry.resolve("zcode:second", decision: .deny) == .denied)
    #expect(registry.register("zcode:third", channelAvailable: true) == .registered)
    let expired = registry.expire("zcode:third")
    #expect(expired)

    #expect(registry.state(for: "zcode:first") == nil)
    #expect(registry.state(for: "zcode:second") == .denied)
    #expect(registry.state(for: "zcode:third") == .expired)
    #expect(throws: ZCodePermissionResolutionError.unknownRequest) {
        try registry.resolve("zcode:first", decision: .allow)
    }
}
