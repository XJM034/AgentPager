import Foundation
import Testing
@testable import AgentGridCore

@Test("Rollout Observation 隐藏会话发现与重试节奏")
func rolloutObservationOwnsDiscoveryCadence() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let now = Date.now
    var observation = CodexRolloutObservation(
        sessionsRoot: root,
        lookback: 60,
        discoveryInterval: 3
    )

    #expect(observation.observe(now: now).isEmpty)

    let rollout = root.appendingPathComponent("rollout-session-live.jsonl")
    let contents = """
    {"type":"session_meta","payload":{"id":"session-live","cwd":"/tmp/AgentGrid"}}
    {"type":"event_msg","payload":{"type":"user_message","message":"深化采集 module"}}

    """
    try Data(contents.utf8).write(to: rollout)

    #expect(
        observation.observe(now: now.addingTimeInterval(2)).isEmpty
    )
    let signals = observation.observe(now: now.addingTimeInterval(3))

    #expect(signals.last?.sessionID == "session-live")
    #expect(signals.last?.userPrompt == "深化采集 module")
}

@Test("Hook 只提供追踪提示而不要求调用者操作 Reader")
func hookAddsRolloutHint() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let rollout = root.appendingPathComponent("rollout-hook.jsonl")
    try Data().write(to: rollout)
    let hook = CodexHookPayload(
        cwd: "/tmp/AgentGrid",
        hookEventName: .sessionStart,
        sessionID: "session-hook",
        transcriptPath: rollout.path
    )
    var observation = CodexRolloutObservation(
        sessionsRoot: root.appendingPathComponent("unused", isDirectory: true),
        lookback: 60,
        discoveryInterval: 3
    )
    observation.include(hook)

    let handle = try FileHandle(forWritingTo: rollout)
    try handle.write(
        contentsOf: Data(
            """
            {"type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\\"cmd\\":\\"swift test\\"}"}}

            """.utf8
        )
    )
    try handle.close()

    let signals = observation.observe()

    #expect(signals.last?.sessionID == "session-hook")
    #expect(signals.last?.latestStep == "swift test")
}

@Test("运行中的 rollout 消失后会收敛为中断")
func missingRunningRolloutBecomesInterruptedAfterGracePeriod() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let now = Date(timeIntervalSince1970: 10_000)
    let rollout = root.appendingPathComponent("rollout-session-archived.jsonl")
    let contents = """
    {"type":"session_meta","payload":{"id":"session-archived","cwd":"/tmp/AgentGrid"}}
    {"type":"event_msg","payload":{"type":"task_started"}}
    {"type":"event_msg","payload":{"type":"task_complete"}}
    {"type":"event_msg","payload":{"type":"task_started"}}

    """
    try Data(contents.utf8).write(to: rollout)

    var observation = CodexRolloutObservation(
        sessionsRoot: root,
        lookback: 60,
        discoveryInterval: 3
    )
    #expect(observation.observe(now: now).last?.lifecycle == .running)

    try FileManager.default.removeItem(at: rollout)

    #expect(observation.observe(now: now).isEmpty)
    #expect(observation.observe(now: now.addingTimeInterval(2)).isEmpty)
    #expect(
        observation.observe(now: now.addingTimeInterval(5)).last?.lifecycle
            == .interrupted
    )
}

@Test("Hook 已启动但 rollout 未写入事件时消失也会收敛")
func missingHookTrackedRolloutBecomesInterrupted() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let now = Date(timeIntervalSince1970: 20_000)
    let rollout = root.appendingPathComponent("rollout-hook-disappeared.jsonl")
    try Data().write(to: rollout)
    let hook = CodexHookPayload(
        cwd: "/tmp/AgentGrid",
        hookEventName: .sessionStart,
        sessionID: "session-hook-disappeared",
        transcriptPath: rollout.path
    )
    var observation = CodexRolloutObservation(
        sessionsRoot: root.appendingPathComponent("unused", isDirectory: true),
        lookback: 60,
        discoveryInterval: 3
    )
    observation.include(hook)

    try FileManager.default.removeItem(at: rollout)

    #expect(observation.observe(now: now).isEmpty)
    #expect(
        observation.observe(now: now.addingTimeInterval(5)).last?.lifecycle
            == .interrupted
    )
}

