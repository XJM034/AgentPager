import Foundation
import Testing
@testable import AgentGridCore

@Test("GLM 启动和重复刷新需要钥匙串授权时只发布状态，不发起交互授权")
func glmBackgroundRefreshNeverRequestsAuthorization() async {
    let store = AuthorizationGLMKeyStore()
    let fetcher = AuthorizationQuotaFetcher()
    let recorder = AuthorizationStateRecorder()
    let coordinator = GLMQuotaCoordinator(
        keyStore: store,
        quotaFetcher: fetcher,
        onStateChange: { await recorder.record($0) }
    )

    await coordinator.start()
    await coordinator.waitUntilIdle()
    for _ in 0..<3 {
        await coordinator.refresh()
        await coordinator.waitUntilIdle()
    }

    #expect(store.authorizationCount == 0)
    #expect(await fetcher.requestCount == 0)
    #expect(await recorder.latest?.keyAccessIssue == .authorizationRequired)
    #expect(await recorder.latest?.credentialStatus == .configured)
    #expect(await recorder.latest?.health == .unavailable)
    #expect(await recorder.latest?.lastSuccessfulAt == nil)
    await coordinator.stop()
}

@Test("一次授权后跨 24 小时十分钟刷新与协调器重启仍读取新额度，不重复授权")
func glmOneAuthorizationSurvivesPollingAndRestart() async {
    let store = AuthorizationGLMKeyStore()
    let fetcher = AuthorizationQuotaFetcher()
    let recorder = AuthorizationStateRecorder()
    let scheduler = AuthorizationScheduler()
    let coordinator = GLMQuotaCoordinator(
        keyStore: store,
        quotaFetcher: fetcher,
        scheduler: scheduler,
        onStateChange: { await recorder.record($0) }
    )
    await coordinator.start()
    await coordinator.waitUntilIdle()
    #expect(await coordinator.authorizeStoredKey())
    #expect(await recorder.latest?.keyAccessIssue == nil)

    for cycle in 1...144 {
        #expect(scheduler.interval == 600)
        scheduler.fire()
        await recorder.waitForUpdates(cycle + 2)
        await coordinator.waitUntilIdle()
        #expect(await recorder.latest?.lastSuccessfulAt == Date(
            timeIntervalSince1970: Double(cycle + 1) * 600
        ))
    }
    await coordinator.stop()

    let restarted = GLMQuotaCoordinator(
        keyStore: store,
        quotaFetcher: fetcher,
        scheduler: scheduler,
        onStateChange: { await recorder.record($0) }
    )
    await restarted.start()
    await restarted.waitUntilIdle()
    #expect(store.authorizationCount == 1)
    #expect(await fetcher.requestCount == 146)
    #expect(await recorder.latest?.health == .available)
    #expect(await recorder.latest?.keyAccessIssue == nil)
    await restarted.stop()
}

@Test(arguments: [true, false])
func glmKeyMutationAuthorizationFailureRemainsActionable(_ saving: Bool) async {
    let store = AuthorizationGLMKeyStore(mutationRequiresAuthorization: true)
    let recorder = AuthorizationStateRecorder()
    let coordinator = GLMQuotaCoordinator(
        keyStore: store,
        quotaFetcher: AuthorizationQuotaFetcher(),
        onStateChange: { await recorder.record($0) }
    )
    let succeeded = saving
        ? await coordinator.saveCandidate("synthetic-candidate")
        : await coordinator.deleteKey()
    #expect(!succeeded)
    #expect(await recorder.latest?.keyAccessIssue == .authorizationRequired)
    #expect(await recorder.latest?.credentialStatus == .configured)
}

@Test(arguments: [GLMKeyAccessError.authorizationRequired, .authorizationNotPersistent])
func glmCancelledOrOneTimeAuthorizationDoesNotResumePollingAsHealthy(
    _ error: GLMKeyAccessError
) async {
    let store = AuthorizationGLMKeyStore(authorizationError: error)
    let recorder = AuthorizationStateRecorder()
    let fetcher = AuthorizationQuotaFetcher()
    let coordinator = GLMQuotaCoordinator(
        keyStore: store, quotaFetcher: fetcher,
        onStateChange: { await recorder.record($0) }
    )
    #expect(!(await coordinator.authorizeStoredKey()))
    #expect(await recorder.latest?.keyAccessIssue == error)
    #expect(await recorder.latest?.lastSuccessfulAt == nil)
    await coordinator.refresh()
    await coordinator.waitUntilIdle()
    #expect(store.authorizationCount == 1)
    #expect(await fetcher.requestCount == 0)
}

