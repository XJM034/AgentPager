import AgentGridCore
import Foundation
import Network
import Testing
@testable import AgentGridBridge

@MainActor
@Test("默认无 GLM Key 的真实本地 Bridge 接缝保持 ZCode 审批与 Codex Claude 可用")
func unconfiguredGLMLocalBridgeEndToEnd() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("agentpager-issue9-fixture-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let hookPort = try temporaryTCPPort()
    let webSocketPort = try temporaryTCPPort(excluding: hookPort)
    let pairingSecret = Data(repeating: 0x29, count: 32)
    let keyStore = IntegrationMemoryGLMKeyStore()
    let quotaFetcher = IntegrationSequencedGLMFetcher(results: [])
    let runtime = BridgeRuntimeConfiguration(
        hookPort: hookPort,
        webSocketPort: webSocketPort,
        advertisedHost: "127.0.0.1",
        pairingSecretLoader: { pairingSecret },
        taskPersistence: TaskSnapshotPersistence(
            fileURL: directory.appendingPathComponent("tasks.json")
        ),
        observesLocalEnvironment: false,
        startsBackgroundMaintenance: false,
        zcodeDecisionTimeoutMilliseconds: 2_000,
        usageLoader: fixtureCodexUsage
    )
    let model = BridgeModel(
        runtimeConfiguration: runtime,
        glmCoordinatorFactory: { stateHandler in
            GLMQuotaCoordinator(
                keyStore: keyStore,
                quotaFetcher: quotaFetcher,
                scheduler: IntegrationNoopGLMScheduler(),
                onStateChange: stateHandler
            )
        }
    )
    model.start()
    let client = LocalWebSocketClient(port: webSocketPort)
    defer {
        client.close()
        model.stop()
    }

    let initial = try await nextSnapshot(from: client) { snapshot in
        snapshot.usage?.quotaGroups.map(\.id) == ["codex"]
    }
    #expect(initial.usageProviders == nil)
    let initialGLMRequestCount = await quotaFetcher.requestCount
    #expect(initialGLMRequestCount == 0)

    let sessionID = "zcode-issue9-no-key-fixture"
    _ = try await exchangeHook(
        source: .zcode,
        port: hookPort,
        payload: [
            "session_id": sessionID,
            "hook_event_name": "SessionStart",
            "cwd": "/private/tmp/agentpager-issue9-fixture",
        ]
    )
    _ = try await exchangeHook(
        source: .zcode,
        port: hookPort,
        payload: [
            "session_id": sessionID,
            "hook_event_name": "PreToolUse",
            "cwd": "/private/tmp/agentpager-issue9-fixture",
            "tool_name": "Edit",
            "tool_use_id": "tool-activity-fixture",
            "tool_input": ["new_string": "fixture-private-tool-input"],
        ]
    )
    let running = try await nextSnapshot(from: client) { snapshot in
        snapshot.tasks.first(where: { $0.id == sessionID })?.lifecycle == .running
    }
    #expect(running.tasks.first(where: { $0.id == sessionID })?.activity == .editing)

    let approveToolID = "tool-approve-fixture"
    let denyToolID = "tool-deny-fixture"
    let approveRequestID = try #require(
        ZCodePendingRequestID.make(sessionID: sessionID, toolUseID: approveToolID)
    )
    let denyRequestID = try #require(
        ZCodePendingRequestID.make(sessionID: sessionID, toolUseID: denyToolID)
    )
    let approveInput = try hookInput(
        sessionID: sessionID,
        event: "PermissionRequest",
        toolUseID: approveToolID
    )
    let denyInput = try hookInput(
        sessionID: sessionID,
        event: "PermissionRequest",
        toolUseID: denyToolID
    )
    let approveExchange = Task.detached {
        HookBridgeClient.exchange(
            input: approveInput,
            source: .zcode,
            port: hookPort,
            timeoutMilliseconds: 3_000
        )
    }
    let denyExchange = Task.detached {
        HookBridgeClient.exchange(
            input: denyInput,
            source: .zcode,
            port: hookPort,
            timeoutMilliseconds: 3_000
        )
    }

    let waiting = try await nextSnapshot(from: client) { snapshot in
        Set(snapshot.pendingRequests.compactMap(\.requestID)) ==
            Set([approveRequestID, denyRequestID])
    }
    #expect(waiting.tasks.first(where: { $0.id == sessionID })?.lifecycle == .waitingApproval)

    let denyControl = try signedControl(
        taskID: sessionID,
        pendingRequestID: denyRequestID,
        action: .deny,
        sequence: 1,
        secret: pairingSecret
    )
    try await client.send(try protocolText(denyControl))
    #expect(try await nextAck(from: client, requestID: denyControl.messageId).result == .accepted)
    #expect(await denyExchange.value == (try ZCodeHookOutput.permission(.deny)))

    let approveControl = try signedControl(
        taskID: sessionID,
        pendingRequestID: approveRequestID,
        action: .approve,
        sequence: 2,
        secret: pairingSecret
    )
    try await client.send(try protocolText(approveControl))
    #expect(
        try await nextAck(from: client, requestID: approveControl.messageId).result == .accepted
    )
    #expect(await approveExchange.value == (try ZCodeHookOutput.permission(.allow)))

    _ = try await exchangeHook(
        source: .zcode,
        port: hookPort,
        payload: [
            "session_id": sessionID,
            "hook_event_name": "Stop",
            "cwd": "/private/tmp/agentpager-issue9-fixture",
            "last_assistant_message": "fixture-private-response",
        ]
    )
    let idle = try await nextSnapshot(from: client) { snapshot in
        snapshot.tasks.first(where: { $0.id == sessionID })?.lifecycle == .idle
    }
    let idleTask = try #require(idle.tasks.first { $0.id == sessionID })
    #expect(idleTask.completedAt == nil)
    #expect(idle.pendingRequests.isEmpty)

    _ = try await exchangeHook(
        source: .codex,
        port: hookPort,
        payload: [
            "session_id": "codex-issue9-fixture",
            "hook_event_name": "SessionStart",
            "cwd": "/private/tmp/agentpager-issue9-fixture",
            "source": "cli",
        ]
    )
    _ = try await exchangeHook(
        source: .claude,
        port: hookPort,
        payload: [
            "session_id": "claude-issue9-fixture",
            "hook_event_name": "SessionStart",
            "cwd": "/private/tmp/agentpager-issue9-fixture",
        ]
    )
    let allAgents = try await nextSnapshot(from: client) { snapshot in
        let sources = Set(snapshot.tasks.map(\.source))
        return sources.contains(.zcode) && sources.contains(.codexCLI) && sources.contains(.claudeCode)
    }
    let encoded = try protocolText(
        MessageEnvelope(type: "state.snapshot", payload: allAgents)
    )
    #expect(!encoded.contains("fixture-private-tool-input"))
    #expect(!encoded.contains("fixture-private-response"))
    #expect(!encoded.contains("/private/tmp/fixture-private-path"))
    #expect(initial.usageProviders == nil)
    let finalGLMRequestCount = await quotaFetcher.requestCount
    #expect(finalGLMRequestCount == 0)
}

