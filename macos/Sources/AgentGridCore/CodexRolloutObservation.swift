import Foundation

public struct CodexRolloutReconciliation: Sendable {
    public var activeSessionIDs: Set<String>
    public var signals: [CodexRolloutSignal]

    public init(
        activeSessionIDs: Set<String>,
        signals: [CodexRolloutSignal]
    ) {
        self.activeSessionIDs = activeSessionIDs
        self.signals = signals
    }
}

public struct CodexRolloutObservation: Sendable {
    private var reader: CodexRolloutReader
    private let sessionsRoot: URL
    private let lookback: TimeInterval
    private let discoveryInterval: TimeInterval
    private var nextDiscovery: Date

    public init() {
        self.init(
            sessionsRoot: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex/sessions", isDirectory: true),
            lookback: 10 * 60,
            discoveryInterval: 3
        )
    }

    init(
        sessionsRoot: URL,
        lookback: TimeInterval,
        discoveryInterval: TimeInterval,
        reader: CodexRolloutReader = CodexRolloutReader()
    ) {
        self.reader = reader
        self.sessionsRoot = sessionsRoot
        self.lookback = lookback
        self.discoveryInterval = discoveryInterval
        nextDiscovery = .distantPast
    }

    public mutating func include(_ hook: CodexHookPayload) {
        reader.track(
            filePath: hook.transcriptPath,
            sessionID: hook.sessionID,
            cwd: hook.cwd,
            initialLifecycle: Self.lifecycle(for: hook.hookEventName)
        )
    }

    public mutating func observe(now: Date = .now) -> [CodexRolloutSignal] {
        if now >= nextDiscovery {
            reader.discoverSessions(
                in: sessionsRoot,
                modifiedAfter: now.addingTimeInterval(-lookback),
                now: now
            )
            nextDiscovery = now.addingTimeInterval(discoveryInterval)
        }
        return reader.poll(now: now)
    }

    public mutating func reconcile(
        sessionStartDates: [String: Date],
        now: Date = .now
    ) -> CodexRolloutReconciliation {
        let discoveredSessionIDs = reader.discoverSessions(
            in: sessionsRoot,
            matching: sessionStartDates
        )
        let signals = reader.poll(now: now)
        var latestLifecycleBySessionID: [String: AgentLifecycle] = [:]
        for signal in signals where discoveredSessionIDs.contains(signal.sessionID) {
            if let lifecycle = signal.lifecycle {
                latestLifecycleBySessionID[signal.sessionID] = lifecycle
            }
        }
        let activeSessionIDs = discoveredSessionIDs.filter { sessionID in
            guard let lifecycle = latestLifecycleBySessionID[sessionID] else {
                return false
            }
            return lifecycle != .succeeded && lifecycle != .interrupted
        }
        return CodexRolloutReconciliation(
            activeSessionIDs: activeSessionIDs,
            signals: signals
        )
    }

    private static func lifecycle(for event: CodexHookEventName) -> AgentLifecycle {
        switch event {
        case .sessionStart:
            return .starting
        case .userPromptSubmit, .preToolUse, .postToolUse:
            return .running
        case .permissionRequest:
            return .waitingApproval
        case .stop:
            return .succeeded
        }
    }
}
