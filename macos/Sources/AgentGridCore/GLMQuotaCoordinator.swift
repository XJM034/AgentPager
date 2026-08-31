import Foundation

public protocol GLMKeyStore: Sendable {
    func exists() throws -> Bool
    /// Background reads must never present system authentication UI.
    func load() throws -> String?
    /// Only call in response to an explicit user action.
    func authorizeAccess() throws
    func save(_ key: String) throws
    func delete() throws
}

public extension GLMKeyStore {
    func exists() throws -> Bool {
        try load() != nil
    }

    func authorizeAccess() throws {
        _ = try load()
    }
}

public enum GLMKeyAccessError: Error, Equatable, Sendable {
    case authorizationRequired
    case authorizationNotPersistent
}

public protocol GLMScheduledTask: Sendable {
    func cancel()
}

public protocol GLMRefreshScheduler: Sendable {
    func schedule(
        after interval: TimeInterval,
        operation: @escaping @Sendable () -> Void
    ) -> any GLMScheduledTask
}

public final class DispatchGLMRefreshScheduler: GLMRefreshScheduler, @unchecked Sendable {
    private let queue: DispatchQueue

    public init(
        queue: DispatchQueue = DispatchQueue(
            label: "com.agentpager.glm-quota-refresh",
            qos: .utility
        )
    ) {
        self.queue = queue
    }

    public func schedule(
        after interval: TimeInterval,
        operation: @escaping @Sendable () -> Void
    ) -> any GLMScheduledTask {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval)
        timer.setEventHandler(handler: operation)
        timer.resume()
        return DispatchGLMScheduledTask(timer: timer)
    }
}

private final class DispatchGLMScheduledTask: GLMScheduledTask, @unchecked Sendable {
    private let timer: DispatchSourceTimer

    init(timer: DispatchSourceTimer) {
        self.timer = timer
    }

    func cancel() {
        timer.cancel()
    }

    deinit {
        timer.cancel()
    }
}

public enum GLMCredentialStatus: String, Equatable, Sendable {
    case unconfigured
    case configured
}

public enum GLMValidationStatus: String, Equatable, Sendable {
    case idle
    case succeeded
    case failed
}

public enum GLMDataHealth: String, Equatable, Sendable {
    case unconfigured
    case available
    case stale
    case authenticationFailed
    case unavailable
    case planExpired
    case exhausted
}

public struct GLMQuotaState: Equatable, Sendable {
    public var credentialStatus: GLMCredentialStatus
    public var keyAccessIssue: GLMKeyAccessError?
    public var validationStatus: GLMValidationStatus
    public var health: GLMDataHealth
    public var failure: GLMQuotaError?
    public var lastSuccessfulAt: Date?
    public var lastUpdatedAt: Date?
    public var provider: UsageProviderSnapshot?

    public init(
        credentialStatus: GLMCredentialStatus,
        keyAccessIssue: GLMKeyAccessError? = nil,
        validationStatus: GLMValidationStatus = .idle,
        health: GLMDataHealth? = nil,
        failure: GLMQuotaError? = nil,
        lastSuccessfulAt: Date? = nil,
        lastUpdatedAt: Date? = nil,
        provider: UsageProviderSnapshot? = nil
    ) {
        self.credentialStatus = credentialStatus
        self.keyAccessIssue = keyAccessIssue
        self.validationStatus = validationStatus
        self.health = health ?? (credentialStatus == .configured ? .unavailable : .unconfigured)
        self.failure = failure
        self.lastSuccessfulAt = lastSuccessfulAt
        self.lastUpdatedAt = lastUpdatedAt
        self.provider = provider
    }
}