@Test("已经完成的 rollout 消失后不会被降级为中断")
func missingCompletedRolloutKeepsTerminalResult() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let now = Date(timeIntervalSince1970: 30_000)
    let rollout = root.appendingPathComponent("rollout-session-completed.jsonl")
    let contents = """
    {"type":"session_meta","payload":{"id":"session-completed","cwd":"/tmp/AgentGrid"}}
    {"type":"event_msg","payload":{"type":"task_started"}}
    {"type":"event_msg","payload":{"type":"task_complete"}}

    """
    try Data(contents.utf8).write(to: rollout)

    var observation = CodexRolloutObservation(
        sessionsRoot: root,
        lookback: 60,
        discoveryInterval: 3
    )
    #expect(observation.observe(now: now).last?.lifecycle == .succeeded)

    try FileManager.default.removeItem(at: rollout)

    #expect(observation.observe(now: now).isEmpty)
    #expect(observation.observe(now: now.addingTimeInterval(5)).isEmpty)
}

@Test("同一 Session 仍有续接 rollout 时不会因旧文件消失而中断")
func continuationRolloutKeepsSessionRunningWhenOlderFileDisappears() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let now = Date(timeIntervalSince1970: 40_000)
    let oldRollout = root.appendingPathComponent("rollout-session-old.jsonl")
    let currentRollout = root.appendingPathComponent("rollout-session-current.jsonl")
    let oldContents = """
    {"type":"session_meta","payload":{"id":"session-continued","cwd":"/tmp/AgentGrid"}}
    {"timestamp":"1970-01-01T11:06:30.000Z","type":"event_msg","payload":{"type":"task_started"}}

    """
    let currentContents = """
    {"type":"session_meta","payload":{"id":"session-continued","cwd":"/tmp/AgentGrid"}}
    {"timestamp":"1970-01-01T11:06:31.000Z","type":"event_msg","payload":{"type":"task_started"}}

    """
    try Data(oldContents.utf8).write(to: oldRollout)
    try Data(currentContents.utf8).write(to: currentRollout)

    var observation = CodexRolloutObservation(
        sessionsRoot: root,
        lookback: 60,
        discoveryInterval: 3
    )
    #expect(observation.observe(now: now).contains { $0.lifecycle == .running })

    try FileManager.default.removeItem(at: oldRollout)

    #expect(observation.observe(now: now).isEmpty)
    #expect(observation.observe(now: now.addingTimeInterval(5)).isEmpty)
}

@Test("同一 Session 的新 rollout 消失时旧终态文件不能阻止收敛")
func completedOlderRolloutDoesNotKeepMissingCurrentRolloutRunning() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let now = Date(timeIntervalSince1970: 50_000)
    let oldRollout = root.appendingPathComponent("rollout-session-old-terminal.jsonl")
    let currentRollout = root.appendingPathComponent("rollout-session-current-running.jsonl")
    try Data("""
    {"type":"session_meta","payload":{"id":"session-continued","cwd":"/tmp/AgentGrid"}}
    {"timestamp":"1970-01-01T13:53:10.000Z","type":"event_msg","payload":{"type":"task_started"}}
    {"timestamp":"1970-01-01T13:53:11.000Z","type":"event_msg","payload":{"type":"task_complete"}}

    """.utf8).write(to: oldRollout)
    try Data("""
    {"type":"session_meta","payload":{"id":"session-continued","cwd":"/tmp/AgentGrid"}}
    {"timestamp":"1970-01-01T13:53:20.000Z","type":"event_msg","payload":{"type":"task_started"}}

    """.utf8).write(to: currentRollout)

    var observation = CodexRolloutObservation(
        sessionsRoot: root,
        lookback: 60,
        discoveryInterval: 3
    )
    #expect(observation.observe(now: now).last?.lifecycle == .running)

    try FileManager.default.removeItem(at: currentRollout)

    #expect(observation.observe(now: now).isEmpty)
    #expect(
        observation.observe(now: now.addingTimeInterval(5)).last?.lifecycle
            == .interrupted
    )
}