@MainActor
@Test("合成可选 Key 的真实本地 Bridge 接缝隔离 GLM 故障并保持 single flight 与重连")
func configuredGLMLocalBridgeEndToEnd() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("agentpager-issue9-fixture-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let hookPort = try temporaryTCPPort()
    let webSocketPort = try temporaryTCPPort(excluding: hookPort)
    let pairingSecret = Data(repeating: 0x39, count: 32)
    let syntheticKey = "fixture-memory-key"
    let keyStore = IntegrationMemoryGLMKeyStore(key: syntheticKey)
    let quotaFetcher = IntegrationControllableGLMFetcher(results: [
        .success(fixtureGLMProvider()),
        .failure(.unauthorized),
        .failure(.timedOut),
        .failure(.serverUnavailable),
    ])
    let runtime = BridgeRuntimeConfiguration(
        hookPort: hookPort,
        webSocketPort: webSocketPort,
        advertisedHost: "127.0.0.1",
        pairingSecretLoader: { pairingSecret },
        taskPersistence: TaskSnapshotPersistence(
            fileURL: directory.appendingPathComponent("tasks.json")
        ),
        observesLocalEnvironment: false,
        startsBackgroundMaintenance: false,
        zcodeDecisionTimeoutMilliseconds: 2_000,
        usageLoader: fixtureCodexUsage
    )
    let model = BridgeModel(
        runtimeConfiguration: runtime,
        glmCoordinatorFactory: { stateHandler in
            GLMQuotaCoordinator(
                keyStore: keyStore,
                quotaFetcher: quotaFetcher,
                scheduler: IntegrationNoopGLMScheduler(),
                onStateChange: stateHandler
            )
        }
    )
    model.start()
    defer { model.stop() }

    await quotaFetcher.waitForRequestCount(1)
    let firstClient = LocalWebSocketClient(port: webSocketPort)
    let connectedSnapshot = try await nextSnapshot(from: firstClient) { snapshot in
        snapshot.usageProviders == nil &&
            snapshot.usage?.quotaGroups.map(\.id) == ["codex"]
    }
    #expect(connectedSnapshot.tasks.isEmpty)
    model.refreshGLMQuota()
    await Task.yield()
    let overlappingRequestCount = await quotaFetcher.requestCount
    #expect(overlappingRequestCount == 1)

    await quotaFetcher.releaseFirstRequest()
    let available = try await nextSnapshot(from: firstClient) { snapshot in
        snapshot.usageProviders?.count == 1 && snapshot.usageProviders?.first?.status == "available"
    }
    #expect(available.usage?.quotaGroups.map(\.id) == ["codex"])
    let glm = try #require(available.usageProviders?.first)
    #expect(glm.id == "glm")
    #expect(glm.quotaGroups.count == 1)
    #expect(glm.quotaGroups.first?.windows.map(\.key) == ["5-hour", "weekly"])
    let availableText = try protocolText(available)
    #expect(!availableText.contains(syntheticKey))
    await waitForBridgeOperation(model)

    model.refreshGLMQuota()
    let unauthorized = try await nextSnapshot(from: firstClient) { snapshot in
        snapshot.usageProviders?.first?.status == "auth_unauthorized"
    }
    #expect(unauthorized.tasks.isEmpty)
    #expect(unauthorized.usageProviders?.first?.quotaGroups.first?.windows.count == 2)
    await waitForBridgeOperation(model)

    model.refreshGLMQuota()
    let timedOut = try await nextSnapshot(from: firstClient) { snapshot in
        snapshot.usageProviders?.first?.status == "stale_timeout"
    }
    #expect(timedOut.usageProviders?.first?.quotaGroups.first?.windows.count == 2)
    await waitForBridgeOperation(model)

    model.refreshGLMQuota()
    let temporarilyUnavailable = try await nextSnapshot(from: firstClient) { snapshot in
        snapshot.usageProviders?.first?.status == "stale_server_error"
    }
    #expect(
        temporarilyUnavailable.usageProviders?.first?.quotaGroups.first?.windows.count == 2
    )
    await waitForBridgeOperation(model)

    let sessionID = "zcode-issue9-glm-failure-fixture"
    _ = try await exchangeHook(
        source: .zcode,
        port: hookPort,
        payload: [
            "session_id": sessionID,
            "hook_event_name": "SessionStart",
            "cwd": "/private/tmp/agentpager-issue9-fixture",
        ]
    )
    let toolID = "tool-glm-failure-approve-fixture"
    let requestID = try #require(
        ZCodePendingRequestID.make(sessionID: sessionID, toolUseID: toolID)
    )
    let permissionInput = try hookInput(
        sessionID: sessionID,
        event: "PermissionRequest",
        toolUseID: toolID
    )
    let permissionExchange = Task.detached {
        HookBridgeClient.exchange(
            input: permissionInput,
            source: .zcode,
            port: hookPort,
            timeoutMilliseconds: 3_000
        )
    }
    _ = try await nextSnapshot(from: firstClient) { snapshot in
        snapshot.pendingRequests.count == 1 &&
            snapshot.pendingRequests.first?.requestID == requestID
    }
    let approveControl = try signedControl(
        taskID: sessionID,
        pendingRequestID: requestID,
        action: .approve,
        sequence: 1,
        secret: pairingSecret
    )
    try await firstClient.send(try protocolText(approveControl))
    #expect(
        try await nextAck(from: firstClient, requestID: approveControl.messageId).result == .accepted
    )
    #expect(await permissionExchange.value == (try ZCodeHookOutput.permission(.allow)))

    let denyToolID = "tool-glm-failure-deny-fixture"
    let denyRequestID = try #require(
        ZCodePendingRequestID.make(sessionID: sessionID, toolUseID: denyToolID)
    )
    let denyInput = try hookInput(
        sessionID: sessionID,
        event: "PermissionRequest",
        toolUseID: denyToolID
    )
    let denyExchange = Task.detached {
        HookBridgeClient.exchange(
            input: denyInput,
            source: .zcode,
            port: hookPort,
            timeoutMilliseconds: 3_000
        )
    }
    _ = try await nextSnapshot(from: firstClient) { snapshot in
        snapshot.pendingRequests.count == 1 &&
            snapshot.pendingRequests.first?.requestID == denyRequestID
    }
    let denyControl = try signedControl(
        taskID: sessionID,
        pendingRequestID: denyRequestID,
        action: .deny,
        sequence: 2,
        secret: pairingSecret
    )
    try await firstClient.send(try protocolText(denyControl))
    #expect(
        try await nextAck(from: firstClient, requestID: denyControl.messageId).result == .accepted
    )
    #expect(await denyExchange.value == (try ZCodeHookOutput.permission(.deny)))

    model.deleteGLMKey()
    let deleted = try await nextSnapshot(from: firstClient) { snapshot in
        snapshot.usageProviders == nil
    }
    #expect(deleted.usage?.quotaGroups.map(\.id) == ["codex"])
    await waitForBridgeOperation(model)
    #expect((try? keyStore.load()) == nil)
    let requestCountAfterDeletion = await quotaFetcher.requestCount
    let maximumConcurrentRequestCount = await quotaFetcher.maximumConcurrentRequestCount
    #expect(requestCountAfterDeletion >= 4)
    #expect(maximumConcurrentRequestCount == 1)
    model.refreshGLMQuota()
    await waitForBridgeOperation(model)
    let requestCountAfterDisabledRefresh = await quotaFetcher.requestCount
    #expect(requestCountAfterDisabledRefresh == requestCountAfterDeletion)

    firstClient.close()
    try await Task.sleep(for: .milliseconds(20))
    let afterDisconnectID = "zcode-issue9-after-disconnect-fixture"
    _ = try await exchangeHook(
        source: .zcode,
        port: hookPort,
        payload: [
            "session_id": afterDisconnectID,
            "hook_event_name": "SessionStart",
            "cwd": "/private/tmp/agentpager-issue9-fixture",
        ]
    )
    let reconnectedClient = LocalWebSocketClient(port: webSocketPort)
    defer { reconnectedClient.close() }
    let reconnected = try await nextSnapshot(from: reconnectedClient) { snapshot in
        snapshot.tasks.contains { $0.id == afterDisconnectID }
    }
    #expect(reconnected.usageProviders == nil)
    #expect(model.serviceStatus == "局域网服务运行中")
    let requestCountAfterReconnect = await quotaFetcher.requestCount
    #expect(requestCountAfterReconnect == requestCountAfterDeletion)
}

private final class LocalWebSocketClient: @unchecked Sendable {
    private let session: URLSession
    private let task: URLSessionWebSocketTask

    init(port: UInt16) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
        task = session.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)")!)
        task.resume()
    }

    func send(_ text: String) async throws {
        try await task.send(.string(text))
    }

    func receiveText() async throws -> String {
        switch try await task.receive() {
        case let .string(text): text
        case let .data(data):
            try #require(String(data: data, encoding: .utf8))
        @unknown default:
            throw LocalBridgeEndToEndError.unexpectedWebSocketMessage
        }
    }

    func close() {
        task.cancel(with: .normalClosure, reason: nil)
        session.invalidateAndCancel()
    }
}