public actor GLMQuotaCoordinator {
    public static let pollingInterval: TimeInterval = 600
    public static let maximumBackoffInterval: TimeInterval = 14_400

    private let keyStore: any GLMKeyStore
    private let quotaFetcher: any GLMQuotaFetching
    private let scheduler: any GLMRefreshScheduler
    private let now: @Sendable () -> Date
    private let onStateChange: @Sendable (GLMQuotaState) async -> Void
    private var state = GLMQuotaState(credentialStatus: .unconfigured)
    private var scheduledTask: (any GLMScheduledTask)?
    private var refreshTask: Task<Void, Never>?
    private var requestInFlight = false
    private var started = false
    private var consecutiveFailures = 0
    private var configurationRevision = 0
    private var lastSuccessfulProvider: UsageProviderSnapshot?

    public init(
        keyStore: any GLMKeyStore,
        quotaFetcher: any GLMQuotaFetching,
        scheduler: any GLMRefreshScheduler = DispatchGLMRefreshScheduler(),
        now: @escaping @Sendable () -> Date = Date.init,
        onStateChange: @escaping @Sendable (GLMQuotaState) async -> Void
    ) {
        self.keyStore = keyStore
        self.quotaFetcher = quotaFetcher
        self.scheduler = scheduler
        self.now = now
        self.onStateChange = onStateChange
    }

    public func start() async {
        guard !started else { return }
        started = true
        refresh()
    }

    public func refresh() {
        guard refreshTask == nil, !requestInFlight else { return }
        scheduledTask?.cancel()
        scheduledTask = nil
        let revision = configurationRevision
        refreshTask = Task { [weak self] in
            await self?.performRefresh(revision: revision)
        }
    }

    @discardableResult
    public func authorizeStoredKey() async -> Bool {
        await waitUntilIdle()
        guard !requestInFlight else { return false }
        scheduledTask?.cancel()
        scheduledTask = nil
        do {
            try keyStore.authorizeAccess()
        } catch let issue as GLMKeyAccessError {
            await publishRefreshFailure(
                .unavailable, revision: configurationRevision, keyAccessIssue: issue
            )
            return false
        } catch {
            await publishRefreshFailure(.unavailable, revision: configurationRevision)
            return false
        }
        // Fetch through the normal silent path, rather than retaining an authorized Key in memory.
        refresh()
        await waitUntilIdle()
        return state.keyAccessIssue == nil && state.validationStatus == .succeeded
    }

    @discardableResult
    public func saveCandidate(_ candidate: String) async -> Bool {
        let candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else {
            await publishValidationFailure(.missingFields)
            return false
        }

        if refreshTask != nil {
            await waitUntilIdle()
        }
        guard !requestInFlight else { return false }
        requestInFlight = true

        do {
            let provider = try await quotaFetcher.fetchQuota(using: candidate)
            try keyStore.save(candidate)
            configurationRevision += 1
            requestInFlight = false
            consecutiveFailures = 0
            lastSuccessfulProvider = provider
            let successfulAt = provider.capturedAt ?? now()
            state = GLMQuotaState(
                credentialStatus: .configured,
                validationStatus: .succeeded,
                health: provider.status == "quota_exhausted" ? .exhausted : .available,
                lastSuccessfulAt: successfulAt,
                lastUpdatedAt: now(),
                provider: provider
            )
            await onStateChange(state)
            scheduleNext(after: Self.pollingInterval)
            return true
        } catch let issue as GLMKeyAccessError {
            requestInFlight = false
            if (try? keyStore.exists()) == false {
                await publishValidationFailure(.unavailable)
            } else {
                await publishRefreshFailure(
                    .unavailable, revision: configurationRevision, keyAccessIssue: issue
                )
            }
            return false
        } catch let error as GLMQuotaError {
            requestInFlight = false
            await publishValidationFailure(error)
            return false
        } catch {
            requestInFlight = false
            await publishValidationFailure(.unavailable)
            return false
        }
    }

    public func deleteKey() async -> Bool {
        do {
            try keyStore.delete()
            configurationRevision += 1
            scheduledTask?.cancel()
            scheduledTask = nil
            refreshTask?.cancel()
            refreshTask = nil
            requestInFlight = false
            consecutiveFailures = 0
            lastSuccessfulProvider = nil
            state = GLMQuotaState(
                credentialStatus: .unconfigured,
                health: .unconfigured,
                lastUpdatedAt: now()
            )
            await onStateChange(state)
            return true
        } catch let issue as GLMKeyAccessError {
            await publishRefreshFailure(
                .unavailable, revision: configurationRevision, keyAccessIssue: issue
            )
            return false
        } catch {
            await publishValidationFailure(.unavailable)
            return false
        }
    }

    public func waitUntilIdle() async {
        let task = refreshTask
        await task?.value
    }

    public func stop() {
        scheduledTask?.cancel()
        scheduledTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        requestInFlight = false
        configurationRevision += 1
        started = false
    }

    private func performRefresh(revision: Int) async {
        defer { refreshTask = nil }
        guard !requestInFlight else { return }
        let key: String?
        do {
            key = try keyStore.load()
        } catch let issue as GLMKeyAccessError {
            await publishRefreshFailure(.unavailable, revision: revision, keyAccessIssue: issue)
            return
        } catch {
            await publishRefreshFailure(.unavailable, revision: revision)
            return
        }

        guard let key, !key.isEmpty else {
            guard revision == configurationRevision else { return }
            consecutiveFailures = 0
            lastSuccessfulProvider = nil
            state = GLMQuotaState(
                credentialStatus: .unconfigured,
                health: .unconfigured,
                lastUpdatedAt: now()
            )
            await onStateChange(state)
            scheduleNext(after: Self.pollingInterval)
            return
        }

        requestInFlight = true
        do {
            let provider = try await quotaFetcher.fetchQuota(using: key)
            guard revision == configurationRevision, !Task.isCancelled else {
                requestInFlight = false
                return
            }
            consecutiveFailures = 0
            lastSuccessfulProvider = provider
            let successfulAt = provider.capturedAt ?? now()
            state = GLMQuotaState(
                credentialStatus: .configured,
                validationStatus: .succeeded,
                health: provider.status == "quota_exhausted" ? .exhausted : .available,
                lastSuccessfulAt: successfulAt,
                lastUpdatedAt: now(),
                provider: provider
            )
            requestInFlight = false
            await onStateChange(state)
            scheduleNext(after: Self.pollingInterval)
        } catch is CancellationError {
            requestInFlight = false
        } catch let error as GLMQuotaError {
            requestInFlight = false
            await publishRefreshFailure(error, revision: revision)
        } catch {
            requestInFlight = false
            await publishRefreshFailure(.unavailable, revision: revision)
        }
    }

    private func publishValidationFailure(_ error: GLMQuotaError) async {
        // A locked/inaccessible keychain must not be misreported as an absent Key.
        let hasStoredKey = (try? keyStore.exists()) ?? (state.credentialStatus == .configured)
        state = GLMQuotaState(
            credentialStatus: hasStoredKey ? .configured : .unconfigured,
            keyAccessIssue: hasStoredKey ? state.keyAccessIssue : nil,
            validationStatus: .failed,
            health: hasStoredKey ? state.health : .unconfigured,
            failure: error,
            lastSuccessfulAt: state.lastSuccessfulAt,
            lastUpdatedAt: now(),
            provider: state.provider
        )
        await onStateChange(state)
        scheduleNext(after: hasStoredKey ? backoffInterval() : Self.pollingInterval)
    }

    private func publishRefreshFailure(
        _ error: GLMQuotaError,
        revision: Int,
        keyAccessIssue: GLMKeyAccessError? = nil
    ) async {
        guard revision == configurationRevision, !Task.isCancelled else { return }
        if keyAccessIssue == nil { consecutiveFailures += 1 }
        let updatedAt = now()
        let failurePresentation = error.failurePresentation
        let trusted = failurePresentation.retainsTrustedQuota
            ? lastSuccessfulProvider
            : nil
        let health = failurePresentation.health(hasTrustedQuota: trusted != nil)
        let provider = UsageProviderSnapshot(
            id: "glm",
            displayName: "GLM",
            planName: lastSuccessfulProvider?.planName ?? "GLM Coding Plan",
            planLevel: lastSuccessfulProvider?.planLevel,
            capturedAt: updatedAt,
            status: failurePresentation.providerStatus(hasTrustedQuota: trusted != nil),
            quotaGroups: trusted?.quotaGroups ?? []
        )
        state = GLMQuotaState(
            credentialStatus: .configured,
            keyAccessIssue: keyAccessIssue,
            validationStatus: .failed,
            health: health,
            failure: error,
            lastSuccessfulAt: lastSuccessfulProvider?.capturedAt,
            lastUpdatedAt: updatedAt,
            provider: provider
        )
        await onStateChange(state)
        scheduleNext(after: keyAccessIssue == nil ? backoffInterval() : Self.pollingInterval)
    }

    private func backoffInterval() -> TimeInterval {
        let exponent = min(consecutiveFailures, 10)
        let multiplier = pow(2.0, Double(exponent))
        return min(Self.pollingInterval * multiplier, Self.maximumBackoffInterval)
    }

    private func scheduleNext(after interval: TimeInterval) {
        guard started else { return }
        scheduledTask?.cancel()
        scheduledTask = scheduler.schedule(after: interval) { [weak self] in
            Task { await self?.scheduledRefreshFired() }
        }
    }

    private func scheduledRefreshFired() {
        scheduledTask = nil
        refresh()
    }
}

