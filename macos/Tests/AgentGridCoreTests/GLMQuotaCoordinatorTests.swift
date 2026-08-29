import Foundation
import Testing
@testable import AgentGridCore

@Test("未配置 GLM Key 时启动不查询也不发布空 provider")
func unconfiguredGLMDoesNotQueryOrPublishProvider() async {
    let keyStore = MemoryGLMKeyStore()
    let quota = CountingGLMQuotaFetcher()
    let scheduler = RecordingGLMScheduler()
    let states = GLMStateRecorder()
    let coordinator = GLMQuotaCoordinator(
        keyStore: keyStore,
        quotaFetcher: quota,
        scheduler: scheduler,
        onStateChange: { state in
            await states.record(state)
        }
    )

    await coordinator.start()
    await coordinator.waitUntilIdle()

    #expect(await quota.requestCount == 0)
    #expect(scheduler.interval == 600)
    #expect(await states.latest?.credentialStatus == .unconfigured)
    #expect(await states.latest?.provider == nil)
}

@Test("无效候选 GLM Key 不覆盖已有有效 Key")
func invalidCandidateGLMKeyDoesNotReplaceStoredKey() async {
    let keyStore = MemoryGLMKeyStore(key: "stored-key")
    let quota = RejectingGLMQuotaFetcher()
    let states = GLMStateRecorder()
    let coordinator = GLMQuotaCoordinator(
        keyStore: keyStore,
        quotaFetcher: quota,
        scheduler: RecordingGLMScheduler(),
        onStateChange: { state in
            await states.record(state)
        }
    )

    let saved = await coordinator.saveCandidate("invalid-candidate")

    #expect(!saved)
    #expect((try? keyStore.load()) == "stored-key")
    #expect(await states.latest?.credentialStatus == .configured)
    #expect(await states.latest?.validationStatus == .failed)
}

@Test("启动手机连接手动和十分钟轮询触发 GLM 且重叠刷新合并")
func glmRefreshTriggersAreSingleFlightAndNonBlocking() async {
    let keyStore = MemoryGLMKeyStore(key: "stored-key")
    let quota = BlockingFirstGLMQuotaFetcher()
    let scheduler = RecordingGLMScheduler()
    let coordinator = GLMQuotaCoordinator(
        keyStore: keyStore,
        quotaFetcher: quota,
        scheduler: scheduler,
        onStateChange: { _ in }
    )

    await coordinator.start()
    await quota.waitForRequestCount(1)

    await coordinator.refresh()
    await coordinator.refresh()
    scheduler.fire()
    #expect(await quota.requestCount == 1)

    await quota.releaseFirstRequest()
    await coordinator.waitUntilIdle()

    await coordinator.refresh()
    await coordinator.waitUntilIdle()
    await coordinator.refresh()
    await coordinator.waitUntilIdle()
    scheduler.fire()
    await quota.waitForRequestCount(4)
    await coordinator.waitUntilIdle()

    #expect(await quota.requestCount == 4)
}

@Test("自动刷新完成前删除 Key 最终保持未配置且不再查询")
func deletingKeyDuringRefreshFinishesUnconfigured() async {
    let keyStore = MemoryGLMKeyStore(key: "stored-key")
    let quota = BlockingFirstGLMQuotaFetcher()
    let states = GLMStateRecorder()
    let coordinator = GLMQuotaCoordinator(
        keyStore: keyStore,
        quotaFetcher: quota,
        scheduler: RecordingGLMScheduler(),
        onStateChange: { state in
            await states.record(state)
        }
    )
    await coordinator.start()
    await quota.waitForRequestCount(1)

    async let deleted = coordinator.deleteKey()
    await quota.releaseFirstRequest()

    #expect(await deleted)
    #expect((try? keyStore.load()) == nil)
    #expect(await states.latest?.credentialStatus == .unconfigured)
    #expect(await states.latest?.provider == nil)

    await coordinator.refresh()
    await coordinator.waitUntilIdle()
    #expect(await quota.requestCount == 1)
}

@Test("验证后的 Key 只进入 KeyStore 不进入共享快照")
func validatedKeyDoesNotEnterSharedSnapshot() async throws {
    let keyStore = MemoryGLMKeyStore()
    let quota = CountingGLMQuotaFetcher()
    let states = GLMStateRecorder()
    let coordinator = GLMQuotaCoordinator(
        keyStore: keyStore,
        quotaFetcher: quota,
        scheduler: RecordingGLMScheduler(),
        onStateChange: { state in
            await states.record(state)
        }
    )
    let syntheticKey = "test-only-secret-value"

    #expect(await coordinator.saveCandidate(syntheticKey))
    let provider = try #require(await states.latest?.provider)
    let payload = StateSnapshotPayload(
        tasks: [],
        usage: nil,
        usageProviders: [provider],
        focusedTaskID: nil
    )
    let encoded = try ProtocolCodec.encode(payload)
    let text = try #require(String(data: encoded, encoding: .utf8))

    #expect((try? keyStore.load()) == syntheticKey)
    #expect(!text.contains(syntheticKey))
    #expect(!text.localizedCaseInsensitiveContains("authorization"))
    #expect(!text.localizedCaseInsensitiveContains("cookie"))

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let persistence = TaskSnapshotPersistence(
        fileURL: directory.appendingPathComponent("tasks.json")
    )
    try persistence.save(payload.tasks)
    let persisted = try String(contentsOf: persistence.fileURL, encoding: .utf8)
    #expect(!persisted.contains(syntheticKey))
}

