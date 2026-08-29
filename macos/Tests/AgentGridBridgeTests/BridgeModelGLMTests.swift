import AgentGridCore
import Foundation
import Network
import Testing
@testable import AgentGridBridge

@MainActor
@Test("BridgeModel 启动、手机连接和手动入口接入同一 GLM 协调器")
func bridgeModelWiresGLMRefreshTriggers() async {
    let coordinator = BridgeGLMCoordinatorSpy()
    let model = BridgeModel(
        glmCoordinatorFactory: { _ in coordinator }
    )

    model.startGLMQuotaMonitoring()
    await coordinator.waitFor(startCount: 1, refreshCount: 0)

    model.updatePhoneCount(1)
    await coordinator.waitFor(startCount: 1, refreshCount: 1)

    model.refreshGLMQuota()
    await coordinator.waitFor(startCount: 1, refreshCount: 2)
    await waitUntil { !model.glmOperationInProgress }

    model.updatePhoneCount(0)
    model.updatePhoneCount(1)
    await coordinator.waitFor(startCount: 1, refreshCount: 3)
}

@MainActor
@Test("验证后的 Key 不进入 BridgeModel 日志、共享快照或任务持久化")
func validatedKeyDoesNotLeaveBridgeModel() async throws {
    let keyStore = BridgeMemoryGLMKeyStore()
    let quotaFetcher = BridgeSuccessfulGLMFetcher()
    let snapshots = BridgeSnapshotRecorder()
    let syntheticKey = "test-only-bridge-secret"
    let model = BridgeModel(
        glmCoordinatorFactory: { stateHandler in
            GLMQuotaCoordinator(
                keyStore: keyStore,
                quotaFetcher: quotaFetcher,
                scheduler: BridgeNoopGLMScheduler(),
                onStateChange: stateHandler
            )
        },
        snapshotObserver: { text in
            snapshots.record(text)
        }
    )

    model.saveGLMKey(syntheticKey)
    await waitUntil {
        !model.glmOperationInProgress && model.glmValidationStatus == .succeeded
    }

    #expect((try? keyStore.load()) == syntheticKey)
    #expect(model.glmCredentialStatus == .configured)
    #expect(model.glmProvider?.id == "glm")
    #expect(model.recentEvents == ["GLM 额度已刷新"])
    #expect(!model.recentEvents.joined().contains(syntheticKey))
    #expect(!snapshots.joined.contains(syntheticKey))
    #expect(!snapshots.joined.localizedCaseInsensitiveContains("authorization"))
    #expect(!snapshots.joined.localizedCaseInsensitiveContains("cookie"))

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let persistence = TaskSnapshotPersistence(
        fileURL: directory.appendingPathComponent("tasks.json")
    )
    try persistence.save(model.tasks)
    let persisted = try String(contentsOf: persistence.fileURL, encoding: .utf8)
    #expect(!persisted.contains(syntheticKey))
}

@MainActor
@Test("BridgeModel 阻塞中的 GLM 查询不阻塞真实 Hook 与 WebSocket 服务")
func blockedGLMQueryDoesNotBlockHookOrWebSocket() async throws {
    let quota = BridgeBlockingGLMFetcher()
    let coordinatorBox = BridgeGLMCoordinatorBox()
    let model = BridgeModel(
        glmCoordinatorFactory: { stateHandler in
            let coordinator = GLMQuotaCoordinator(
                keyStore: BridgeConfiguredGLMKeyStore(),
                quotaFetcher: quota,
                scheduler: BridgeNoopGLMScheduler(),
                onStateChange: stateHandler
            )
            coordinatorBox.store(coordinator)
            return coordinator
        }
    )
    model.startGLMQuotaMonitoring()
    await quota.waitUntilStarted()

    let hookReceived = BridgeAsyncSignal()
    let hookServer = HookBridgeServer { _ in
        Task { await hookReceived.signal() }
    }
    let webSocketServer = WebSocketServer(
        messageHandler: { _ in },
        countHandler: { _ in }
    )
    try hookServer.start(port: 49_384)
    try webSocketServer.start(port: 49_385)
    defer {
        hookServer.stop()
        webSocketServer.stop()
    }

    try sendBridgeZCodeHook(
        [
            "session_id": "zcode-glm-nonblocking",
            "hook_event_name": "SessionStart",
            "cwd": "/private/work/AgentPager",
        ],
        port: 49_384
    )
    await hookReceived.wait()

    let broadcastStartedAt = Date()
    webSocketServer.broadcast(#"{"type":"state.snapshot"}"#)
    #expect(Date().timeIntervalSince(broadcastStartedAt) < 0.1)

    await quota.release()
    await coordinatorBox.waitUntilIdle()
}

@MainActor
private func waitUntil(
    timeout: Duration = .seconds(2),
    _ condition: @MainActor () -> Bool
) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition(), clock.now < deadline {
        await Task.yield()
    }
    #expect(condition())
}

