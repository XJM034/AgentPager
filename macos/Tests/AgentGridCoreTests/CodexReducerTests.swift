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
