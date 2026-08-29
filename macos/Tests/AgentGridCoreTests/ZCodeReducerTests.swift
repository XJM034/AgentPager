import Foundation
import Testing
@testable import AgentGridCore

@Test("ZCode 核心事件归约为启动、运行、工具活动与非终态空闲")
func zcodeCoreEventsReduceToConservativeLifecycle() {
    let startedAt = Date(timeIntervalSince1970: 1_000)
    var task = ZCodeEventReducer.task(
        from: ZCodeHookPayload(
            sessionID: "zcode-session-1",
            hookEventName: "SessionStart",
            cwd: "/private/work/AgentPager"
        ),
        existing: nil,
        now: startedAt
    )
    #expect(task.source == .zcode)
    #expect(task.projectName == "AgentPager")
    #expect(task.lifecycle == .starting)
    #expect(task.activity == .thinking)

    task = ZCodeEventReducer.task(
        from: ZCodeHookPayload(
            sessionID: "zcode-session-1",
            hookEventName: "UserPromptSubmit",
            cwd: "/private/work/AgentPager",
            prompt: "请修复 /Users/example/SecretProject/App.swift，token=sk-private-value"
        ),
        existing: task,
        now: startedAt.addingTimeInterval(1)
    )
    #expect(task.lifecycle == .running)
    #expect(task.activity == .thinking)
    #expect(task.userPrompt == nil)
    #expect(task.title.hasPrefix("AgentPager · "))
    #expect(!task.title.contains("/Users/example"))
    #expect(!task.title.contains("sk-private-value"))

    task = ZCodeEventReducer.task(
        from: ZCodeHookPayload(
            sessionID: "zcode-session-1",
            hookEventName: "PreToolUse",
            cwd: "/private/work/AgentPager",
            toolName: "Bash",
            toolInput: .object([
                "command": .string("cat /Users/example/SecretProject/App.swift"),
            ]),
            toolUseID: "tool-1"
        ),
        existing: task,
        now: startedAt.addingTimeInterval(2)
    )
    #expect(task.lifecycle == .running)
    #expect(task.activity == .executing)
    #expect(task.latestStep == "执行工具")

    task = ZCodeEventReducer.task(
        from: ZCodeHookPayload(
            sessionID: "zcode-session-1",
            hookEventName: "PostToolUse",
            cwd: "/private/work/AgentPager",
            toolName: "Bash",
            toolUseID: "tool-1"
        ),
        existing: task,
        now: startedAt.addingTimeInterval(3)
    )
    #expect(task.lifecycle == .running)
    #expect(task.activity == .thinking)

    let stoppedAt = startedAt.addingTimeInterval(4)
    task = ZCodeEventReducer.task(
        from: ZCodeHookPayload(
            sessionID: "zcode-session-1",
            hookEventName: "Stop",
            cwd: "/private/work/AgentPager"
        ),
        existing: task,
        now: stoppedAt
    )
    #expect(task.lifecycle == .idle)
    #expect(task.activity == nil)
    #expect(task.completedAt == nil)
    #expect(task.isUnread == false)
    #expect(!task.isTerminal)

    let firstTitle = task.title
    task = ZCodeEventReducer.task(
        from: ZCodeHookPayload(
            sessionID: "zcode-session-1",
            hookEventName: "UserPromptSubmit",
            cwd: "/private/work/AgentPager",
            prompt: "开始下一轮，但保留首轮稳定标题"
        ),
        existing: task,
        now: stoppedAt.addingTimeInterval(1)
    )
    #expect(task.lifecycle == .running)
    #expect(task.activity == .thinking)
    #expect(task.title == firstTitle)
}

@Test("ZCode PermissionRequest 只投影等待批准和脱敏摘要")
func zcodePermissionRequestWaitsWithoutPhoneDecisionCapability() throws {
    var catalog = TaskCatalog()
    _ = catalog.accept(.zcodeHook(ZCodeHookPayload(
        sessionID: "zcode-session-1",
        hookEventName: "UserPromptSubmit",
        cwd: "/private/work/AgentPager",
        prompt: "safe synthetic prompt"
    )))
    _ = catalog.accept(.zcodeHook(ZCodeHookPayload(
        sessionID: "zcode-session-1",
        hookEventName: "PermissionRequest",
        cwd: "/private/work/AgentPager",
        toolName: "Bash",
        toolInput: .object([
            "command": .string("printenv SECRET && cat /Users/example/private.txt"),
        ]),
        toolUseID: "tool-1",
        requestID: "request-1"
    )))

    let projection = catalog.projection()
    let task = try #require(projection.tasks.single)
    let request = try #require(projection.pendingRequests.single)

    #expect(task.lifecycle == .waitingApproval)
    #expect(task.activity == .executing)
    #expect(task.latestStep == "执行工具 · 等待本地批准")
    #expect(task.completedAt == nil)
    #expect(task.capabilities.isEmpty)
    #expect(request.kind == .approval)
    #expect(
        request.requestID ==
            "zcode:dba8317bdc0b859fdf59bc62bbe9631112fec8b939e2b5630f454f2c12db9b52"
    )
    #expect(request.summary == "执行工具 · 等待本地批准")
    #expect(!request.summary.orEmpty.contains("printenv"))
    #expect(!request.summary.orEmpty.contains("/Users/example"))
}

