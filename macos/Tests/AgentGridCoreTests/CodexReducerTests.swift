import Foundation
import Testing
@testable import AgentGridCore

@Test("权限请求进入审批状态并声明批准拒绝能力")
func permissionHookBecomesApprovalTask() {
    let hook = CodexHookPayload(
        cwd: "/tmp/AgentGrid",
        hookEventName: .permissionRequest,
        sessionID: "session-1",
        toolName: "exec_command"
    )

    let task = CodexEventReducer.task(from: hook, existing: nil)

    #expect(task.lifecycle == .waitingApproval)
    #expect(task.activity == .executing)
    #expect(task.capabilities == [.approve, .deny])
}

@Test("工具名映射到活动类型")
func toolActivityMapping() {
    #expect(CodexEventReducer.activity(for: "apply_patch") == .editing)
    #expect(CodexEventReducer.activity(for: "web_search") == .browsing)
    #expect(CodexEventReducer.activity(for: "run_tests") == .testing)
    #expect(CodexEventReducer.activity(for: "spawn_agent") == .delegating)
}

@Test("工具步骤有内容时隐藏内部工具名")
func latestStepHidesInternalToolName() {
    #expect(
        CodexEventReducer.latestStep(
            toolName: "tools.exec_command",
            summary: "swift test"
        ) == "swift test"
    )
    #expect(
        CodexEventReducer.latestStep(
            toolName: "tools.exec_command",
            summary: nil
        ) == nil
    )
    #expect(
        CodexEventReducer.latestStep(
            toolName: "search_graph",
            summary: "AgentGridScreen"
        ) == "search_graph AgentGridScreen"
    )
}

@Test("命令 Hook 只展示 cmd 参数")
func commandHookDisplaysCmdArgumentOnly() throws {
    let payload = """
    {
      "cwd": "/tmp/AgentGrid",
      "hook_event_name": "PreToolUse",
      "session_id": "session-1",
      "tool_name": "tools.exec_command",
      "tool_input": {
        "cmd": "swift test"
      }
    }
    """
    let hook = try JSONDecoder().decode(
        CodexHookPayload.self,
        from: Data(payload.utf8)
    )

    let task = CodexEventReducer.task(from: hook, existing: nil)

    #expect(task.latestStep == "swift test")
}

@Test("连续输入时展示最新消息并保持原任务名")
func latestUserPromptReplacesPreviousPrompt() {
    let firstHook = CodexHookPayload(
        cwd: "/tmp/AgentGrid",
        hookEventName: .userPromptSubmit,
        sessionID: "session-1",
        prompt: "第一条消息"
    )
    let firstTask = CodexEventReducer.task(from: firstHook, existing: nil)
    let originalTitle = firstTask.title
    let latestHook = CodexHookPayload(
        cwd: "/tmp/AgentGrid",
        hookEventName: .userPromptSubmit,
        sessionID: "session-1",
        prompt: "最新输入的消息"
    )

    let latestTask = CodexEventReducer.task(
        from: latestHook,
        existing: firstTask
    )

    #expect(latestTask.userPrompt == "最新输入的消息")
    #expect(latestTask.title == originalTitle)
}

@Test("中断后的 Stop 不会误报成功")
func stopPreservesInterruptedState() {
    let existing = TaskSnapshot(
        id: "session-1",
        source: .codexCLI,
        projectName: "AgentGrid",
        lifecycle: .interrupted
    )
    let hook = CodexHookPayload(
        cwd: "/tmp/AgentGrid",
        hookEventName: .stop,
        sessionID: "session-1"
    )

    let task = CodexEventReducer.task(from: hook, existing: existing)

    #expect(task.lifecycle == .interrupted)
    #expect(task.isUnread)
}
