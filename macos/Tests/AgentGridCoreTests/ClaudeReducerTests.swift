import Foundation
import Testing
@testable import AgentGridCore

@Test("Claude UserPromptSubmit 设置运行态与用户提示")
func claudeUserPromptSubmitRuns() {
    let hook = ClaudeHookPayload(
        cwd: "/tmp/agentpager",
        hookEventName: "UserPromptSubmit",
        sessionID: "claude-1",
        prompt: "重构 Hook 桥接"
    )
    let task = ClaudeEventReducer.task(from: hook, existing: nil)
    #expect(task.source == .claudeCode)
    #expect(task.lifecycle == .running)
    #expect(task.userPrompt == "重构 Hook 桥接")
    #expect(task.title.contains("重构 Hook 桥接"))
}

@Test("Claude PermissionRequest 进入等待批准并授予批准/拒绝能力")
func claudePermissionRequestWaitsForApproval() {
    let hook = ClaudeHookPayload(
        cwd: "/tmp/agentpager",
        hookEventName: "PermissionRequest",
        sessionID: "claude-1",
        toolName: "Bash",
        toolInput: .object(["command": .string("rm -rf /tmp/x")])
    )
    let task = ClaudeEventReducer.task(from: hook, existing: nil)
    #expect(task.lifecycle == .waitingApproval)
    #expect(task.capabilities == [.approve, .deny])
    #expect(task.latestStep?.contains("rm -rf /tmp/x") == true)
}

@Test("Claude Stop 标记完成且未读")
func claudeStopSucceeds() {
    let running = ClaudeEventReducer.task(
        from: ClaudeHookPayload(
            cwd: "/tmp/agentpager",
            hookEventName: "UserPromptSubmit",
            sessionID: "claude-1"
        ),
        existing: nil
    )
    let stopped = ClaudeEventReducer.task(
        from: ClaudeHookPayload(
            cwd: "/tmp/agentpager",
            hookEventName: "Stop",
            sessionID: "claude-1"
        ),
        existing: running
    )
    #expect(stopped.lifecycle == .succeeded)
    #expect(stopped.isUnread == true)
    #expect(stopped.completedAt != nil)
}

@Test("TaskCatalog 接受 Claude 权限请求并登记 PendingRequest")
func taskCatalogAcceptsClaudePermissionRequest() {
    var catalog = TaskCatalog()
    let accepted = catalog.accept(.claudeHook(ClaudeHookPayload(
        cwd: "/tmp/agentpager",
        hookEventName: "PermissionRequest",
        sessionID: "claude-1",
        toolName: "Bash",
        toolInput: .object(["command": .string("echo hi")])
    )))
    #expect(accepted)
    let projection = catalog.projection()
    let task = try #require(projection.tasks.first { $0.id == "claude-1" })
    #expect(task.source == .claudeCode)
    #expect(task.lifecycle == .waitingApproval)
    #expect(projection.pendingRequests.count == 1)
    #expect(projection.pendingRequests.first?.kind == .approval)
}

@Test("TaskCatalog 在 Claude Stop 后清除待办权限")
func taskCatalogClearsClaudePendingRequestOnStop() {
    var catalog = TaskCatalog()
    _ = catalog.accept(.claudeHook(ClaudeHookPayload(
        cwd: "/tmp/agentpager",
        hookEventName: "PermissionRequest",
        sessionID: "claude-1"
    )))
    catalog.accept(.claudeHook(ClaudeHookPayload(
        cwd: "/tmp/agentpager",
        hookEventName: "Stop",
        sessionID: "claude-1"
    )))
    #expect(catalog.projection().pendingRequests.isEmpty)
}

@Test("未知 Claude 事件不改变生命周期，只刷新时间戳")
func claudeUnknownEventLeavesLifecycle() {
    let running = ClaudeEventReducer.task(
        from: ClaudeHookPayload(
            cwd: "/tmp/agentpager",
            hookEventName: "UserPromptSubmit",
            sessionID: "claude-1"
        ),
        existing: nil
    )
    let after = ClaudeEventReducer.task(
        from: ClaudeHookPayload(
            cwd: "/tmp/agentpager",
            hookEventName: "FutureEvent",
            sessionID: "claude-1"
        ),
        existing: running
    )
    #expect(after.lifecycle == .running)
}

@Test("Claude SubagentStart 建立子代理，SubagentStop 标记完成")
func claudeSubagentLifecycle() {
    var task = ClaudeEventReducer.task(
        from: ClaudeHookPayload(
            cwd: "/tmp/agentpager",
            hookEventName: "UserPromptSubmit",
            sessionID: "claude-1"
        ),
        existing: nil
    )
    task = ClaudeEventReducer.task(
        from: ClaudeHookPayload(
            cwd: "/tmp/agentpager",
            hookEventName: "SubagentStart",
            sessionID: "claude-1",
            agentID: "sub-1",
            agentType: "general-purpose",
            taskDescription: "调研 Hook 协议"
        ),
        existing: task
    )
    #expect(task.subagents.count == 1)
    #expect(task.subagents.first?.id == "sub-1")
    #expect(task.subagents.first?.lifecycle == .running)
    #expect(task.subagents.first?.latestStep == "调研 Hook 协议")
    #expect(task.activity == .delegating)

    task = ClaudeEventReducer.task(
        from: ClaudeHookPayload(
            cwd: "/tmp/agentpager",
            hookEventName: "SubagentStop",
            sessionID: "claude-1",
            agentID: "sub-1",
            agentType: "general-purpose"
        ),
        existing: task
    )
    #expect(task.subagents.first?.lifecycle == .succeeded)
    // 全部子代理终态后，父任务不再标记为 delegating。
    #expect(task.activity == .thinking)
}
