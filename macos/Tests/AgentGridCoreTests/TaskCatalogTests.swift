import Foundation
import Testing
@testable import AgentGridCore

@Test("Hook 审批在同一投影中提交任务和待处理请求")
func hookApprovalCommitsConsistentProjection() {
    let now = Date(timeIntervalSince1970: 1_000)
    let hook = CodexHookPayload(
        cwd: "/tmp/AgentGrid",
        hookEventName: .permissionRequest,
        sessionID: "session-1",
        toolName: "exec_command"
    )
    var catalog = TaskCatalog()

    let changed = catalog.accept(.hook(hook, receivedAt: now))
    let projection = catalog.projection()

    #expect(changed)
    #expect(projection.revision == 1)
    #expect(projection.tasks.count == 1)
    #expect(projection.tasks[0].lifecycle == .waitingApproval)
    #expect(projection.tasks[0].capabilities == [.approve, .deny])
    #expect(projection.pendingRequests == [
        PendingRequest(
            taskID: "session-1",
            kind: .approval,
            summary: nil
        ),
    ])
}

@Test("批准控制先解析 Hook 再原子提交运行态")
func approvalControlResolvesBeforeCommit() {
    let now = Date(timeIntervalSince1970: 2_000)
    let hook = CodexHookPayload(
        cwd: "/tmp/AgentGrid",
        hookEventName: .permissionRequest,
        sessionID: "session-1",
        toolName: "exec_command"
    )
    let resolver = RecordingPermissionResolver()
    var catalog = TaskCatalog()
    catalog.accept(.hook(hook, receivedAt: now))

    let receipt = catalog.perform(
        AuthorizedTaskControl(
            requestID: UUID(),
            taskID: "session-1",
            action: .approve
        ),
        permissionResolver: resolver,
        now: now.addingTimeInterval(1)
    )
    let projection = catalog.projection()

    #expect(receipt.result == .accepted)
    #expect(receipt.committedRevision == 2)
    #expect(resolver.decisions == [
        .init(sessionID: "session-1", decision: .allow),
    ])
    #expect(projection.tasks[0].lifecycle == .running)
    #expect(projection.tasks[0].capabilities.isEmpty)
    #expect(projection.pendingRequests.isEmpty)
}

@Test("Hook 解析失败时控制不会提前修改 Task")
func failedPermissionResolutionKeepsState() {
    let hook = CodexHookPayload(
        cwd: "/tmp/AgentGrid",
        hookEventName: .permissionRequest,
        sessionID: "session-1",
        toolName: "exec_command"
    )
    let resolver = RecordingPermissionResolver(shouldFail: true)
    var catalog = TaskCatalog()
    catalog.accept(.hook(hook))
    let before = catalog.projection()

    let receipt = catalog.perform(
        AuthorizedTaskControl(
            requestID: UUID(),
            taskID: "session-1",
            action: .deny
        ),
        permissionResolver: resolver
    )

    #expect(receipt.result == .rejected)
    #expect(catalog.projection() == before)
}

@Test("旧 rollout 不会把终态 Task 重新打开")
func staleRolloutDoesNotReopenTerminalTask() {
    let completedAt = Date.now
    let task = TaskSnapshot(
        id: "session-1",
        source: .codexCLI,
        projectName: "AgentGrid",
        lifecycle: .succeeded,
        updatedAt: completedAt,
        completedAt: completedAt,
        isUnread: true
    )
    let staleSignal = CodexRolloutSignal(
        sessionID: "session-1",
        cwd: "/tmp/AgentGrid",
        lifecycle: .running,
        activity: .thinking,
        userPrompt: "可以补充的旧消息",
        timestamp: completedAt.addingTimeInterval(-10)
    )
    var catalog = TaskCatalog(restoring: [task])

    catalog.accept(.rollout([staleSignal]))
    let updated = catalog.projection().tasks[0]

    #expect(updated.lifecycle == .succeeded)
    #expect(updated.completedAt == completedAt)
    #expect(updated.userPrompt == "可以补充的旧消息")
}