@Test("ZCode 同一 Session 并发请求按 tool_use_id 独立批准和拒绝")
func zcodeConcurrentPermissionRequestsResolveOnlySelectedRequest() throws {
    let firstHook = ZCodeHookPayload(
        sessionID: "zcode-session-1",
        hookEventName: "PermissionRequest",
        cwd: "/private/work/AgentPager",
        toolName: "Read",
        toolUseID: "tool-1"
    )
    let secondHook = ZCodeHookPayload(
        sessionID: "zcode-session-1",
        hookEventName: "PermissionRequest",
        cwd: "/private/work/AgentPager",
        toolName: "Bash",
        toolUseID: "tool-2"
    )
    let firstID = try #require(ZCodeEventReducer.safeRequestID(from: firstHook))
    let secondID = try #require(ZCodeEventReducer.safeRequestID(from: secondHook))
    let resolver = RecordingZCodePermissionResolver()
    var catalog = TaskCatalog()

    catalog.accept(.zcodeHook(firstHook, permissionState: .pending))
    catalog.accept(.zcodeHook(secondHook, permissionState: .pending))

    #expect(Set(catalog.projection().pendingRequests.compactMap(\.requestID)) == [firstID, secondID])
    #expect(
        Set(catalog.projection().pendingRequests.compactMap(\.summary)) == [
            "读取文件 · 等待手机批准",
            "执行工具 · 等待手机批准",
        ]
    )
    #expect(catalog.projection().tasks.single?.capabilities == [.approve, .deny])

    let approved = catalog.perform(
        AuthorizedTaskControl(
            requestID: UUID(),
            taskID: "zcode-session-1",
            action: .approve,
            pendingRequestID: firstID
        ),
        permissionResolver: resolver
    )

    #expect(approved.result == .accepted)
    #expect(catalog.projection().pendingRequests.map(\.requestID) == [secondID])
    #expect(catalog.projection().tasks.single?.lifecycle == .waitingApproval)

    let denied = catalog.perform(
        AuthorizedTaskControl(
            requestID: UUID(),
            taskID: "zcode-session-1",
            action: .deny,
            pendingRequestID: secondID
        ),
        permissionResolver: resolver
    )

    #expect(denied.result == .accepted)
    #expect(catalog.projection().pendingRequests.isEmpty)
    #expect(catalog.projection().tasks.single?.lifecycle == .running)
    #expect(resolver.decisions == [
        .init(requestID: firstID, decision: .allow),
        .init(requestID: secondID, decision: .deny),
    ])
}

@Test("ZCode 重复 未知 过期和已完成请求返回明确 stale 结果")
func zcodeInvalidPermissionAnswersAreExplicit() throws {
    let hook = ZCodeHookPayload(
        sessionID: "zcode-session-1",
        hookEventName: "PermissionRequest",
        cwd: "/private/work/AgentPager",
        toolName: "Read",
        toolUseID: "tool-1"
    )
    let requestID = try #require(ZCodeEventReducer.safeRequestID(from: hook))
    let resolver = RecordingZCodePermissionResolver()
    var catalog = TaskCatalog()
    catalog.accept(.zcodeHook(hook, permissionState: .pending))

    let first = catalog.perform(
        AuthorizedTaskControl(
            requestID: UUID(),
            taskID: hook.sessionID,
            action: .approve,
            pendingRequestID: requestID
        ),
        permissionResolver: resolver
    )
    resolver.states[requestID] = .approved

    let duplicate = catalog.perform(
        AuthorizedTaskControl(
            requestID: UUID(),
            taskID: hook.sessionID,
            action: .approve,
            pendingRequestID: requestID
        ),
        permissionResolver: resolver
    )
    let unknown = catalog.perform(
        AuthorizedTaskControl(
            requestID: UUID(),
            taskID: hook.sessionID,
            action: .deny,
            pendingRequestID: "zcode:unknown"
        ),
        permissionResolver: resolver
    )
    resolver.states["zcode:expired"] = .expired
    let expired = catalog.perform(
        AuthorizedTaskControl(
            requestID: UUID(),
            taskID: hook.sessionID,
            action: .approve,
            pendingRequestID: "zcode:expired"
        ),
        permissionResolver: resolver
    )
    resolver.states["zcode:cancelled"] = .cancelled
    let completed = catalog.perform(
        AuthorizedTaskControl(
            requestID: UUID(),
            taskID: hook.sessionID,
            action: .deny,
            pendingRequestID: "zcode:cancelled"
        ),
        permissionResolver: resolver
    )

    #expect(first.result == .accepted)
    #expect(duplicate.result == .stale)
    #expect(duplicate.reason?.contains("已批准") == true)
    #expect(unknown.result == .stale)
    #expect(unknown.reason?.contains("未知") == true)
    #expect(expired.result == .stale)
    #expect(expired.reason?.contains("过期") == true)
    #expect(completed.result == .stale)
    #expect(completed.reason?.contains("已取消") == true)
}

