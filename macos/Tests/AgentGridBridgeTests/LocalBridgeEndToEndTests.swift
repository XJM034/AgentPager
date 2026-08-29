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
        snapshot.usage?.quotaGroups.map(\.id) == ["codex", "codex_bengalfox"]
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
            snapshot.usage?.quotaGroups.map(\.id) == ["codex", "codex_bengalfox"]
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
    #expect(available.usage?.quotaGroups.map(\.id) == ["codex", "codex_bengalfox"])
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
    #expect(deleted.usage?.quotaGroups.map(\.id) == ["codex", "codex_bengalfox"])
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
            QuotaGroup(
                id: "codex_bengalfox",
                name: "SPARK",
                capturedAt: capturedAt,
                windows: []
            ),
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