@Test("首次保存被取消且未写入 Key 时不能显示已配置或引导读取不存在的 Key")
func glmCancelledFirstSaveRemainsUnconfigured() async {
    let store = AuthorizationGLMKeyStore(mutationRequiresAuthorization: true, hasStoredKey: false)
    let recorder = AuthorizationStateRecorder()
    let coordinator = GLMQuotaCoordinator(
        keyStore: store, quotaFetcher: AuthorizationQuotaFetcher(),
        onStateChange: { await recorder.record($0) }
    )
    #expect(!(await coordinator.saveCandidate("synthetic-candidate")))
    #expect(await recorder.latest?.credentialStatus == .unconfigured)
    #expect(await recorder.latest?.keyAccessIssue == nil)
    #expect(await recorder.latest?.provider == nil)
}

@Test("撤销钥匙串权限后不沿用内存 Key，旧额度标记陈旧且不更新最后成功时间")
func glmRevokedAccessStopsFetchingAndPreservesHonestFreshness() async {
    let store = AuthorizationGLMKeyStore()
    let recorder = AuthorizationStateRecorder()
    let fetcher = AuthorizationQuotaFetcher()
    let coordinator = GLMQuotaCoordinator(
        keyStore: store, quotaFetcher: fetcher,
        onStateChange: { await recorder.record($0) }
    )
    #expect(await coordinator.authorizeStoredKey())
    store.revokeAccess()
    await coordinator.refresh()
    await coordinator.waitUntilIdle()
    #expect(await fetcher.requestCount == 1)
    #expect(store.authorizationCount == 1)
    #expect(await recorder.latest?.keyAccessIssue == .authorizationRequired)
    #expect(await recorder.latest?.health == .stale)
    #expect(await recorder.latest?.provider?.status == "stale_unavailable")
    #expect(await recorder.latest?.lastSuccessfulAt == Date(timeIntervalSince1970: 600))
}

private final class AuthorizationGLMKeyStore: GLMKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var permitted = false
    private var authorizations = 0
    private let mutationRequiresAuthorization: Bool
    private let authorizationError: GLMKeyAccessError?
    private let hasStoredKey: Bool

    init(
        mutationRequiresAuthorization: Bool = false,
        authorizationError: GLMKeyAccessError? = nil,
        hasStoredKey: Bool = true
    ) {
        self.mutationRequiresAuthorization = mutationRequiresAuthorization
        self.authorizationError = authorizationError
        self.hasStoredKey = hasStoredKey
    }

    var authorizationCount: Int { lock.withLock { authorizations } }

    func exists() throws -> Bool { hasStoredKey }

    func load() throws -> String? {
        try lock.withLock {
            guard permitted else { throw GLMKeyAccessError.authorizationRequired }
            return "synthetic-authorization-test-key"
        }
    }

    func authorizeAccess() throws {
        try lock.withLock {
            authorizations += 1
            if let authorizationError { throw authorizationError }
            permitted = true
        }
    }

    func revokeAccess() { lock.withLock { permitted = false } }

    func save(_ key: String) throws {
        if mutationRequiresAuthorization { throw GLMKeyAccessError.authorizationRequired }
    }
    func delete() throws {
        if mutationRequiresAuthorization { throw GLMKeyAccessError.authorizationRequired }
    }
}

private actor AuthorizationQuotaFetcher: GLMQuotaFetching {
    private(set) var requestCount = 0

    func fetchQuota(using key: String) async throws -> UsageProviderSnapshot {
        requestCount += 1
        return UsageProviderSnapshot(
            id: "glm",
            capturedAt: Date(timeIntervalSince1970: Double(requestCount) * 600),
            status: "available"
        )
    }
}

private actor AuthorizationStateRecorder {
    private(set) var latest: GLMQuotaState?
    private var updates = 0
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func record(_ state: GLMQuotaState) {
        latest = state
        updates += 1
        let satisfied = waiters.filter { updates >= $0.0 }
        waiters.removeAll { updates >= $0.0 }
        satisfied.forEach { $0.1.resume() }
    }

    func waitForUpdates(_ count: Int) async {
        if updates >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
}

private final class AuthorizationScheduler: GLMRefreshScheduler, @unchecked Sendable {
    private let lock = NSLock()
    private var storedInterval: TimeInterval?
    private var task: AuthorizationScheduledTask?
    var interval: TimeInterval? { lock.withLock { storedInterval } }

    func schedule(
        after interval: TimeInterval,
        operation: @escaping @Sendable () -> Void
    ) -> any GLMScheduledTask {
        lock.withLock {
            storedInterval = interval
            let task = AuthorizationScheduledTask(operation)
            self.task = task
            return task
        }
    }

    func fire() { lock.withLock { task }?.fire() }
}

private final class AuthorizationScheduledTask: GLMScheduledTask, @unchecked Sendable {
    private let lock = NSLock()
    private var operation: (@Sendable () -> Void)?
    init(_ operation: @escaping @Sendable () -> Void) { self.operation = operation }
    func cancel() { lock.withLock { operation = nil } }
    func fire() {
        let callback = lock.withLock {
            defer { operation = nil }
            return operation
        }
        callback?()
    }
}
