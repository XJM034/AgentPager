import Foundation
import Testing
@testable import AgentGridCore

@Test("控制消息签名可验证")
func controlSignatureRoundTrip() throws {
    let secret = Data(repeating: 0x42, count: 32)
    var envelope = SignedControlEnvelope(
        messageId: UUID(uuidString: "6f539e96-6bce-4fdc-94d5-3cf4ea755622")!,
        sentAt: 1_785_067_200_000,
        deviceId: "nova4",
        sequence: 7,
        nonce: "nonce-7",
        payload: ControlPayload(taskID: "task-1", action: .approve)
    )
    envelope.signature = try ControlSigner.sign(envelope, secret: secret)

    #expect(try ControlSigner.verify(envelope, secret: secret))
}

@Test("控制消息修改后签名失效")
func tamperedControlIsRejected() throws {
    let secret = Data(repeating: 0x24, count: 32)
    var envelope = SignedControlEnvelope(
        sentAt: 1_785_067_200_000,
        deviceId: "nova4",
        sequence: 1,
        nonce: "nonce-1",
        payload: ControlPayload(taskID: "task-1", action: .approve)
    )
    envelope.signature = try ControlSigner.sign(envelope, secret: secret)
    envelope.payload.action = .deny

    #expect(try !ControlSigner.verify(envelope, secret: secret))
}

@Test("重放保护拒绝相同序号和 nonce")
func replayGuardRejectsReplay() throws {
    let now = Date(timeIntervalSince1970: 1_785_067_200)
    let secret = Data(repeating: 0x11, count: 32)
    var envelope = SignedControlEnvelope(
        sentAt: Int64(now.timeIntervalSince1970 * 1_000),
        deviceId: "nova4",
        sequence: 1,
        nonce: "same-nonce",
        payload: ControlPayload(taskID: "task-1", action: .approve)
    )
    envelope.signature = try ControlSigner.sign(envelope, secret: secret)
    var guardState = ReplayGuard()

    try guardState.validate(envelope, secret: secret, now: now)
    #expect(throws: ProtocolError.replayed) {
        try guardState.validate(envelope, secret: secret, now: now)
    }
}

@Test("状态协议使用整数毫秒时间戳")
func stateProtocolUsesIntegerMilliseconds() throws {
    let task = TaskSnapshot(
        id: "task-1",
        source: .codexCLI,
        projectName: "AgentGrid",
        lifecycle: .running,
        startedAt: Date(timeIntervalSince1970: 100.123_456),
        updatedAt: Date(timeIntervalSince1970: 101.654_321)
    )
    let envelope = MessageEnvelope(
        type: "state.snapshot",
        payload: StateSnapshotPayload(
            tasks: [task],
            usage: nil,
            focusedTaskID: task.id
        )
    )

    let object = try #require(
        JSONSerialization.jsonObject(with: ProtocolCodec.encode(envelope))
            as? [String: Any]
    )
    let payload = try #require(object["payload"] as? [String: Any])
    let tasks = try #require(payload["tasks"] as? [[String: Any]])
    let encodedTask = try #require(tasks.first)

    #expect((encodedTask["startedAt"] as? NSNumber)?.int64Value == 100_123)
    #expect((encodedTask["startedAt"] as? NSNumber)?.doubleValue == 100_123)
    #expect((encodedTask["updatedAt"] as? NSNumber)?.int64Value == 101_654)
}

@Test("状态快照发送前过滤内部工具包装")
func stateSnapshotFiltersInternalToolWrappersBeforeSending() throws {
    let commandTask = TaskSnapshot(
        id: "command-task",
        source: .codexDesktop,
        projectName: "AgentGrid",
        latestStep: """
        const r = await tools.exec_command({cmd:"swift test",workdir:"/tmp/AgentGrid"});text(r.output)
        """,
        lifecycle: .running
    )
    let patchTask = TaskSnapshot(
        id: "patch-task",
        source: .codexDesktop,
        projectName: "AgentGrid",
        latestStep: """
        apply_patch *** Begin Patch *** Update File: /tmp/AgentGrid/App.swift @@ -旧内容 +新内容 *** End Patch
        """,
        lifecycle: .running
    )
    let envelope = MessageEnvelope(
        type: "state.snapshot",
        payload: StateSnapshotPayload(
            tasks: [commandTask, patchTask],
            usage: nil,
            focusedTaskID: commandTask.id
        )
    )

    let object = try #require(
        JSONSerialization.jsonObject(with: ProtocolCodec.encode(envelope))
            as? [String: Any]
    )
    let payload = try #require(object["payload"] as? [String: Any])
    let tasks = try #require(payload["tasks"] as? [[String: Any]])

    #expect(tasks[0]["latestStep"] as? String == "swift test")
    #expect(tasks[1]["latestStep"] as? String == "/tmp/AgentGrid/App.swift")
}

