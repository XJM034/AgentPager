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
