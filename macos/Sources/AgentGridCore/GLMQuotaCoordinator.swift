import Foundation

public protocol GLMKeyStore: Sendable {
    func exists() throws -> Bool
    func load() throws -> String?
    func save(_ key: String) throws
    func delete() throws
}

public extension GLMKeyStore {
    func exists() throws -> Bool {
        try load() != nil
    }
}

public protocol GLMScheduledTask: Sendable {
    func cancel()
}

public protocol GLMRefreshScheduler: Sendable {
    func schedule(
        every interval: TimeInterval,
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
        every interval: TimeInterval,
        operation: @escaping @Sendable () -> Void
    ) -> any GLMScheduledTask {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
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

public struct GLMQuotaState: Equatable, Sendable {
    public var credentialStatus: GLMCredentialStatus
    public var validationStatus: GLMValidationStatus
    public var provider: UsageProviderSnapshot?

    public init(
        credentialStatus: GLMCredentialStatus,
        validationStatus: GLMValidationStatus = .idle,
        provider: UsageProviderSnapshot? = nil
    ) {
        self.credentialStatus = credentialStatus
        self.validationStatus = validationStatus
        self.provider = provider
    }
}

public actor GLMQuotaCoordinator {
    public static let pollingInterval: TimeInterval = 600

    private let keyStore: any GLMKeyStore
    private let quotaFetcher: any GLMQuotaFetching
    private let scheduler: any GLMRefreshScheduler
    private let onStateChange: @Sendable (GLMQuotaState) async -> Void
    private var state = GLMQuotaState(credentialStatus: .unconfigured)
    private var scheduledTask: (any GLMScheduledTask)?
    private var refreshTask: Task<Void, Never>?
    private var requestInFlight = false
    private var started = false

    public init(
        keyStore: any GLMKeyStore,
        quotaFetcher: any GLMQuotaFetching,
        scheduler: any GLMRefreshScheduler = DispatchGLMRefreshScheduler(),
        onStateChange: @escaping @Sendable (GLMQuotaState) async -> Void
    ) {
        self.keyStore = keyStore
        self.quotaFetcher = quotaFetcher
        self.scheduler = scheduler
        self.onStateChange = onStateChange
    }

    public func start() async {
        guard !started else { return }
        started = true
        scheduledTask = scheduler.schedule(every: Self.pollingInterval) { [weak self] in
            Task {
                await self?.refresh()
            }
        }
        refresh()
    }

    public func refresh() {
        guard refreshTask == nil, !requestInFlight else { return }
        refreshTask = Task { [weak self] in
            await self?.performRefresh()
        }
    }

    @discardableResult
    public func saveCandidate(_ candidate: String) async -> Bool {
        let candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else {
            await publishValidationFailure()
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
            requestInFlight = false
            state = GLMQuotaState(
                credentialStatus: .configured,
                validationStatus: .succeeded,
                provider: provider
            )
            await onStateChange(state)
            return true
        } catch {
            requestInFlight = false
            await publishValidationFailure()
            return false
        }
    }

    public func deleteKey() async -> Bool {
        if refreshTask != nil {
            await waitUntilIdle()
        }
        guard !requestInFlight else { return false }
        do {
            try keyStore.delete()
            state = GLMQuotaState(credentialStatus: .unconfigured)
            await onStateChange(state)
            return true
        } catch {
            await publishValidationFailure()
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
        started = false
    }

    private func performRefresh() async {
        defer { refreshTask = nil }
        guard !requestInFlight else { return }
        let key: String?
        do {
            key = try keyStore.load()
        } catch {
            state = GLMQuotaState(
                credentialStatus: .unconfigured,
                validationStatus: .failed
            )
            await onStateChange(state)
            return
        }

        guard let key, !key.isEmpty else {
            state = GLMQuotaState(credentialStatus: .unconfigured)
            await onStateChange(state)
            return
        }

        requestInFlight = true
        state = GLMQuotaState(credentialStatus: .configured)
        await onStateChange(state)
        do {
            let provider = try await quotaFetcher.fetchQuota(using: key)
            state = GLMQuotaState(
                credentialStatus: .configured,
                validationStatus: .succeeded,
                provider: provider
            )
        } catch {
            state = GLMQuotaState(
                credentialStatus: .configured,
                validationStatus: .failed
            )
        }
        requestInFlight = false
        await onStateChange(state)
    }

    private func publishValidationFailure() async {
        let hasStoredKey = (try? keyStore.exists()) == true
        state = GLMQuotaState(
            credentialStatus: hasStoredKey ? .configured : .unconfigured,
            validationStatus: .failed,
            provider: state.provider
        )
        await onStateChange(state)
    }
}