private enum LocalBridgeEndToEndError: Error {
    case timedOut
    case unexpectedWebSocketMessage
    case temporaryPortUnavailable
}

@MainActor
private func nextSnapshot(
    from client: LocalWebSocketClient,
    matching predicate: (StateSnapshotPayload) -> Bool
) async throws -> StateSnapshotPayload {
    for _ in 0..<80 {
        let text = try await withTimeout { try await client.receiveText() }
        guard let data = text.data(using: .utf8),
              let envelope = try? ProtocolCodec.decode(
                  MessageEnvelope<StateSnapshotPayload>.self,
                  from: data
              ),
              envelope.type == "state.snapshot",
              predicate(envelope.payload) else {
            continue
        }
        return envelope.payload
    }
    throw LocalBridgeEndToEndError.timedOut
}

@MainActor
private func nextAck(
    from client: LocalWebSocketClient,
    requestID: UUID
) async throws -> ControlAckPayload {
    for _ in 0..<80 {
        let text = try await withTimeout { try await client.receiveText() }
        guard let data = text.data(using: .utf8),
              let envelope = try? ProtocolCodec.decode(
                  MessageEnvelope<ControlAckPayload>.self,
                  from: data
              ),
              envelope.type == "control.ack",
              envelope.payload.requestID == requestID else {
            continue
        }
        return envelope.payload
    }
    throw LocalBridgeEndToEndError.timedOut
}

private func withTimeout<T: Sendable>(
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        let gate = TimeoutContinuationGate(continuation)
        Task {
            do {
                gate.resume(returning: try await operation())
            } catch {
                gate.resume(throwing: error)
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            gate.resume(throwing: LocalBridgeEndToEndError.timedOut)
        }
    }
}

private final class TimeoutContinuationGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: Value) {
        take()?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<Value, Error>? {
        lock.withLock {
            defer { continuation = nil }
            return continuation
        }
    }
}

private func exchangeHook(
    source: HookSource,
    port: UInt16,
    payload: [String: Any]
) async throws -> Data {
    let input = try JSONSerialization.data(withJSONObject: payload)
    return await Task.detached {
        HookBridgeClient.exchange(
            input: input,
            source: source,
            port: port,
            timeoutMilliseconds: 2_000
        )
    }.value
}

private func hookInput(
    sessionID: String,
    event: String,
    toolUseID: String
) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "session_id": sessionID,
        "hook_event_name": event,
        "cwd": "/private/tmp/agentpager-issue9-fixture",
        "tool_name": "Read",
        "tool_use_id": toolUseID,
        "tool_input": ["file_path": "/private/tmp/fixture-private-path"],
    ])
}

private func signedControl(
    taskID: String,
    pendingRequestID: String,
    action: ControlAction,
    sequence: UInt64,
    secret: Data
) throws -> SignedControlEnvelope {
    var envelope = SignedControlEnvelope(
        deviceId: "android-issue9-fixture",
        sequence: sequence,
        nonce: "issue9-fixture-nonce-\(sequence)",
        payload: ControlPayload(
            taskID: taskID,
            action: action,
            pendingRequestID: pendingRequestID
        )
    )
    envelope.signature = try ControlSigner.sign(envelope, secret: secret)
    return envelope
}

private func protocolText<T: Codable & Sendable>(_ value: T) throws -> String {
    try #require(String(data: ProtocolCodec.encode(value), encoding: .utf8))
}

private func fixtureCodexUsage() -> UsageSnapshot? {
    let capturedAt = Date(timeIntervalSince1970: 1_787_900_200)
    return UsageSnapshot(
        capturedAt: capturedAt,
        planType: "fixture",
        limitID: "codex",
        windows: [],
        quotaGroups: [
            QuotaGroup(id: "codex", name: "GENERAL", capturedAt: capturedAt, windows: []),
        ]
    )
}

private func temporaryTCPPort(excluding excluded: UInt16? = nil) throws -> UInt16 {
    for _ in 0..<40 {
        let port = UInt16.random(in: 50_000...62_000)
        guard port != excluded,
              let listener = try? NWListener(
                  using: .tcp,
                  on: NWEndpoint.Port(rawValue: port)!
              ) else {
            continue
        }
        listener.cancel()
        return port
    }
    throw LocalBridgeEndToEndError.temporaryPortUnavailable
}

@MainActor
private func waitForBridgeOperation(_ model: BridgeModel) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(2))
    while model.glmOperationInProgress, clock.now < deadline {
        await Task.yield()
    }
    #expect(!model.glmOperationInProgress)
}

private func fixtureGLMProvider() -> UsageProviderSnapshot {
    let capturedAt = Date(timeIntervalSince1970: 1_787_900_200)
    return UsageProviderSnapshot(
        id: "glm",
        displayName: "GLM",
        planName: "GLM Coding Plan",
        planLevel: "fixture-level",
        capturedAt: capturedAt,
        status: "available",
        quotaGroups: [
            QuotaGroup(
                id: "credit",
                name: "CREDIT_LIMIT",
                capturedAt: capturedAt,
                windows: [
                    UsageWindow(
                        key: "5-hour",
                        label: "5H",
                        usedPercentage: 18,
                        remainingPercentage: 82,
                        windowMinutes: 300,
                        resetsAt: capturedAt.addingTimeInterval(3_600),
                        remainingAmount: 1_640
                    ),
                    UsageWindow(
                        key: "weekly",
                        label: "WEEK",
                        usedPercentage: 36,
                        remainingPercentage: 64,
                        windowMinutes: 10_080,
                        resetsAt: capturedAt.addingTimeInterval(86_400),
                        remainingAmount: 6_400
                    ),
                ]
            ),
        ]
    )
}

private final class IntegrationMemoryGLMKeyStore: GLMKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var key: String?

    init(key: String? = nil) {
        self.key = key
    }

    func load() throws -> String? { lock.withLock { key } }
    func save(_ key: String) throws { lock.withLock { self.key = key } }
    func delete() throws { lock.withLock { key = nil } }
}

private actor IntegrationSequencedGLMFetcher: GLMQuotaFetching {
    private var results: [Result<UsageProviderSnapshot, GLMQuotaError>]
    private(set) var requestCount = 0

    init(results: [Result<UsageProviderSnapshot, GLMQuotaError>]) {
        self.results = results
    }

    func fetchQuota(using key: String) async throws -> UsageProviderSnapshot {
        requestCount += 1
        guard !results.isEmpty else { throw GLMQuotaError.unavailable }
        return try results.removeFirst().get()
    }
}

private actor IntegrationControllableGLMFetcher: GLMQuotaFetching {
    private var results: [Result<UsageProviderSnapshot, GLMQuotaError>]
    private var firstRequestContinuation: CheckedContinuation<Void, Never>?
    private var countWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var requestCount = 0
    private(set) var maximumConcurrentRequestCount = 0
    private var inFlightRequestCount = 0

    init(results: [Result<UsageProviderSnapshot, GLMQuotaError>]) {
        self.results = results
    }

    func fetchQuota(using key: String) async throws -> UsageProviderSnapshot {
        requestCount += 1
        inFlightRequestCount += 1
        maximumConcurrentRequestCount = max(
            maximumConcurrentRequestCount,
            inFlightRequestCount
        )
        defer { inFlightRequestCount -= 1 }
        if requestCount == 1 {
            await withCheckedContinuation { continuation in
                firstRequestContinuation = continuation
                resumeSatisfiedCountWaiters()
            }
        } else {
            resumeSatisfiedCountWaiters()
        }
        guard !results.isEmpty else { throw GLMQuotaError.unavailable }
        return try results.removeFirst().get()
    }

    func waitForRequestCount(_ expected: Int) async {
        if requestCount >= expected { return }
        await withCheckedContinuation { continuation in
            countWaiters.append((expected, continuation))
        }
    }

    func releaseFirstRequest() {
        firstRequestContinuation?.resume()
        firstRequestContinuation = nil
    }

    private func resumeSatisfiedCountWaiters() {
        let satisfied = countWaiters.filter { requestCount >= $0.0 }
        countWaiters.removeAll { requestCount >= $0.0 }
        satisfied.forEach { $0.1.resume() }
    }
}

