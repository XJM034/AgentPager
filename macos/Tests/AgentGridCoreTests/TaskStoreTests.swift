import Foundation
import Testing
@testable import AgentGridCore

@Test("审批任务优先于固定的运行任务")
func approvalOverridesPinnedRunningTask() {
    let now = Date(timeIntervalSince1970: 1_000)
    let running = TaskSnapshot(
        id: "running",
        source: .codexCLI,
        projectName: "运行任务",
        lifecycle: .running,
        updatedAt: now,
        isPinned: true
    )
    let approval = TaskSnapshot(
        id: "approval",
        source: .codexDesktop,
        projectName: "审批任务",
        lifecycle: .waitingApproval,
        updatedAt: now.addingTimeInterval(-10)
    )

    let store = TaskStore(tasks: [running, approval])
    #expect(store.focusedTask()?.id == "approval")
}

@Test("活动任务不超时，完成任务按 TTL 删除")
func purgeOnlyExpiredTerminalTasks() {
    let now = Date(timeIntervalSince1970: 10_000)
    let active = TaskSnapshot(
        id: "active",
        source: .codexCLI,
        projectName: "活动",
        lifecycle: .running,
        startedAt: now.addingTimeInterval(-10_000),
        updatedAt: now.addingTimeInterval(-10_000)
    )
    let expired = TaskSnapshot(
        id: "expired",
        source: .codexCLI,
        projectName: "过期",
        lifecycle: .succeeded,
        startedAt: now.addingTimeInterval(-10_000),
        updatedAt: now.addingTimeInterval(-8_000),
        completedAt: now.addingTimeInterval(-8_000)
    )
    var store = TaskStore(tasks: [active, expired], retention: 3_600)

    store.purge(now: now)

    #expect(store.tasks.map(\.id) == ["active"])
}

@Test("容量不足时优先清理最旧的终态任务")
func capacityPurgesOldestTerminalTask() {
    let now = Date(timeIntervalSince1970: 20_000)
    let tasks = (0..<4).map { index in
        TaskSnapshot(
            id: "done-\(index)",
            source: .codexCLI,
            projectName: "任务",
            lifecycle: .succeeded,
            startedAt: now,
            updatedAt: now.addingTimeInterval(Double(index)),
            completedAt: now.addingTimeInterval(Double(index))
        )
    }
    var store = TaskStore(tasks: tasks, retention: 86_400, capacity: 3)

    store.purge(now: now.addingTimeInterval(10))

    #expect(store.tasks.count == 3)
    #expect(!store.tasks.contains { $0.id == "done-0" })
}

@Test("子代理终态保留四秒后自动清除")
func terminalSubagentsAreRemovedAfterGracePeriod() {
    let now = Date(timeIntervalSince1970: 30_000)
    let running = SubagentSnapshot(
        id: "running-child",
        path: "/root/running_child",
        lifecycle: .running,
        startedAt: now.addingTimeInterval(-20),
        updatedAt: now
    )
    let recent = SubagentSnapshot(
        id: "recent-child",
        path: "/root/recent_child",
        lifecycle: .succeeded,
        startedAt: now.addingTimeInterval(-10),
        updatedAt: now.addingTimeInterval(-3.9)
    )
    let expired = SubagentSnapshot(
        id: "expired-child",
        path: "/root/expired_child",
        lifecycle: .interrupted,
        startedAt: now.addingTimeInterval(-10),
        updatedAt: now.addingTimeInterval(-4)
    )
    let task = TaskSnapshot(
        id: "parent",
        source: .codexCLI,
        projectName: "父任务",
        subagents: [running, recent, expired],
        lifecycle: .running,
        updatedAt: now
    )
    var store = TaskStore(tasks: [task])

    let changed = store.purgeTerminalSubagents(now: now, retention: 4)

    #expect(changed)
    #expect(store.tasks[0].subagents.map(\.id) == ["running-child", "recent-child"])
}