private actor BridgeGLMCoordinatorSpy: GLMQuotaCoordinating {
    private var startCount = 0
    private var refreshCount = 0
    private var waiters: [(
        startCount: Int,
        refreshCount: Int,
        continuation: CheckedContinuation<Void, Never>
    )] = []

    func start() {
        startCount += 1
        resumeSatisfiedWaiters()
    }

    func refresh() {
        refreshCount += 1
        resumeSatisfiedWaiters()
    }

    func waitUntilIdle() {}

    func saveCandidate(_ candidate: String) -> Bool { true }

    func deleteKey() -> Bool { true }

    func waitFor(startCount: Int, refreshCount: Int) async {
        if self.startCount >= startCount, self.refreshCount >= refreshCount {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append((startCount, refreshCount, continuation))
        }
    }

    private func resumeSatisfiedWaiters() {
        let satisfied = waiters.filter {
            startCount >= $0.startCount && refreshCount >= $0.refreshCount
        }
        waiters.removeAll {
            startCount >= $0.startCount && refreshCount >= $0.refreshCount
        }
        satisfied.forEach { $0.continuation.resume() }
    }
}

private final class BridgeMemoryGLMKeyStore: GLMKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var key: String?

    func load() throws -> String? {
        lock.withLock { key }
    }

    func save(_ key: String) throws {
        lock.withLock { self.key = key }
    }

    func delete() throws {
        lock.withLock { key = nil }
    }
}

private final class BridgeConfiguredGLMKeyStore: GLMKeyStore, @unchecked Sendable {
    func load() throws -> String? { "integration-test-key" }
    func save(_ key: String) throws {}
    func delete() throws {}
}

private actor BridgeSuccessfulGLMFetcher: GLMQuotaFetching {
    func fetchQuota(using key: String) async throws -> UsageProviderSnapshot {
        UsageProviderSnapshot(
            id: "glm",
            displayName: "GLM",
            planName: "GLM Coding Plan",
            capturedAt: Date(timeIntervalSince1970: 1_785_067_200),
            quotaGroups: [
                QuotaGroup(
                    id: "credit-limit",
                    name: nil,
                    capturedAt: Date(timeIntervalSince1970: 1_785_067_200),
                    windows: []
                ),
            ]
        )
    }
}

private actor BridgeBlockingGLMFetcher: GLMQuotaFetching {
    private var startedWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private var started = false

    func fetchQuota(using key: String) async throws -> UsageProviderSnapshot {
        started = true
        startedWaiter?.resume()
        startedWaiter = nil
        await withCheckedContinuation { continuation in
            releaseWaiter = continuation
        }
        return UsageProviderSnapshot(id: "glm")
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { continuation in
            startedWaiter = continuation
        }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

private actor BridgeAsyncSignal {
    private var signaled = false
    private var waiter: CheckedContinuation<Void, Never>?

    func signal() {
        signaled = true
        waiter?.resume()
        waiter = nil
    }

    func wait() async {
        if signaled { return }
        await withCheckedContinuation { continuation in
            waiter = continuation
        }
    }
}

private final class BridgeGLMCoordinatorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var coordinator: (any GLMQuotaCoordinating)?

    func store(_ coordinator: any GLMQuotaCoordinating) {
        lock.withLock {
            self.coordinator = coordinator
        }
    }

    func waitUntilIdle() async {
        let coordinator = lock.withLock { coordinator }
        await coordinator?.waitUntilIdle()
    }
}

@MainActor
private final class BridgeSnapshotRecorder {
    private var snapshots: [String] = []

    var joined: String { snapshots.joined(separator: "\n") }

    func record(_ text: String) {
        snapshots.append(text)
    }
}

private final class BridgeNoopGLMScheduler: GLMRefreshScheduler, @unchecked Sendable {
    func schedule(
        every interval: TimeInterval,
        operation: @escaping @Sendable () -> Void
    ) -> any GLMScheduledTask {
        BridgeNoopGLMScheduledTask()
    }
}

private final class BridgeNoopGLMScheduledTask: GLMScheduledTask, @unchecked Sendable {
    func cancel() {}
}

private func sendBridgeZCodeHook(
    _ payload: [String: Any],
    port: UInt16
) throws {
    var encodedLine = try JSONSerialization.data(withJSONObject: [
        "hook_source": "zcode",
        "payload": payload,
    ])
    encodedLine.append(UInt8(ascii: "\n"))
    let line = encodedLine

    let connection = NWConnection(
        host: "127.0.0.1",
        port: NWEndpoint.Port(rawValue: port)!,
        using: .tcp
    )
    let finished = DispatchSemaphore(value: 0)
    connection.stateUpdateHandler = { state in
        switch state {
        case .ready:
            connection.send(content: line, completion: .contentProcessed { error in
                guard error == nil else {
                    finished.signal()
                    return
                }
                connection.receiveMessage { _, _, _, _ in
                    finished.signal()
                }
            })
        case .failed, .cancelled:
            finished.signal()
        default:
            break
        }
    }
    connection.start(queue: DispatchQueue(label: "bridge-glm-hook-test-client"))
    let result = finished.wait(timeout: .now() + 2)
    connection.cancel()
    #expect(result == .success)
}