private final class IntegrationNoopGLMScheduler: GLMRefreshScheduler, @unchecked Sendable {
    func schedule(
        after interval: TimeInterval,
        operation: @escaping @Sendable () -> Void
    ) -> any GLMScheduledTask {
        IntegrationNoopGLMScheduledTask()
    }
}

private final class IntegrationNoopGLMScheduledTask: GLMScheduledTask, @unchecked Sendable {
    func cancel() {}
}

@MainActor
@Test("Paseo 未输入 omp 经认证本机入口自动进入手机快照")
func paseoCreatedSessionReachesPhone() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let ports = try paseoTestPorts()
    let (hookPort, phonePort, paseoPort) = (ports[0], ports[1], ports[2])
    let model = BridgeModel(runtimeConfiguration: BridgeRuntimeConfiguration(
        hookPort: hookPort, webSocketPort: phonePort, advertisedHost: "127.0.0.1",
        pairingSecretLoader: { Data(repeating: 14, count: 32) },
        taskPersistence: TaskSnapshotPersistence(fileURL: directory.appendingPathComponent("tasks.json")),
        observesLocalEnvironment: false, startsBackgroundMaintenance: false,
        usageLoader: { nil },
        paseoIngress: PaseoIngressConfiguration(port: paseoPort, token: String(repeating: "a", count: 64))
    ), glmCoordinatorFactory: { stateHandler in
        GLMQuotaCoordinator(keyStore: IntegrationMemoryGLMKeyStore(),
            quotaFetcher: IntegrationSequencedGLMFetcher(results: []),
            scheduler: IntegrationNoopGLMScheduler(), onStateChange: stateHandler)
    })
    model.start()
    try await waitForPaseoTestPort(phonePort)
    try await waitForPaseoTestPort(paseoPort)
    let client = LocalWebSocketClient(port: phonePort)
    defer { client.close(); model.stop() }
    _ = try await nextSnapshot(from: client) { $0.tasks.isEmpty }
    let payload: [String: Any] = [
        "token": String(repeating: "a", count: 64), "hostID": "host-a",
        "agentID": "agent-a", "provider": "omp", "projectName": "AgentPager",
        "titleCategory": "development", "status": "idle", "archived": false,
    ]
    var unauthorized = payload
    unauthorized["token"] = "wrong-token"
    unauthorized["agentID"] = "unauthorized"
    #expect(try await paseoExchange(JSONSerialization.data(withJSONObject: unauthorized) + Data([10]), port: paseoPort) == "")
    let line = try JSONSerialization.data(withJSONObject: payload) + Data([10])
    let reply = try await paseoExchange(line, port: paseoPort)
    #expect(reply == "ok")
    let snapshot = try await nextSnapshot(from: client) { !$0.tasks.isEmpty }
    let task = try #require(snapshot.tasks.first)
    #expect(task.source.rawValue == "omp")
    #expect(task.lifecycle == .idle)
    #expect(task.completedAt == nil)
    #expect(task.capabilities.isEmpty)
    #expect(task.title == "AgentPager · 开发请求")
    #expect(snapshot.pendingRequests.isEmpty)

    let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("integrations/paseo-omp/test/discovery-fixture.mjs")
    let result = try await Task.detached {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", fixtureURL.path, String(paseoPort), String(repeating: "a", count: 64)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }.value
    #expect(result == 0)
    let discovered = try await nextSnapshot(from: client) { $0.tasks.count == 4 }
    #expect(Set(discovered.tasks.map(\.id)).count == 4)
    #expect(discovered.tasks.allSatisfy { $0.source == .omp && $0.lifecycle == .idle })
    #expect(discovered.tasks.filter { $0.projectName == "AgentPager" }.count == 3)
    #expect(discovered.tasks.filter { $0.projectName == "ProjectB" }.count == 1)
    // Repeated messages do not alter existing identity or timestamps.
    #expect(try await paseoExchange(line, port: paseoPort) == "ok")
    var otherHost = payload
    otherHost["hostID"] = "host-b"
    #expect(try await paseoExchange(JSONSerialization.data(withJSONObject: otherHost) + Data([10]), port: paseoPort) == "ok")
    let multiHost = try await nextSnapshot(from: client) { $0.tasks.count == 5 }
    #expect(multiHost.tasks.first { $0.id == task.id } == task)
    #expect(Set(multiHost.tasks.map(\.id)).count == 5)
    let phoneText = try protocolText(multiHost)
    let persisted = try String(contentsOf: directory.appendingPathComponent("tasks.json"), encoding: .utf8)
    for sensitive in ["sensitive-parent", "secret-prompt-value", "fixture-host", String(repeating: "a", count: 64)] {
        #expect(!phoneText.contains(sensitive))
        #expect(!persisted.contains(sensitive))
        #expect(!model.recentEvents.joined().contains(sensitive))
    }
}

@MainActor
@Test("omp 恢复与分支无需 created，归档不再占用手机目录")
func paseoRecoveryReachesPhone() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let ports = try paseoTestPorts()
    let model = BridgeModel(runtimeConfiguration: BridgeRuntimeConfiguration(
        hookPort: ports[0], webSocketPort: ports[1], advertisedHost: "127.0.0.1",
        pairingSecretLoader: { Data(repeating: 15, count: 32) },
        taskPersistence: TaskSnapshotPersistence(fileURL: directory.appendingPathComponent("tasks.json")),
        observesLocalEnvironment: false, startsBackgroundMaintenance: false, usageLoader: { nil },
        paseoIngress: PaseoIngressConfiguration(port: ports[2], token: String(repeating: "b", count: 64))
    ), glmCoordinatorFactory: { handler in
        GLMQuotaCoordinator(keyStore: IntegrationMemoryGLMKeyStore(),
            quotaFetcher: IntegrationSequencedGLMFetcher(results: []),
            scheduler: IntegrationNoopGLMScheduler(), onStateChange: handler)
    })
    var phone: LocalWebSocketClient!
    let process = Process()
    let input = Pipe()
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("integrations/paseo-omp/test/turn-fixture.mjs")
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", fixture.path, String(ports[2]), String(repeating: "b", count: 64)]
    process.standardInput = input
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    defer {
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        phone?.close()
        model.stop()
    }
    try process.run()
    let ready = try output.fileHandleForReading.read(upToCount: 6)
    #expect(ready == Data("ready\n".utf8))
    model.start()
    try await waitForPaseoTestPort(ports[1])
    try await waitForPaseoTestPort(ports[2])
    phone = LocalWebSocketClient(port: ports[1])
    _ = try await nextSnapshot(from: phone) { $0.tasks.isEmpty }
    try input.fileHandleForWriting.write(contentsOf: Data("sync\n".utf8))
    let initial = try await nextSnapshot(from: phone) { $0.tasks.count == 1 }
    let identity = try #require(initial.tasks.first?.id)
    #expect(initial.tasks.first?.lifecycle == .idle)
    try input.fileHandleForWriting.write(contentsOf: Data("import\n".utf8))
    let imported = try await nextSnapshot(from: phone) { $0.tasks.count == 2 }
    #expect(Set(imported.tasks.map(\.id)).count == 2)
    #expect(imported.tasks.allSatisfy { $0.lifecycle == .idle && $0.completedAt == nil })
    #expect(imported.tasks.contains { $0.id == identity })
    try input.fileHandleForWriting.write(contentsOf: Data("archive\n".utf8))
    let archived = try await nextSnapshot(from: phone) { $0.tasks.count == 1 }
    #expect(archived.tasks.first?.id == identity)
    try input.fileHandleForWriting.write(contentsOf: Data("silent-start\n".utf8))
    let recovered = try await nextSnapshot(from: phone) { $0.tasks.first?.lifecycle == .running }
    #expect(recovered.tasks.first?.id == identity)
    #expect(recovered.tasks.first?.completedAt == nil)
    try input.fileHandleForWriting.write(contentsOf: Data("silent-idle\n".utf8))
    let idle = try await nextSnapshot(from: phone) { $0.tasks.first?.lifecycle == .idle }
    #expect(idle.tasks.first?.id == identity)
    #expect(idle.tasks.first?.completedAt == nil)
    try input.fileHandleForWriting.write(contentsOf: Data("callback-fast\n".utf8))
    let fast = try await nextSnapshot(from: phone) { $0.tasks.first?.lifecycle == .running }
    #expect(fast.tasks.first?.id == identity)
    try input.fileHandleForWriting.write(contentsOf: Data("new-generation\n".utf8))
    let generation = try await nextSnapshot(from: phone) { $0.tasks.first?.activity == .reading }
    #expect(generation.tasks.first?.id == identity)
    try input.fileHandleForWriting.write(contentsOf: Data("recovery-hazards\n".utf8))
    let raced = try await nextSnapshot(from: phone) { snapshot in
        #expect(snapshot.tasks.count == 1)
        #expect(snapshot.tasks.first?.lifecycle == .running)
        return snapshot.tasks.first?.activity == .editing
    }
    #expect(raced.tasks.first?.id == identity)
    try input.fileHandleForWriting.write(contentsOf: Data("resource-recovery\n".utf8))
    let resourceRecovered = try await nextSnapshot(from: phone) { $0.tasks.first?.activity == .browsing }
    #expect(resourceRecovered.tasks.first?.id == identity)
    let reconnectedPhone = LocalWebSocketClient(port: ports[1])
    defer { reconnectedPhone.close() }
    let reconnected = try await nextSnapshot(from: reconnectedPhone) { !$0.tasks.isEmpty }
    #expect(reconnected.tasks == resourceRecovered.tasks)
    try input.fileHandleForWriting.write(contentsOf: Data("busy-snapshot\n".utf8))
    let busy = try await nextSnapshot(from: phone) { $0.tasks.count == 2 }
    #expect(busy.tasks.first { $0.id == identity }?.lifecycle == .running)
    try input.fileHandleForWriting.write(contentsOf: Data("outcome-race\n".utf8))
    let outcome = try await nextSnapshot(from: phone) { $0.tasks.first?.lifecycle == .succeeded }
    #expect(outcome.tasks.first?.completedAt != nil)
    try input.fileHandleForWriting.write(contentsOf: Data("adapter-restart-empty\n".utf8))
    _ = try await nextSnapshot(from: phone) { $0.tasks.isEmpty }
    if let capture = ProcessInfo.processInfo.environment["AGENTPAGER_CAPTURE_OMP_RECOVERY"] {
        try Data(protocolText([initial, imported, archived, recovered, idle, fast, generation, raced, reconnected]).utf8)
            .write(to: URL(fileURLWithPath: capture))
    }
}