@Test("Bridge 重启对账后会中断没有活动证据的旧状态")
func restoredActiveTaskStartsInterruptedUntilFreshEvidenceArrives() throws {
    for lifecycle in [
        AgentLifecycle.starting,
        .running,
        .waitingApproval,
        .waitingAnswer,
    ] {
        let task = TaskSnapshot(
            id: "session-stale-\(lifecycle.rawValue)",
            source: .codexCLI,
            projectName: "AgentGrid",
            lifecycle: lifecycle,
            activity: .thinking,
            startedAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )

        var catalog = TaskCatalog(restoring: [task])
        catalog.reconcileRestoredActiveTasks(
            verifiedActiveTaskIDs: [],
            now: Date(timeIntervalSince1970: 3_000)
        )
        let restored = try #require(catalog.projection().tasks.first)

        #expect(restored.lifecycle == .interrupted)
        #expect(restored.activity == nil)
        #expect(restored.completedAt != nil)
    }
}

@Test("新一轮用户输入会把已完成 Task 重新打开")
func freshUserMessageReopensTerminalTask() throws {
    let completedAt = Date.now
    let task = TaskSnapshot(
        id: "session-1",
        source: .codexDesktop,
        projectName: "AgentGrid",
        lifecycle: .succeeded,
        updatedAt: completedAt,
        completedAt: completedAt,
        isUnread: true
    )
    let line = try JSONSerialization.data(withJSONObject: [
        "type": "event_msg",
        "payload": [
            "type": "user_message",
            "message": "继续处理这个任务",
        ],
    ])
    let signal = try #require(CodexRolloutReader.signal(
        from: line,
        sessionID: "session-1",
        cwd: "/tmp/AgentGrid",
        now: completedAt.addingTimeInterval(1)
    ))
    var catalog = TaskCatalog(restoring: [task])

    catalog.accept(.rollout([signal]))
    let updated = try #require(catalog.projection().tasks.first)

    #expect(updated.lifecycle == .running)
    #expect(updated.completedAt == nil)
    #expect(updated.userPrompt == "继续处理这个任务")
}

@Test("子代理变化与父 Task 活动在同一 Revision 中提交")
func subagentAndParentActivityCommitTogether() {
    let now = Date(timeIntervalSince1970: 5_000)
    let signal = CodexRolloutSignal(
        sessionID: "parent",
        cwd: "/tmp/AgentGrid",
        lifecycle: .running,
        activity: .editing,
        latestStep: "修改 TaskCatalog",
        subagentID: "child",
        subagentPath: "/root/catalog_tests",
        timestamp: now
    )
    var catalog = TaskCatalog()

    catalog.accept(.rollout([signal]))
    let task = catalog.projection().tasks[0]

    #expect(task.activity == .delegating)
    #expect(task.subagents.count == 1)
    #expect(task.subagents[0].id == "child")
    #expect(task.subagents[0].latestStep == "修改 TaskCatalog")
}