@Test("扩展状态快照保留 ZCode、多提供方额度和待审批请求标识")
func extendedStateSnapshotPreservesProtocolSemantics() throws {
    let envelope = try ProtocolCodec.decode(
        MessageEnvelope<StateSnapshotPayload>.self,
        from: protocolFixture(named: "task-snapshot-v2.json")
    )

    #expect(envelope.payload.tasks.first?.source == .zcode)
    #expect(envelope.payload.usage?.limitID == "codex")
    let glm = try #require(
        envelope.payload.usageProviders?.first { $0.id == "glm" }
    )
    #expect(glm.planName == "GLM Coding Plan")
    #expect(glm.planLevel == "lite")
    let fiveHour = try #require(glm.quotaGroups.first?.windows.first)
    #expect(fiveHour.quotaType == "CREDIT_LIMIT")
    #expect(fiveHour.usedPercentage == 5)
    #expect(fiveHour.remainingAmount == 1_897)
    #expect(
        envelope.payload.pendingRequests.first?.requestID ==
            "zcode:session-1:tool-1"
    )
}

@Test("未知来源、提供方和额度组保守降级且缺失可选字段仍可解码")
func unknownStateSnapshotUsesConservativeFallbacks() throws {
    let envelope = try ProtocolCodec.decode(
        MessageEnvelope<StateSnapshotPayload>.self,
        from: protocolFixture(named: "task-snapshot-unknown.json")
    )

    #expect(envelope.payload.tasks.first?.source == .unknown)
    #expect(envelope.payload.usage == nil)
    #expect(envelope.payload.pendingRequests.isEmpty)
    let provider = try #require(envelope.payload.usageProviders?.first)
    #expect(provider.id == "futureProvider")
    #expect(provider.displayName == nil)
    let group = try #require(provider.quotaGroups.first)
    #expect(group.id == "futureQuotaGroup")
    #expect(group.windows.first?.quotaType == "FUTURE_LIMIT")
}

@Test("ZCode 会话监控样本保持非终态空闲且不携带原始内容")
func zcodeMonitoringFixtureUsesIdleWithoutSensitiveContent() throws {
    let data = try protocolFixture(named: "zcode-session-monitoring.json")
    let text = try #require(String(data: data, encoding: .utf8))
    let envelope = try ProtocolCodec.decode(
        MessageEnvelope<StateSnapshotPayload>.self,
        from: data
    )
    let task = try #require(envelope.payload.tasks.first)

    #expect(task.source == .zcode)
    #expect(task.lifecycle == .idle)
    #expect(!task.isTerminal)
    #expect(task.completedAt == nil)
    #expect(task.userPrompt == nil)
    #expect(task.latestStep == nil)
    #expect(!text.contains("/Users/"))
    #expect(!text.lowercased().contains("token="))
}

@Test("旧 Codex 状态快照缺少扩展字段时仍可解码")
func legacyStateSnapshotStillDecodes() throws {
    let envelope = try ProtocolCodec.decode(
        MessageEnvelope<StateSnapshotPayload>.self,
        from: protocolFixture(named: "task-snapshot.json")
    )

    let task = try #require(envelope.payload.tasks.first)
    #expect(task.source == .codexCLI)
    #expect(task.title == "AgentPager")
    #expect(envelope.payload.usage == nil)
    #expect(envelope.payload.usageProviders == nil)
    #expect(envelope.payload.pendingRequests.isEmpty)
}

@Test("控制载荷可携带待审批请求标识且旧载荷仍可读取")
func controlPayloadSupportsOptionalPendingRequestID() throws {
    let current = ControlPayload(
        taskID: "zcode-session-1",
        action: .approve,
        pendingRequestID: "zcode:session-1:tool-1"
    )
    let encoded = try ProtocolCodec.encode(current)
    let object = try #require(
        JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    #expect(object["pendingRequestID"] as? String == "zcode:session-1:tool-1")

    let envelope = SignedControlEnvelope(
        messageId: UUID(uuidString: "6f539e96-6bce-4fdc-94d5-3cf4ea755622")!,
        sentAt: 1_785_067_200_000,
        deviceId: "android-test",
        sequence: 7,
        nonce: "nonce-7",
        payload: current
    )
    let signingText = try #require(
        String(data: ControlSigner.signingData(for: envelope), encoding: .utf8)
    )
    #expect(
        signingText.split(separator: "\n").last ==
            #"{"action":"approve","pendingRequestID":"zcode:session-1:tool-1","taskID":"zcode-session-1"}"#
    )

    let legacy = try ProtocolCodec.decode(
        ControlPayload.self,
        from: Data(#"{"taskID":"task-1","action":"deny"}"#.utf8)
    )
    #expect(legacy.pendingRequestID == nil)
}

private func protocolFixture(named name: String) throws -> Data {
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while directory.path != "/" {
        let candidate = directory
            .appendingPathComponent("protocol/fixtures")
            .appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: candidate.path) {
            return try Data(contentsOf: candidate)
        }
        directory.deleteLastPathComponent()
    }
    throw CocoaError(.fileNoSuchFile)
}