@MainActor
@Test("omp 真实适配入口在同一卡片同步运行与思考")
func paseoTurnProgressReachesPhone() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let ports = try paseoTestPorts()
    let model = BridgeModel(runtimeConfiguration: BridgeRuntimeConfiguration(
        hookPort: ports[0], webSocketPort: ports[1], advertisedHost: "127.0.0.1",
        pairingSecretLoader: { Data(repeating: 15, count: 32) },
        taskPersistence: TaskSnapshotPersistence(fileURL: directory.appendingPathComponent("tasks.json")),
        observesLocalEnvironment: false, startsBackgroundMaintenance: false, usageLoader: { nil },
        paseoIngress: PaseoIngressConfiguration(port: ports[2], token: String(repeating: "b", count: 64))
    ), glmCoordinatorFactory: { handler in
        GLMQuotaCoordinator(keyStore: IntegrationMemoryGLMKeyStore(),
            quotaFetcher: IntegrationSequencedGLMFetcher(results: []),
            scheduler: IntegrationNoopGLMScheduler(), onStateChange: handler)
    })
    model.start()
    try await waitForPaseoTestPort(ports[1])
    try await waitForPaseoTestPort(ports[2])
    let phone = LocalWebSocketClient(port: ports[1])
    let process = Process()
    let input = Pipe()
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("integrations/paseo-omp/test/turn-fixture.mjs")
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", fixture.path, String(ports[2]), String(repeating: "b", count: 64)]
    process.standardInput = input
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    defer {
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        phone.close()
        model.stop()
    }
    _ = try await nextSnapshot(from: phone) { $0.tasks.isEmpty }
    try process.run()
    let initial = try await nextSnapshot(from: phone) { $0.tasks.count == 1 }
    let identity = try #require(initial.tasks.first?.id)
    #expect(initial.tasks.first?.lifecycle == .idle)
    try input.fileHandleForWriting.write(contentsOf: Data("start\n".utf8))
    let running = try await nextSnapshot(from: phone) { $0.tasks.first?.lifecycle == .running }
    #expect(running.tasks.count == 1)
    #expect(running.tasks.first?.id == identity)
    #expect(running.tasks.first?.activity == .thinking)
    #expect(running.tasks.first?.completedAt == nil)
    try input.fileHandleForWriting.write(contentsOf: Data("tool\n".utf8))
    let tool = try await nextSnapshot(from: phone) { $0.tasks.first?.activity == .reading }
    #expect(tool.tasks.first?.latestStep == ZCodeEventReducer.safeStep(for: .reading))
    #expect(tool.tasks.first?.lifecycle == .running)
    try input.fileHandleForWriting.write(contentsOf: Data("complete\n".utf8))
    let completed = try await nextSnapshot(from: phone) { $0.tasks.first?.lifecycle == .succeeded }
    #expect(completed.tasks.first?.completedAt != nil)
    #expect(completed.tasks.first?.id == identity)
    try input.fileHandleForWriting.write(contentsOf: Data("next\n".utf8))
    let next = try await nextSnapshot(from: phone) { $0.tasks.first?.lifecycle == .running }
    #expect(next.tasks.count == 1)
    #expect(next.tasks.first?.id == identity)
    #expect(next.tasks.first?.activity == .thinking)
    #expect(next.tasks.first?.completedAt == nil)
    try input.fileHandleForWriting.write(contentsOf: Data("hazards\n".utf8))
    let safe = try await nextSnapshot(from: phone) { snapshot in
        #expect(snapshot.tasks.filter { $0.id == identity }.allSatisfy { $0.lifecycle == .running })
        return snapshot.tasks.first?.activity == .editing
    }
    #expect(safe.tasks.count == 1)
    #expect(safe.tasks.first?.id == identity)
    #expect(safe.tasks.first?.completedAt == nil)
    try input.fileHandleForWriting.write(contentsOf: Data("burst\n".utf8))
    let secondCompletion = try await nextSnapshot(from: phone) { $0.tasks.first?.lifecycle == .succeeded }
    #expect(secondCompletion.tasks.first?.id == identity)
    let immediateNext = try await nextSnapshot(from: phone) { $0.tasks.first?.lifecycle == .running }
    #expect(immediateNext.tasks.first?.id == identity)
    try input.fileHandleForWriting.write(contentsOf: Data("equal-time-old-round\n".utf8))
    let protected = try await nextSnapshot(from: phone) { snapshot in
        #expect(snapshot.tasks.count == 1)
        #expect(snapshot.tasks.first?.lifecycle == .running)
        return snapshot.tasks.first?.activity == .reading
    }
    #expect(protected.tasks.first?.id == identity)
    try input.fileHandleForWriting.write(contentsOf: Data("churn\n".utf8))
    let fresh = try await nextSnapshot(from: phone) { $0.tasks.contains { $0.projectName == "Fresh" } }
    #expect(fresh.tasks.contains { $0.projectName == "Fresh" && $0.lifecycle == .idle })
    let snapshots = [initial, running, tool, completed, next, safe]
    if let capture = ProcessInfo.processInfo.environment["AGENTPAGER_CAPTURE_OMP_TURNS"] {
        try Data(protocolText(snapshots).utf8).write(to: URL(fileURLWithPath: capture))
    }
    for snapshot in snapshots {
        let text = try protocolText(snapshot)
        for secret in ["secret-prompt", "secret-path", "secret-tool", "round-1"] {
            #expect(!text.contains(secret))
            #expect(!model.recentEvents.joined().contains(secret))
        }
    }

}