@Test("只含 Token 用量的续接文件不能阻止运行 Session 收敛")
func usageOnlyContinuationDoesNotKeepMissingSessionRunning() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let now = Date(timeIntervalSince1970: 55_000)
    let runningRollout = root.appendingPathComponent("rollout-session-running.jsonl")
    let usageRollout = root.appendingPathComponent("rollout-session-usage.jsonl")
    try Data("""
    {"type":"session_meta","payload":{"id":"session-usage-continuation","cwd":"/tmp/AgentGrid"}}
    {"timestamp":"1970-01-01T15:16:30.000Z","type":"event_msg","payload":{"type":"task_started"}}

    """.utf8).write(to: runningRollout)
    try Data("""
    {"type":"session_meta","payload":{"id":"session-usage-continuation","cwd":"/tmp/AgentGrid"}}
    {"timestamp":"1970-01-01T15:16:31.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":100}}}}

    """.utf8).write(to: usageRollout)

    var observation = CodexRolloutObservation(
        sessionsRoot: root,
        lookback: 60,
        discoveryInterval: 3
    )
    #expect(observation.observe(now: now).contains { $0.lifecycle == .running })

    try FileManager.default.removeItem(at: runningRollout)

    #expect(observation.observe(now: now).isEmpty)
    #expect(
        observation.observe(now: now.addingTimeInterval(5)).last?.lifecycle
            == .interrupted
    )
}

@Test("Bridge 重启时会核实超过常规回看窗口的等待 Session")
func startupReconciliationKeepsLongWaitingSessionActive() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let now = Date(timeIntervalSince1970: 60_000)
    let sessionID = "session-long-waiting"
    let sessionDirectory = root
        .appendingPathComponent("1970/01/01", isDirectory: true)
    try FileManager.default.createDirectory(
        at: sessionDirectory,
        withIntermediateDirectories: true
    )
    let rollout = sessionDirectory.appendingPathComponent(
        "rollout-" + sessionID + ".jsonl"
    )
    try Data("""
    {"type":"session_meta","payload":{"id":"session-long-waiting","cwd":"/tmp/AgentGrid"}}
    {"timestamp":"1970-01-01T16:38:20.000Z","type":"event_msg","payload":{"type":"request_user_input","prompt":"请选择部署目标"}}

    """.utf8).write(to: rollout)
    try FileManager.default.setAttributes(
        [.modificationDate: now.addingTimeInterval(-60 * 60)],
        ofItemAtPath: rollout.path
    )

    let restoredTask = TaskSnapshot(
        id: sessionID,
        source: .codexDesktop,
        projectName: "AgentGrid",
        lifecycle: .waitingAnswer,
        activity: .thinking,
        startedAt: now.addingTimeInterval(-2 * 60 * 60),
        updatedAt: now.addingTimeInterval(-60 * 60)
    )
    var catalog = TaskCatalog(restoring: [restoredTask])
    var observation = CodexRolloutObservation(
        sessionsRoot: root,
        lookback: 10 * 60,
        discoveryInterval: 3
    )

    let reconciliation = observation.reconcile(
        sessionStartDates: [sessionID: restoredTask.startedAt],
        now: now
    )
    catalog.accept(.rollout(reconciliation.signals))
    catalog.reconcileRestoredActiveTasks(
        verifiedActiveTaskIDs: reconciliation.activeSessionIDs,
        now: now
    )

    let task = try #require(catalog.projection().tasks.first)
    #expect(reconciliation.activeSessionIDs == [sessionID])
    #expect(task.lifecycle == .waitingAnswer)
    #expect(task.completedAt == nil)
}

@Test("Bridge 重启核实时不会扫描远离 Session 启动日的目录")
func startupReconciliationSkipsUnrelatedDateDirectories() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let unrelatedDirectory = root
        .appendingPathComponent("1970/01/10", isDirectory: true)
    try FileManager.default.createDirectory(
        at: unrelatedDirectory,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: root) }

    let sessionID = "session-outside-start-date"
    let rollout = unrelatedDirectory.appendingPathComponent(
        "rollout-" + sessionID + ".jsonl"
    )
    try Data("""
    {"type":"session_meta","payload":{"id":"session-outside-start-date","cwd":"/tmp/AgentGrid"}}
    {"type":"event_msg","payload":{"type":"task_started"}}

    """.utf8).write(to: rollout)

    var observation = CodexRolloutObservation(
        sessionsRoot: root,
        lookback: 10 * 60,
        discoveryInterval: 3
    )
    let reconciliation = observation.reconcile(
        sessionStartDates: [
            sessionID: Date(timeIntervalSince1970: 12 * 60 * 60),
        ],
        now: Date(timeIntervalSince1970: 60_000)
    )

    #expect(reconciliation.activeSessionIDs.isEmpty)
    #expect(reconciliation.signals.isEmpty)
}