@Test("ZCode 超时或断线会及时清理 pending 并恢复非阻塞任务态")
func zcodeTerminalRelayStateCleansPendingCatalogEntry() throws {
    let hook = ZCodeHookPayload(
        sessionID: "zcode-session-1",
        hookEventName: "PermissionRequest",
        cwd: "/private/work/AgentPager",
        toolName: "Read",
        toolUseID: "tool-timeout"
    )
    let requestID = try #require(ZCodeEventReducer.safeRequestID(from: hook))
    var catalog = TaskCatalog()
    catalog.accept(.zcodeHook(hook, permissionState: .pending))

    let changed = catalog.completeZCodePermissionRequest(
        requestID,
        state: .expired,
        now: Date(timeIntervalSince1970: 2_000)
    )
    let projection = catalog.projection()

    #expect(changed)
    #expect(projection.pendingRequests.isEmpty)
    #expect(projection.tasks.single?.lifecycle == .running)
    #expect(projection.tasks.single?.capabilities.isEmpty == true)
}

@Test("ZCode terminal 回调先到也不会留下随后到达的 pending")
func zcodeTerminalStateBeforeHookEventStillPreventsPendingEntry() throws {
    let hook = ZCodeHookPayload(
        sessionID: "zcode-session-1",
        hookEventName: "PermissionRequest",
        cwd: "/private/work/AgentPager",
        toolName: "Read",
        toolUseID: "tool-cancelled-before-event"
    )
    let requestID = try #require(ZCodeEventReducer.safeRequestID(from: hook))
    var catalog = TaskCatalog()

    let completedBeforeEvent = catalog.completeZCodePermissionRequest(
        requestID,
        state: .cancelled
    )
    #expect(!completedBeforeEvent)
    catalog.accept(.zcodeHook(hook, permissionState: .pending))

    #expect(catalog.projection().pendingRequests.isEmpty)
    #expect(catalog.projection().tasks.single?.lifecycle == .running)
    #expect(catalog.projection().tasks.single?.capabilities.isEmpty == true)
}

@Test("缺少 tool_use_id 的 ZCode 权限事件不能留下不可裁决 pending")
func zcodePermissionWithoutToolUseIDDoesNotCreatePendingEntry() {
    var catalog = TaskCatalog()

    catalog.accept(
        .zcodeHook(
            ZCodeHookPayload(
                sessionID: "zcode-session-1",
                hookEventName: "PermissionRequest",
                cwd: "/private/work/AgentPager",
                toolName: "Read",
                toolUseID: nil
            )
        )
    )

    #expect(catalog.projection().pendingRequests.isEmpty)
    #expect(catalog.projection().tasks.single?.lifecycle == .running)
    #expect(catalog.projection().tasks.single?.capabilities.isEmpty == true)
}

@Test("ZCode PostToolUseFailure 保持运行并只显示脱敏错误步骤")
func zcodeToolFailureRemainsRunningWithSafeStep() {
    let running = ZCodeEventReducer.task(
        from: ZCodeHookPayload(
            sessionID: "zcode-session-1",
            hookEventName: "UserPromptSubmit",
            cwd: "/private/work/AgentPager"
        ),
        existing: nil
    )
    let failed = ZCodeEventReducer.task(
        from: ZCodeHookPayload(
            sessionID: "zcode-session-1",
            hookEventName: "PostToolUseFailure",
            cwd: "/private/work/AgentPager",
            toolName: "Read",
            toolUseID: "tool-1",
            errorCategory: .permissionDenied
        ),
        existing: running
    )

    #expect(failed.lifecycle == .running)
    #expect(failed.activity == .reading)
    #expect(failed.latestStep == "读取失败 · 权限拒绝")
    #expect(failed.completedAt == nil)
    #expect(!failed.isUnread)
    #expect(failed.capabilities.isEmpty)
}