@Test("Paseo 原生请求经实际插件与 Bridge 到手机，保持只读")
@MainActor
func paseoAttentionReachesPhone() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let ports = try paseoTestPorts()
    let model = BridgeModel(runtimeConfiguration: BridgeRuntimeConfiguration(
        hookPort: ports[0], webSocketPort: ports[1], advertisedHost: "127.0.0.1",
        pairingSecretLoader: { Data(repeating: 15, count: 32) },
        taskPersistence: TaskSnapshotPersistence(fileURL: directory.appendingPathComponent("tasks.json")),
        observesLocalEnvironment: false, startsBackgroundMaintenance: false, usageLoader: { nil },
        paseoIngress: PaseoIngressConfiguration(port: ports[2], token: String(repeating: "b", count: 64))
    ), glmCoordinatorFactory: { handler in
        GLMQuotaCoordinator(keyStore: IntegrationMemoryGLMKeyStore(),
            quotaFetcher: IntegrationSequencedGLMFetcher(results: []),
            scheduler: IntegrationNoopGLMScheduler(), onStateChange: handler)
    })
    model.start()
    try await waitForPaseoTestPort(ports[1])
    try await waitForPaseoTestPort(ports[2])
    let phone = LocalWebSocketClient(port: ports[1])
    let process = Process()
    let input = Pipe()
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("integrations/paseo-omp/test/turn-fixture.mjs")
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", fixture.path, String(ports[2]), String(repeating: "b", count: 64)]
    process.standardInput = input
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    defer {
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        phone.close()
        model.stop()
    }
    _ = try await nextSnapshot(from: phone) { $0.tasks.isEmpty }
    try process.run()
    let initial = try await nextSnapshot(from: phone) { $0.tasks.count == 1 }
    let identity = try #require(initial.tasks.first?.id)
    #expect(initial.tasks.first?.lifecycle == .idle)
    try input.fileHandleForWriting.write(contentsOf: Data("start\n".utf8))
    let running = try await nextSnapshot(from: phone) { $0.tasks.first?.lifecycle == .running }
    #expect(running.tasks.count == 1)
    #expect(running.tasks.first?.id == identity)
    #expect(running.tasks.first?.activity == .thinking)
    #expect(running.tasks.first?.completedAt == nil)
    try input.fileHandleForWriting.write(contentsOf: Data("approval\n".utf8))
    let waiting = try await nextSnapshot(from: phone) { $0.tasks.first?.lifecycle == .waitingApproval }
    #expect(waiting.tasks.first?.latestStep == "请回到 Paseo 处理工具审批")
    #expect(waiting.tasks.first?.capabilities.isEmpty == true)
    try input.fileHandleForWriting.write(contentsOf: Data("question\n".utf8))
    let question = try await nextSnapshot(from: phone) { $0.tasks.first?.lifecycle == .waitingAnswer }
    #expect(question.tasks.first?.latestStep == "请回到 Paseo 处理待确认事项")
    try input.fileHandleForWriting.write(contentsOf: Data("resolve-a\nstale-resolved\ntool-c\nresolve-b\n".utf8))
    let stillWaiting = try await nextSnapshot(from: phone) { snapshot in
        #expect(snapshot.tasks.first?.lifecycle != .running)
        return snapshot.tasks.first?.lifecycle == .waitingApproval
    }
    try input.fileHandleForWriting.write(contentsOf: Data("stale-resolved\nresolve-c\n".utf8))
    let resumed = try await nextSnapshot(from: phone) { snapshot in
        #expect(snapshot.tasks.first?.lifecycle != .waitingAnswer)
        return snapshot.tasks.first?.lifecycle == .running
    }
    #expect(resumed.tasks.first?.completedAt == nil)
    try input.fileHandleForWriting.write(contentsOf: Data("refresh-race\n".utf8))
    _ = try await nextSnapshot(from: phone) { $0.tasks.first?.lifecycle == .waitingApproval }
    let raceResolved = try await nextSnapshot(from: phone) { $0.tasks.first?.lifecycle == .running }
    #expect(raceResolved.tasks.first?.completedAt == nil)
    try input.fileHandleForWriting.write(contentsOf: Data("failed\n".utf8))
    let failed = try await nextSnapshot(from: phone) { $0.tasks.first?.lifecycle == .interrupted }
    #expect(failed.tasks.first?.latestStep == "本轮执行失败，请回到 Paseo 查看")
    #expect(failed.tasks.first?.completedAt != nil)
    try input.fileHandleForWriting.write(contentsOf: Data("next\n".utf8))
    let next = try await nextSnapshot(from: phone) { snapshot in
        #expect(snapshot.tasks.first?.lifecycle != .offline)
        return snapshot.tasks.first?.lifecycle == .running
    }
    try input.fileHandleForWriting.write(contentsOf: Data("plan\n".utf8))
    let plan = try await nextSnapshot(from: phone) { $0.tasks.first?.lifecycle == .waitingAnswer }
    #expect(plan.tasks.first?.latestStep == "请回到 Paseo 处理待确认事项")
    try input.fileHandleForWriting.write(contentsOf: Data("other\nstale-resolved\ncanceled\n".utf8))
    let canceled = try await nextSnapshot(from: phone) { snapshot in
        #expect(snapshot.tasks.first?.lifecycle != .running)
        return snapshot.tasks.first?.lifecycle == .interrupted
    }
    #expect(canceled.tasks.first?.latestStep == "本轮已取消")
    #expect(canceled.tasks.first?.completedAt != nil)
    let snapshots = [initial, running, waiting, question, stillWaiting, resumed, failed, next, plan, canceled]
    if let capture = ProcessInfo.processInfo.environment["AGENTPAGER_CAPTURE_OMP_ATTENTION"] {
        try Data(protocolText(snapshots).utf8).write(to: URL(fileURLWithPath: capture))
    }
    for snapshot in snapshots {
        #expect(snapshot.tasks.first?.id == identity)
        #expect(snapshot.tasks.first?.capabilities.isEmpty == true)
        let text = try protocolText(snapshot)
        for secret in ["secret-", "request-a", "request-b", "round-1"] {
            #expect(!text.contains(secret))
            #expect(!model.recentEvents.joined().contains(secret))
        }
    }
}

private func paseoExchange(_ line: Data, port: UInt16) async throws -> String {
    try await withTimeout {
        try await withCheckedThrowingContinuation { continuation in
            let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
            let gate = TimeoutContinuationGate<String>(continuation)
            connection.stateUpdateHandler = { state in
                if case .ready = state {
                    connection.send(content: line, completion: .contentProcessed { error in
                        if let error { gate.resume(throwing: error); connection.cancel(); return }
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 32) { data, _, _, error in
                            if let error { gate.resume(throwing: error) }
                            else { gate.resume(returning: String(data: data ?? Data(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") }
                            connection.cancel()
                        }
                    })
                } else if case let .failed(error) = state { gate.resume(throwing: error); connection.cancel() }
            }
            connection.start(queue: DispatchQueue(label: "paseo-test"))
        }
    }
}

private func waitForPaseoTestPort(_ port: UInt16) async throws {
    for _ in 0..<100 {
        let ready = await withCheckedContinuation { continuation in
            let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
            let queue = DispatchQueue(label: "paseo-readiness")
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready, .waiting, .failed:
                    connection.stateUpdateHandler = nil
                    connection.cancel()
                    if case .ready = state { continuation.resume(returning: true) }
                    else { continuation.resume(returning: false) }
                default: break
                }
            }
            connection.start(queue: queue)
        }
        if ready { return }
        // Poll an observable listening condition, not a fixed delay used as acceptance evidence.
        try await Task.sleep(for: .milliseconds(10))
    }
    throw LocalBridgeEndToEndError.timedOut
}

private func paseoTestPorts() throws -> [UInt16] {
    var descriptors: [Int32] = []
    defer { descriptors.forEach { Darwin.close($0) } }
    return try (0..<3).map { _ in
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw LocalBridgeEndToEndError.temporaryPortUnavailable }
        descriptors.append(descriptor)
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(descriptor, $0, length) }
        }
        guard bound == 0 else { throw LocalBridgeEndToEndError.temporaryPortUnavailable }
        let named = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        guard named == 0 else { throw LocalBridgeEndToEndError.temporaryPortUnavailable }
        return UInt16(bigEndian: address.sin_port)
    }
}