private extension GLMQuotaError {
    var failurePresentation: GLMFailurePresentation {
        switch self {
        case .unauthorized:
            GLMFailurePresentation(
                status: "auth_unauthorized",
                retention: .historical,
                healthPolicy: .authenticationFailed
            )
        case .forbidden:
            GLMFailurePresentation(
                status: "auth_forbidden",
                retention: .historical,
                healthPolicy: .authenticationFailed
            )
        case .rateLimited:
            GLMFailurePresentation(status: "rate_limited", retention: .stale)
        case .planExpired:
            GLMFailurePresentation(
                status: "plan_expired",
                retention: .none,
                healthPolicy: .planExpired
            )
        case .quotaExhausted:
            GLMFailurePresentation(
                status: "quota_exhausted",
                retention: .none,
                healthPolicy: .exhausted
            )
        case .timedOut:
            GLMFailurePresentation(status: "timeout", retention: .stale)
        case .serverUnavailable:
            GLMFailurePresentation(status: "server_error", retention: .stale)
        case .nonJSON:
            GLMFailurePresentation(status: "non_json", retention: .stale)
        case .missingFields:
            GLMFailurePresentation(status: "missing_fields", retention: .stale)
        case .unknownSchema, .invalidData:
            GLMFailurePresentation(status: "unknown_schema", retention: .stale)
        case .invalidHTTPResponse, .unavailable:
            GLMFailurePresentation(status: "unavailable", retention: .stale)
        }
    }
}

private enum GLMTrustedQuotaRetention {
    case none
    case stale
    case historical
}

private enum GLMFailureHealthPolicy {
    case transient
    case authenticationFailed
    case planExpired
    case exhausted

    func health(hasTrustedQuota: Bool) -> GLMDataHealth {
        switch self {
        case .transient:
            hasTrustedQuota ? .stale : .unavailable
        case .authenticationFailed:
            .authenticationFailed
        case .planExpired:
            .planExpired
        case .exhausted:
            .exhausted
        }
    }
}

private struct GLMFailurePresentation {
    var status: String
    var retention: GLMTrustedQuotaRetention
    var healthPolicy: GLMFailureHealthPolicy = .transient

    var retainsTrustedQuota: Bool { retention != .none }

    func health(hasTrustedQuota: Bool) -> GLMDataHealth {
        healthPolicy.health(hasTrustedQuota: hasTrustedQuota)
    }

    func providerStatus(hasTrustedQuota: Bool) -> String {
        guard hasTrustedQuota, retention == .stale else { return status }
        return "stale_\(status)"
    }
}