@Test("临时失败保留最后可信读数并指数退避，成功后恢复正常刷新")
func temporaryFailureKeepsTrustedQuotaAndRecoversPollingInterval() async throws {
    let capturedAt = Date(timeIntervalSince1970: 1_787_900_134)
    let first = UsageProviderSnapshot(
        id: "glm",
        planName: "GLM Coding Plan",
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
                        usedPercentage: 15,
                        remainingPercentage: 85,
                        windowMinutes: 300,
                        resetsAt: nil,
                        remainingAmount: 1_700
                    ),
                ]
            ),
        ]
    )
    let quota = SequencedGLMQuotaFetcher(results: [
        .success(first),
        .failure(.timedOut),
        .success(first),
    ])
    let scheduler = RecordingGLMScheduler()
    let states = GLMStateRecorder()
    let updatedAt = Date(timeIntervalSince1970: 1_787_900_200)
    let coordinator = GLMQuotaCoordinator(
        keyStore: MemoryGLMKeyStore(key: "stored-key"),
        quotaFetcher: quota,
        scheduler: scheduler,
        now: { updatedAt },
        onStateChange: { state in await states.record(state) }
    )

    await coordinator.start()
    await coordinator.waitUntilIdle()
    #expect(await states.latest?.health == .available)
    #expect(scheduler.interval == 600)

    await coordinator.refresh()
    await coordinator.waitUntilIdle()
    let stale = try #require(await states.latest)
    #expect(stale.health == .stale)
    #expect(stale.failure == .timedOut)
    #expect(stale.lastSuccessfulAt == capturedAt)
    #expect(stale.provider?.status == "stale_timeout")
    #expect(stale.provider?.quotaGroups.single?.windows.single?.remainingAmount == 1_700)
    #expect(scheduler.interval == 1_200)

    await coordinator.refresh()
    await coordinator.waitUntilIdle()
    #expect(await states.latest?.health == .available)
    #expect(await states.latest?.failure == nil)
    #expect(scheduler.interval == 600)
}

@Test(arguments: [
    (GLMQuotaError.unauthorized, GLMDataHealth.authenticationFailed, "auth_unauthorized"),
    (GLMQuotaError.forbidden, GLMDataHealth.authenticationFailed, "auth_forbidden"),
    (GLMQuotaError.planExpired, GLMDataHealth.planExpired, "plan_expired"),
    (GLMQuotaError.unknownSchema, GLMDataHealth.unavailable, "unknown_schema"),
])
func firstFailurePublishesHonestEmptyState(
    _ error: GLMQuotaError,
    _ expectedHealth: GLMDataHealth,
    _ expectedStatus: String
) async throws {
    let states = GLMStateRecorder()
    let coordinator = GLMQuotaCoordinator(
        keyStore: MemoryGLMKeyStore(key: "stored-key"),
        quotaFetcher: SequencedGLMQuotaFetcher(results: [.failure(error)]),
        scheduler: RecordingGLMScheduler(),
        onStateChange: { state in await states.record(state) }
    )

    await coordinator.start()
    await coordinator.waitUntilIdle()

    let state = try #require(await states.latest)
    #expect(state.health == expectedHealth)
    #expect(state.failure == error)
    #expect(state.provider?.status == expectedStatus)
    #expect(state.provider?.quotaGroups.isEmpty == true)
    #expect(state.lastSuccessfulAt == nil)
}