@MainActor
@Test("关闭监控清理手机卡片，恢复补齐同一会话且不停止插件任务")
func paseoMonitoringToggleReachesPhone() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let ports = try paseoTestPorts()
    let model = BridgeModel(runtimeConfiguration: BridgeRuntimeConfiguration(
        hookPort: ports[0], webSocketPort: ports[1], advertisedHost: "127.0.0.1",
        pairingSecretLoader: { Data(repeating: 15, count: 32) },
        taskPersistence: TaskSnapshotPersistence(fileURL: directory.appendingPathComponent("tasks.json")),
        observesLocalEnvironment: false, startsBackgroundMaintenance: false, usageLoader: { nil },
        paseoIngress: PaseoIngressConfiguration(port: ports[2], token: String(repeating: "b", count: 64))
    ), glmCoordinatorFactory: { handler in
        GLMQuotaCoordinator(keyStore: IntegrationMemoryGLMKeyStore(),
            quotaFetcher: IntegrationSequencedGLMFetcher(results: []),
            scheduler: IntegrationNoopGLMScheduler(), onStateChange: handler)
    })
    var phone: LocalWebSocketClient!
    let process = Process()
    let input = Pipe()
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("integrations/paseo-omp/test/turn-fixture.mjs")
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", fixture.path, String(ports[2]), String(repeating: "b", count: 64)]
    process.standardInput = input
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    defer {
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        phone?.close()
        model.stop()
    }
    try process.run()
    let ready = try output.fileHandleForReading.read(upToCount: 6)
    #expect(ready == Data("ready\n".utf8))
    model.start()
    try await waitForPaseoTestPort(ports[1])
    try await waitForPaseoTestPort(ports[2])
    phone = LocalWebSocketClient(port: ports[1])
    _ = try await nextSnapshot(from: phone) { $0.tasks.isEmpty }
    try input.fileHandleForWriting.write(contentsOf: Data("sync\n".utf8))
    let initial = try await nextSnapshot(from: phone) { $0.tasks.count == 1 }
    let identity = try #require(initial.tasks.first?.id)
    #expect(initial.tasks.first?.lifecycle == .idle)
    model.setPaseoMonitoring(false)
    _ = try await nextSnapshot(from: phone) { $0.tasks.isEmpty }
    #expect(model.paseoStatus == "未启用")
    try input.fileHandleForWriting.write(contentsOf: Data("silent-start\n".utf8))
    model.setPaseoMonitoring(true)
    try await waitForPaseoTestPort(ports[2])
    try input.fileHandleForWriting.write(contentsOf: Data("sync\n".utf8))
    let restored = try await nextSnapshot(from: phone) { $0.tasks.first?.lifecycle == .running }
    #expect(restored.tasks.first?.id == identity)
    #expect(restored.tasks.first?.capabilities.isEmpty == true)
    #expect(model.paseoStatus == "已连接")
    try input.fileHandleForWriting.write(contentsOf: Data("approval\n".utf8))
    let waiting = try await nextSnapshot(from: phone) { $0.tasks.first?.lifecycle == .waitingApproval }
    model.setPaseoMonitoring(false)
    _ = try await nextSnapshot(from: phone) { $0.tasks.isEmpty }
    model.setPaseoMonitoring(true)
    try await waitForPaseoTestPort(ports[2])
    try input.fileHandleForWriting.write(contentsOf: Data("sync\n".utf8))
    let stillWaiting = try await nextSnapshot(from: phone) { $0.tasks.first?.lifecycle == .waitingApproval }
    #expect(stillWaiting.tasks.first?.id == waiting.tasks.first?.id)
    model.setPaseoMonitoring(false)
    _ = try await nextSnapshot(from: phone) { $0.tasks.isEmpty }
    try input.fileHandleForWriting.write(contentsOf: Data("resolve-all\nbarrier\n".utf8))
    let settled = try await Task.detached { try output.fileHandleForReading.read(upToCount: 8) }.value
    #expect(settled == Data("settled\n".utf8))
    model.setPaseoMonitoring(true)
    try await waitForPaseoTestPort(ports[2])
    try input.fileHandleForWriting.write(contentsOf: Data("sync\n".utf8))
    let resolved = try await nextSnapshot(from: phone) { snapshot in
        #expect(!snapshot.tasks.contains { $0.lifecycle == .waitingApproval || $0.lifecycle == .waitingAnswer })
        return snapshot.tasks.first?.lifecycle == .running
    }
    #expect(resolved.tasks.first?.id == identity)
    #expect(resolved.tasks.first?.capabilities.isEmpty == true)
    try input.fileHandleForWriting.write(contentsOf: Data("adapter-restart-empty\n".utf8))
    _ = try await nextSnapshot(from: phone) { $0.tasks.isEmpty }
    #expect(model.paseoStatus == "已连接 · 暂无会话")
    if let capture = ProcessInfo.processInfo.environment["AGENTPAGER_CAPTURE_OMP_CONFIGURATION"] {
        try Data(protocolText([initial, restored, waiting, stillWaiting, resolved]).utf8)
            .write(to: URL(fileURLWithPath: capture))
    }
}


@MainActor
@Test("配置入口启用与关闭可跨 Bridge 重建保留，保留第三方配置并备份")
func paseoConfigurationPersistsThroughBridge() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let daemonConfig = directory.appendingPathComponent("daemon.json")
    let original = Data(#"{"pluginsEnabled":true,"plugins":{"third-party":{"enabled":true}},"providers":{"omp":{"defaultMode":"full"}}}"#.utf8)
    try original.write(to: daemonConfig)
    let integration = PaseoIntegration(
        directory: directory.appendingPathComponent("managed"),
        pluginURL: paseoPluginTestURL, daemonConfigURL: daemonConfig,
        command: { _ in try JSONSerialization.data(withJSONObject: [[
            "id": "agentpager-omp", "path": paseoPluginTestURL.path,
            "enabled": true, "status": "running",
        ]]) }
    )
    let ports = try paseoTestPorts()
    let runtime = BridgeRuntimeConfiguration(hookPort: ports[0], webSocketPort: ports[1],
        pairingSecretLoader: { Data(repeating: 2, count: 32) },
        taskPersistence: TaskSnapshotPersistence(fileURL: directory.appendingPathComponent("tasks.json")),
        observesLocalEnvironment: false, startsBackgroundMaintenance: false, usageLoader: { nil }, paseoIngress: nil)
    let model = BridgeModel(runtimeConfiguration: runtime, paseoIntegration: integration)
    // Configuration is driven through the same Bridge action the settings button uses.
    await model.configurePaseo(.enable)
    let enabled = try #require(try integration.configuration())
    let backups = try FileManager.default.contentsOfDirectory(atPath: integration.backupDirectory.path)
    await model.configurePaseo(.enable)
    #expect(try FileManager.default.contentsOfDirectory(atPath: integration.backupDirectory.path) == backups)
    await model.configurePaseo(.disable)
    #expect(try integration.configuration() == nil)
    let replacement = BridgeModel(runtimeConfiguration: runtime, paseoIntegration: integration)
    await replacement.configurePaseo(.enable)
    #expect(try integration.configuration()?.hostID == enabled.hostID)
    #expect(try integration.configuration()?.token == enabled.token)
    #expect(try Data(contentsOf: daemonConfig) == original)
    #expect(try FileManager.default.contentsOfDirectory(atPath: integration.backupDirectory.path).isEmpty == false)
    let unavailable = PaseoIntegration(directory: integration.directory, pluginURL: integration.pluginURL,
        daemonConfigURL: daemonConfig, command: { _ in throw PaseoIntegration.Failure.unavailable })
    let offlineModel = BridgeModel(runtimeConfiguration: runtime, paseoIntegration: unavailable)
    await offlineModel.configurePaseo(.disable)
    #expect(try integration.configuration() == nil)
    await replacement.configurePaseo(.enable)
    // A replaced registration is no longer ours to remove.
    try Data(#"{"pluginsEnabled":true,"plugins":{"agentpager-omp":{"path":"/third-party","enabled":true}}}"#.utf8).write(to: daemonConfig)
    await replacement.configurePaseo(.revoke)
    #expect(replacement.paseoDiagnostic != nil)
    #expect(try integration.configuration()?.hostID == enabled.hostID)
}

@MainActor
@Test("插件安装返回但未运行时配置入口不能报告成功")
func paseoFailedPluginIsDiagnosed() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let config = directory.appendingPathComponent("daemon.json")
    try Data(#"{"pluginsEnabled":true}"#.utf8).write(to: config)
    let integration = PaseoIntegration(directory: directory.appendingPathComponent("managed"),
        pluginURL: paseoPluginTestURL, daemonConfigURL: config,
        command: { _ in Data("[]".utf8) })
    let model = BridgeModel(runtimeConfiguration: BridgeRuntimeConfiguration(
        observesLocalEnvironment: false, startsBackgroundMaintenance: false, paseoIngress: nil),
        paseoIntegration: integration)
    await model.configurePaseo(.enable)
    #expect(model.paseoDiagnostic != nil)
    #expect(model.paseoStatus != "已连接")
}

private var paseoPluginTestURL: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("integrations/paseo-omp")
}

