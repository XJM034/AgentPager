import Foundation

public enum ZCodePermissionRegistrationResult: Equatable, Sendable {
    case registered
    case existing(ZCodePermissionRequestState)
    case unavailable

    public var state: ZCodePermissionRequestState {
        switch self {
        case .registered: .pending
        case let .existing(state): state
        case .unavailable: .cancelled
        }
    }

    public var isRegistered: Bool {
        self == .registered
    }
}

/// 只管理 ZCode 单次权限请求的生命周期；TCP 连接仍由 HookBridgeServer 持有。
/// 终态历史有界，淘汰后的控制请求会返回明确 unknown，而不会静默成功。
public struct ZCodePermissionRegistry: Sendable {
    private var states: [String: ZCodePermissionRequestState] = [:]
    private var terminalOrder: [String] = []
    private let terminalHistoryLimit: Int

    public init(
        terminalHistoryLimit: Int = ZCodePermissionTiming.terminalHistoryLimit
    ) {
        precondition(terminalHistoryLimit > 0)
        self.terminalHistoryLimit = terminalHistoryLimit
    }

    public mutating func register(
        _ requestID: String,
        channelAvailable: Bool
    ) -> ZCodePermissionRegistrationResult {
        if let state = states[requestID] {
            return .existing(state)
        }
        guard channelAvailable else {
            transition(requestID, to: .cancelled)
            return .unavailable
        }
        states[requestID] = .pending
        return .registered
    }

    public mutating func resolve(
        _ requestID: String,
        decision: CodexPermissionDecision
    ) throws -> ZCodePermissionRequestState {
        guard let state = states[requestID] else {
            throw ZCodePermissionResolutionError.unknownRequest
        }
        guard state == .pending else {
            throw ZCodePermissionResolutionError.completed(state)
        }
        let terminalState: ZCodePermissionRequestState =
            decision == .allow ? .approved : .denied
        transition(requestID, to: terminalState)
        return terminalState
    }

    @discardableResult
    public mutating func expire(_ requestID: String) -> Bool {
        transitionPending(requestID, to: .expired)
    }

    @discardableResult
    public mutating func cancel(_ requestID: String) -> Bool {
        transitionPending(requestID, to: .cancelled)
    }

    public func state(for requestID: String) -> ZCodePermissionRequestState? {
        states[requestID]
    }

    private mutating func transitionPending(
        _ requestID: String,
        to state: ZCodePermissionRequestState
    ) -> Bool {
        guard states[requestID] == .pending else { return false }
        transition(requestID, to: state)
        return true
    }

    private mutating func transition(
        _ requestID: String,
        to state: ZCodePermissionRequestState
    ) {
        let wasTerminal = states[requestID].map { $0 != .pending } ?? false
        states[requestID] = state
        guard state != .pending, !wasTerminal else { return }
        terminalOrder.append(requestID)
        while terminalOrder.count > terminalHistoryLimit {
            let evicted = terminalOrder.removeFirst()
            if states[evicted] != .pending {
                states.removeValue(forKey: evicted)
            }
        }
    }
}