@Test(arguments: [
    (GLMQuotaError.unknownSchema, GLMDataHealth.stale, "stale_unknown_schema"),
    (GLMQuotaError.missingFields, GLMDataHealth.stale, "stale_missing_fields"),
    (GLMQuotaError.unauthorized, GLMDataHealth.authenticationFailed, "auth_unauthorized"),
])
func schemaAndAuthenticationFailuresKeepLastTrustedReading(
    _ error: GLMQuotaError,
    _ expectedHealth: GLMDataHealth,
    _ expectedStatus: String
) async throws {
    let capturedAt = Date(timeIntervalSince1970: 1_787_900_134)
    let trusted = UsageProviderSnapshot(
        id: "glm",
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
                        usedPercentage: 15,
                        remainingPercentage: 85,
                        windowMinutes: 300,
                        resetsAt: nil,
                        remainingAmount: 1_700
                    ),
                ]
            ),
        ]
    )
    let states = GLMStateRecorder()
    let coordinator = GLMQuotaCoordinator(
        keyStore: MemoryGLMKeyStore(key: "stored-key"),
        quotaFetcher: SequencedGLMQuotaFetcher(results: [.success(trusted), .failure(error)]),
        scheduler: RecordingGLMScheduler(),
        onStateChange: { state in await states.record(state) }
    )

    await coordinator.start()
    await coordinator.waitUntilIdle()
    await coordinator.refresh()
    await coordinator.waitUntilIdle()

    let state = try #require(await states.latest)
    #expect(state.health == expectedHealth)
    #expect(state.provider?.status == expectedStatus)
    #expect(state.provider?.quotaGroups.single?.windows.single?.remainingAmount == 1_700)
    #expect(state.lastSuccessfulAt == capturedAt)
}

@Test("删除 Key 立即发布未启用且已取消请求不能恢复旧数据")
func deletingKeyImmediatelyClearsQuotaAndIgnoresCancelledRequest() async {
    let keyStore = MemoryGLMKeyStore(key: "stored-key")
    let quota = BlockingFirstGLMQuotaFetcher()
    let states = GLMStateRecorder()
    let coordinator = GLMQuotaCoordinator(
        keyStore: keyStore,
        quotaFetcher: quota,
        scheduler: RecordingGLMScheduler(),
        onStateChange: { state in await states.record(state) }
    )
    await coordinator.start()
    await quota.waitForRequestCount(1)

    #expect(await coordinator.deleteKey())
    #expect((try? keyStore.load()) == nil)
    #expect(await states.latest?.health == .unconfigured)
    #expect(await states.latest?.provider == nil)

    await quota.releaseFirstRequest()
    await Task.yield()
    #expect(await states.latest?.health == .unconfigured)
    #expect(await states.latest?.provider == nil)
}

private final class MemoryGLMKeyStore: GLMKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var key: String?

    init(key: String? = nil) {
        self.key = key
    }

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

private actor CountingGLMQuotaFetcher: GLMQuotaFetching {
    private(set) var requestCount = 0

    func fetchQuota(using key: String) async throws -> UsageProviderSnapshot {
        requestCount += 1
        return UsageProviderSnapshot(id: "glm")
    }
}

private actor RejectingGLMQuotaFetcher: GLMQuotaFetching {
    func fetchQuota(using key: String) async throws -> UsageProviderSnapshot {
        throw GLMQuotaError.unauthorized
    }
}

private actor BlockingFirstGLMQuotaFetcher: GLMQuotaFetching {
    private(set) var requestCount = 0
    private var firstRequestContinuation: CheckedContinuation<Void, Never>?
    private var countWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func fetchQuota(using key: String) async throws -> UsageProviderSnapshot {
        requestCount += 1
        resumeSatisfiedCountWaiters()
        if requestCount == 1 {
            await withCheckedContinuation { continuation in
                firstRequestContinuation = continuation
            }
        }
        return UsageProviderSnapshot(
            id: "glm",
            quotaGroups: [QuotaGroup(id: "credit", name: nil, capturedAt: nil, windows: [])]
        )
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

private actor SequencedGLMQuotaFetcher: GLMQuotaFetching {
    private var results: [Result<UsageProviderSnapshot, GLMQuotaError>]

    init(results: [Result<UsageProviderSnapshot, GLMQuotaError>]) {
        self.results = results
    }

    func fetchQuota(using key: String) async throws -> UsageProviderSnapshot {
        guard !results.isEmpty else { throw GLMQuotaError.unavailable }
        return try results.removeFirst().get()
    }
}

private final class RecordingGLMScheduler: GLMRefreshScheduler, @unchecked Sendable {
    private let lock = NSLock()
    private var storedInterval: TimeInterval?
    private var operation: (@Sendable () -> Void)?

    var interval: TimeInterval? {
        lock.withLock { storedInterval }
    }

    func schedule(
        after interval: TimeInterval,
        operation: @escaping @Sendable () -> Void
    ) -> any GLMScheduledTask {
        lock.withLock {
            storedInterval = interval
            self.operation = operation
        }
        return NoopGLMScheduledTask()
    }

    func fire() {
        lock.withLock { operation }?()
    }
}

private final class NoopGLMScheduledTask: GLMScheduledTask, @unchecked Sendable {
    func cancel() {}
}

private actor GLMStateRecorder {
    private(set) var latest: GLMQuotaState?

    func record(_ state: GLMQuotaState) {
        latest = state
    }
}