@MainActor
@Test("Paseo 升级拒绝插件时诊断版本不兼容，不误报连接故障", arguments: [false, true])
func paseoVersionMismatchIsDiagnosed(commandFails: Bool) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let config = directory.appendingPathComponent("daemon.json")
    try Data(#"{"pluginsEnabled":true}"#.utf8).write(to: config)
    let integration = PaseoIntegration(directory: directory.appendingPathComponent("managed"),
        pluginURL: paseoPluginTestURL, daemonConfigURL: config, command: { arguments in
            if commandFails && arguments.prefix(2) != ["plugin", "ls"] {
                throw PaseoIntegration.Failure.unavailable
            }
            return try JSONSerialization.data(withJSONObject: [["id": "agentpager-omp",
                "path": paseoPluginTestURL.path, "enabled": true, "status": "failed",
                "error": "Plugin \"agentpager-omp\" requires Paseo 0.8.0. Your daemon is 0.9.1."]])
        })
    let model = BridgeModel(runtimeConfiguration: BridgeRuntimeConfiguration(
        observesLocalEnvironment: false, startsBackgroundMaintenance: false, paseoIngress: nil),
        paseoIntegration: integration)
    await model.configurePaseo(.enable)
    #expect(model.paseoDiagnostic == "Paseo 版本与监控插件不兼容，请更新 AgentPager Bridge 后恢复接入。")
    #expect(model.paseoStatus != "已连接")
}

@Test("首次启用通过完整插件清单发现未安装项，符合真实 CLI 的不存在行为")
func paseoFirstInstallUsesPluginCatalog() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let config = directory.appendingPathComponent("daemon.json")
    let installed = directory.appendingPathComponent("installed")
    try Data(#"{"pluginsEnabled":true}"#.utf8).write(to: config)
    let integration = PaseoIntegration(directory: directory.appendingPathComponent("managed"),
        pluginURL: paseoPluginTestURL, daemonConfigURL: config, command: { arguments in
            // Paseo 0.8.0 exits 1 for `plugin ls <missing-id>`, but full ls returns [].
            if arguments.prefix(3) == ["plugin", "ls", "agentpager-omp"],
               !FileManager.default.fileExists(atPath: installed.path) {
                throw PaseoIntegration.Failure.unavailable
            }
            if arguments.prefix(2) == ["plugin", "install"] {
                try Data().write(to: installed)
            }
            guard FileManager.default.fileExists(atPath: installed.path) else { return Data("[]".utf8) }
            return try JSONSerialization.data(withJSONObject: [["id": "agentpager-omp",
                "path": paseoPluginTestURL.path, "enabled": true, "status": "running"]])
        })
    #expect(try integration.perform(.enable) != nil)
    #expect(FileManager.default.fileExists(atPath: installed.path))
}

@MainActor
@Test("实际插件关联原生 Codex 来源并通过手机协议撤销，不改变 OMP")
func paseoNativeCodexOriginReachesPhone() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let ports = try paseoTestPorts()
    let model = BridgeModel(runtimeConfiguration: BridgeRuntimeConfiguration(
        hookPort: ports[0], webSocketPort: ports[1], advertisedHost: "127.0.0.1",
        pairingSecretLoader: { Data(repeating: 15, count: 32) },
        taskPersistence: TaskSnapshotPersistence(fileURL: directory.appendingPathComponent("tasks.json")),
        observesLocalEnvironment: false, startsBackgroundMaintenance: false, usageLoader: { nil },
        paseoIngress: PaseoIngressConfiguration(port: ports[2], token: String(repeating: "b", count: 64))
    ), glmCoordinatorFactory: { handler in
        GLMQuotaCoordinator(keyStore: IntegrationMemoryGLMKeyStore(),
            quotaFetcher: IntegrationSequencedGLMFetcher(results: []),
            scheduler: IntegrationNoopGLMScheduler(), onStateChange: handler)
    })
    var phone: LocalWebSocketClient!
    let process = Process()
    let input = Pipe()
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("integrations/paseo-omp/test/turn-fixture.mjs")
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", fixture.path, String(ports[2]), String(repeating: "b", count: 64), "native"]
    process.standardInput = input
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    defer {
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        phone?.close()
        model.stop()
    }
    try process.run()
    let ready = try output.fileHandleForReading.read(upToCount: 6)
    #expect(ready == Data("ready\n".utf8))
    model.start()
    try await waitForPaseoTestPort(ports[1])
    try await waitForPaseoTestPort(ports[2])
    phone = LocalWebSocketClient(port: ports[1])
    _ = try await nextSnapshot(from: phone) { $0.tasks.isEmpty }
    try input.fileHandleForWriting.write(contentsOf: Data("sync\n".utf8))
    let initial = try await nextSnapshot(from: phone) { $0.tasks.count == 1 }
    #expect(initial.tasks.first?.lifecycle == .idle)
    let nativeID = "11111111-1111-4111-8111-111111111111"
    for id in [nativeID, "22222222-2222-4222-8222-222222222222", "standalone-codex"] {
        _ = try await exchangeHook(source: .codex, port: ports[0], payload: [
            "session_id": id, "hook_event_name": "SessionStart", "cwd": "/private/tmp/OriginTest", "source": "cli"])
    }
    let tagged = try await nextSnapshot(from: phone) { $0.tasks.count == 4 && $0.tasks.contains { $0.isPaseoSession } }
    #expect(tagged.tasks.filter(\.isPaseoSession).map(\.id) == [nativeID])
    #expect(tagged.tasks.first { $0.source == .omp }?.isPaseoSession == false)
    try input.fileHandleForWriting.write(contentsOf: Data("archive-native\n".utf8))
    let archived = try await nextSnapshot(from: phone) { $0.tasks.count == 4 && !$0.tasks.contains { $0.isPaseoSession } }
    #expect(archived.tasks.first { $0.id == nativeID }?.lifecycle == tagged.tasks.first { $0.id == nativeID }?.lifecycle)
    try input.fileHandleForWriting.write(contentsOf: Data("native-overflow\n".utf8))
    _ = try await nextSnapshot(from: phone) { $0.tasks.first { $0.source == .omp }?.lifecycle == .running }
    if let capture = ProcessInfo.processInfo.environment["AGENTPAGER_CAPTURE_NATIVE_ORIGIN"] {
        try Data(protocolText([initial, tagged, archived]).utf8).write(to: URL(fileURLWithPath: capture))
    }
}