@Test("ZCode 诊断只包含事件、生命周期、工具与错误类别")
func zcodeDiagnosticExcludesRawUserContent() {
    let hook = ZCodeHookPayload(
        sessionID: "private-session",
        hookEventName: "PostToolUseFailure",
        cwd: "/Users/example/SecretProject",
        prompt: "private prompt",
        toolName: "Read",
        toolInput: .object([
            "file_path": .string("/Users/example/SecretProject/App.swift"),
        ]),
        toolUseID: "private-tool",
        errorCategory: .permissionDenied
    )
    let task = ZCodeEventReducer.task(from: hook, existing: nil)
    let diagnostic = ZCodeDiagnosticEvent(hook: hook, lifecycle: task.lifecycle)

    #expect(diagnostic.source == .zcode)
    #expect(diagnostic.eventCategory == "PostToolUseFailure")
    #expect(diagnostic.lifecycle == .running)
    #expect(diagnostic.toolCategory == .reading)
    #expect(diagnostic.outcome == .failure)
    #expect(diagnostic.errorCategory == .permissionDenied)
    #expect(!diagnostic.summary.contains("private"))
    #expect(!diagnostic.summary.contains("/Users/example"))
    #expect(!diagnostic.summary.contains("SecretProject"))
}

@Test("ZCode 核心工具复用现有活动语言且 Agent Task 只显示协作")
func zcodeToolsMapToExistingActivities() {
    let cases: [(String, AgentActivity, String)] = [
        ("Read", .reading, "读取文件"),
        ("Grep", .searching, "搜索内容"),
        ("Edit", .editing, "编辑文件"),
        ("Bash", .executing, "执行工具"),
        ("RunTests", .testing, "运行测试"),
        ("WebSearch", .browsing, "浏览内容"),
        ("Agent", .delegating, "协作任务"),
        ("Task", .delegating, "协作任务"),
        ("FutureUnknownTool", .executing, "执行工具"),
    ]

    for (toolName, expectedActivity, expectedStep) in cases {
        let activity = ZCodeEventReducer.activity(for: toolName)
        #expect(activity == expectedActivity)
        #expect(ZCodeEventReducer.safeStep(for: activity) == expectedStep)
    }
}

@Test("未知 ZCode 事件不能改变已有生命周期")
func unknownZCodeEventPreservesLifecycle() {
    let running = ZCodeEventReducer.task(
        from: ZCodeHookPayload(
            sessionID: "zcode-session-1",
            hookEventName: "UserPromptSubmit",
            cwd: "/private/work/AgentPager"
        ),
        existing: nil
    )
    let after = ZCodeEventReducer.task(
        from: ZCodeHookPayload(
            sessionID: "zcode-session-1",
            hookEventName: "FutureEvent",
            cwd: "/private/work/AgentPager"
        ),
        existing: running
    )

    #expect(after.lifecycle == .running)
    #expect(after.activity == .thinking)
}

@Test("ZCode 标题只映射固定安全类别且不复制 prompt 原文")
func zcodeTitleUsesFixedCategoryWithoutCopyingPrompt() {
    let title = ZCodeEventReducer.safeTitle(
        projectName: "AgentPager",
        prompt: "token=sk-synthetic-value 请修复 /Users/example/private/Secret.swift 后继续补充一段很长的说明文字"
    )

    #expect(title == "AgentPager · 变更请求")
    #expect(!title.contains("sk-synthetic-value"))
    #expect(!title.contains("/Users/example"))
}

@Test("ZCode 标题拒绝未标注格式的常见凭据")
func zcodeTitleExcludesUnlabelledCredentialFormats() {
    let cases = [
        "ghp_1234567890abcdefghijklmnopqrstuvwxyz",
        "eyJhbGciOiJIUzI1NiJ9.payload.signature",
        "AKIAIOSFODNN7EXAMPLE",
        "plain-unlabelled-secret-value",
    ]

    for secret in cases {
        let title = ZCodeEventReducer.safeTitle(
            projectName: "AgentPager",
            prompt: "请处理 \(secret)"
        )
        #expect(!title.contains(secret))
    }
}

private extension Optional where Wrapped == String {
    var orEmpty: String { self ?? "" }
}

private final class RecordingZCodePermissionResolver:
    CodexPermissionResolving,
    @unchecked Sendable
{
    struct Decision: Equatable {
        var requestID: String
        var decision: CodexPermissionDecision
    }

    var decisions: [Decision] = []
    var states: [String: ZCodePermissionRequestState] = [:]

    func resolve(
        sessionID _: String,
        decision _: CodexPermissionDecision
    ) throws {
        Issue.record("ZCode 裁决必须携带 pending request ID")
    }

    func resolve(
        sessionID _: String,
        pendingRequestID: String,
        decision: CodexPermissionDecision
    ) throws {
        if let state = states[pendingRequestID] {
            throw ZCodePermissionResolutionError.completed(state)
        }
        guard pendingRequestID != "zcode:unknown" else {
            throw ZCodePermissionResolutionError.unknownRequest
        }
        decisions.append(.init(requestID: pendingRequestID, decision: decision))
    }
}