private final class RecordingPermissionResolver:
    CodexPermissionResolving,
    @unchecked Sendable
{
    struct Decision: Equatable {
        var sessionID: String
        var decision: CodexPermissionDecision
    }

    private(set) var decisions: [Decision] = []
    private let shouldFail: Bool

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    func resolve(
        sessionID: String,
        decision: CodexPermissionDecision
    ) throws {
        decisions.append(.init(sessionID: sessionID, decision: decision))
        if shouldFail {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

@Test("omp 适配层失联超时为 offline，恢复保留身份且不产生完成")
func paseoLeaseExpiresWithoutCompletion() throws {
    let now = Date(timeIntervalSince1970: 1000)
    let data = Data(#"{"hostID":"lease-host","agentID":"main","provider":"omp","projectName":"Project","titleCategory":"","status":"running","archived":false,"connectionID":"first","revision":1}"#.utf8)
    let discovery = try JSONDecoder().decode(PaseoDiscovery.self, from: data)
    var catalog = TaskCatalog()
    catalog.accept(.paseoDiscovery(discovery, receivedAt: now))
    catalog.maintain(now: now.addingTimeInterval(46))
    let offline = try #require(catalog.projection().tasks.first)
    #expect(offline.lifecycle == .offline)
    #expect(offline.completedAt == nil)
    #expect(!offline.isUnread)
    let recovery = Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"revision\":1", with: "\"revision\":2").utf8)
    catalog.accept(.paseoDiscovery(try JSONDecoder().decode(PaseoDiscovery.self, from: recovery), receivedAt: now.addingTimeInterval(47)))
    let restored = try #require(catalog.projection().tasks.first)
    #expect(restored.id == offline.id)
    #expect(restored.startedAt == offline.startedAt)
    #expect(restored.lifecycle == .running)
    #expect(restored.completedAt == nil)
}

@Test("omp 旧归档不能删除更新状态，重复恢复快照不延长完成")
func paseoRecoveryEnvelopeOrdering() throws {
    func input(_ status: String, revision: Int, archived: Bool = false, baseline: Bool = false, connection: String = "first", epoch: Double = 1000) throws -> PaseoDiscovery {
        let data = try JSONSerialization.data(withJSONObject: [
            "hostID": "ordering", "agentID": "main", "provider": "omp", "projectName": "Project",
            "titleCategory": "", "status": status, "archived": archived,
            "connectionID": connection, "connectionStartedAt": epoch, "revision": revision, "baseline": baseline,
        ])
        return try JSONDecoder().decode(PaseoDiscovery.self, from: data)
    }
    let now = Date.now
    var catalog = TaskCatalog()
    catalog.accept(.paseoDiscovery(try input("running", revision: 2), receivedAt: now))
    catalog.accept(.paseoDiscovery(try input("idle", revision: 1, archived: true), receivedAt: now))
    #expect(catalog.projection().tasks.count == 1)
    catalog.accept(.paseoDiscovery(try input("succeeded", revision: 3), receivedAt: now))
    let finished = catalog.projection().tasks.first
    catalog.accept(.paseoDiscovery(try input("idle", revision: 4, baseline: true), receivedAt: now.addingTimeInterval(15)))
    #expect(catalog.projection().tasks.first?.completedAt == finished?.completedAt)
    #expect(catalog.projection().tasks.first?.lifecycle == .succeeded)
    catalog.accept(.paseoDiscovery(try input("running", revision: 1, connection: "restarted", epoch: 2000), receivedAt: now.addingTimeInterval(16)))
    catalog.accept(.paseoDiscovery(try input("succeeded", revision: 99), receivedAt: now.addingTimeInterval(17)))
    #expect(catalog.projection().tasks.first?.lifecycle == .running)
}

@Test("无配置主机授权的完整目录不能删除归属未知的恢复卡片")
func paseoMembershipPreservesUnownedRestoredTasks() throws {
    let task = TaskSnapshot(id: "paseo:omp:unowned", source: .omp, projectName: "Other", lifecycle: .idle)
    var catalog = TaskCatalog(restoring: [task])
    let data = Data(#"{"hostID":"host-a","agentID":"","provider":"omp","projectName":"","titleCategory":"","status":"snapshot","archived":false,"connectionID":"current","revision":1,"snapshotID":"empty","snapshotPart":0,"snapshotParts":1,"members":[]}"#.utf8)
    catalog.accept(.paseoDiscovery(try JSONDecoder().decode(PaseoDiscovery.self, from: data)))
    #expect(catalog.projection().tasks == [task])
    let next = Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"revision\":1", with: "\"revision\":2").utf8)
    catalog.accept(.paseoDiscovery(try JSONDecoder().decode(PaseoDiscovery.self, from: next), authoritativeHostID: "host-a"))
    #expect(catalog.projection().tasks.isEmpty)
}
