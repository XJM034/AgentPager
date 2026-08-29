import Foundation
import Network

/// 桥接服务器收到并已分类的 Hook 事件。
public enum HookEnvelope: Sendable {
    case codex(CodexHookPayload)
    case claude(ClaudeHookPayload)
    case zcode(
        ZCodeHookPayload,
        permissionState: ZCodePermissionRequestState? = nil
    )
}

public final class HookBridgeServer: CodexPermissionResolving, @unchecked Sendable {
    public typealias EventHandler = @Sendable (HookEnvelope) -> Void
    public typealias ZCodeStateHandler = @Sendable (
        String,
        ZCodePermissionRequestState
    ) -> Void

    private struct PendingConnection {
        var connectionID: UUID
        var connection: NWConnection
        var source: HookSource
        var sessionID: String
    }

    private let queue = DispatchQueue(label: "com.agentgrid.hook-server")
    private let lock = NSLock()
    private var listener: NWListener?
    /// 旧 Codex/Claude 使用来源+Session 键；ZCode 使用稳定 pending request ID。
    private var pending: [String: PendingConnection] = [:]
    private var zcodeRegistry: ZCodePermissionRegistry
    private var phoneConnected = false
    private let zcodeDecisionTimeoutMilliseconds: Int
    private let eventHandler: EventHandler
    private let zcodeStateHandler: ZCodeStateHandler

    public init(
        zcodeDecisionTimeoutMilliseconds: Int =
            ZCodePermissionTiming.bridgeDecisionTimeoutMilliseconds,
        zcodeTerminalHistoryLimit: Int = ZCodePermissionTiming.terminalHistoryLimit,
        eventHandler: @escaping EventHandler,
        zcodeStateHandler: @escaping ZCodeStateHandler = { _, _ in }
    ) {
        precondition(zcodeDecisionTimeoutMilliseconds > 0)
        self.zcodeDecisionTimeoutMilliseconds = zcodeDecisionTimeoutMilliseconds
        zcodeRegistry = ZCodePermissionRegistry(
            terminalHistoryLimit: zcodeTerminalHistoryLimit
        )
        self.eventHandler = eventHandler
        self.zcodeStateHandler = zcodeStateHandler
    }

    public func start(port: UInt16 = 49_361) throws {
        let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        let cancelled = lock.withLock { () -> [(String, PendingConnection)] in
            let zcode = pending.filter { $0.value.source == .zcode }
            for requestID in zcode.keys {
                _ = zcodeRegistry.cancel(requestID)
            }
            pending.values.forEach { $0.connection.cancel() }
            pending.removeAll()
            return Array(zcode)
        }
        cancelled.forEach { requestID, _ in
            zcodeStateHandler(requestID, .cancelled)
        }
    }

    public func setPhoneConnected(_ connected: Bool) {
        let cancelled = lock.withLock { () -> [(String, PendingConnection)] in
            phoneConnected = connected
            guard !connected else { return [] }
            let entries = pending.filter { $0.value.source == .zcode }
            for requestID in entries.keys {
                pending.removeValue(forKey: requestID)
                _ = zcodeRegistry.cancel(requestID)
            }
            return Array(entries)
        }
        cancelled.forEach { requestID, entry in
            finish(entry.connection, response: ZCodeHookOutput.fallback)
            zcodeStateHandler(requestID, .cancelled)
        }
    }

    public func resolve(sessionID: String, decision: CodexPermissionDecision) {
        let entry = lock.withLock {
            pending.removeValue(forKey: legacyKey(source: .codex, sessionID: sessionID))
                ?? pending.removeValue(
                    forKey: legacyKey(source: .claude, sessionID: sessionID)
                )
        }
        guard let entry else { return }
        let response: Data?
        switch entry.source {
        case .codex:
            response = try? CodexHookOutput.permission(decision)
        case .claude:
            let claudeDecision: ClaudePermissionDecision = decision == .allow ? .allow : .deny
            response = try? ClaudeHookOutput.permission(claudeDecision)
        case .zcode:
            // ZCode 手机权限回传属于 Issue #6；#5 不登记此类等待连接。
            response = try? ZCodeHookOutput.permission(decision)
        }
        guard let response else {
            entry.connection.cancel()
            return
        }
        entry.connection.send(content: response, completion: .contentProcessed { _ in
            entry.connection.cancel()
        })
    }

    public func resolve(
        sessionID: String,
        pendingRequestID: String,
        decision: CodexPermissionDecision
    ) throws {
        let outcome = lock.withLock {
            () -> Result<(PendingConnection, ZCodePermissionRequestState), Error> in
            guard let currentState = zcodeRegistry.state(for: pendingRequestID) else {
                return .failure(ZCodePermissionResolutionError.unknownRequest)
            }
            guard currentState == .pending else {
                return .failure(ZCodePermissionResolutionError.completed(currentState))
            }
            guard let entry = pending[pendingRequestID], entry.sessionID == sessionID else {
                return .failure(ZCodePermissionResolutionError.unknownRequest)
            }
            do {
                let state = try zcodeRegistry.resolve(
                    pendingRequestID,
                    decision: decision
                )
                pending.removeValue(forKey: pendingRequestID)
                return .success((entry, state))
            } catch {
                return .failure(error)
            }
        }
        let (entry, state) = try outcome.get()
        let response = try ZCodeHookOutput.permission(decision)
        finish(entry.connection, response: response)
        zcodeStateHandler(pendingRequestID, state)
    }

    private func accept(_ connection: NWConnection) {
        let connectionID = UUID()
        connection.stateUpdateHandler = { state in
            if case let .failed(error) = state {
                fputs("AgentPager Hook 连接错误：\(error)\n", stderr)
                self.cancelPending(connectionID: connectionID)
                connection.cancel()
            }
            if case .cancelled = state {
                self.cancelPending(connectionID: connectionID)
            }
        }
        connection.start(queue: queue)
        receive(on: connection, connectionID: connectionID, buffer: Data())
    }

    private func receive(
        on connection: NWConnection,
        connectionID: UUID,
        buffer: Data
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1_024) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            var nextBuffer = buffer
            if let data {
                nextBuffer.append(data)
            }

            if let newline = nextBuffer.firstIndex(of: UInt8(ascii: "\n")) {
                let payloadData = nextBuffer.prefix(upTo: newline)
                self.handle(
                    Data(payloadData),
                    connection: connection,
                    connectionID: connectionID
                )
                return
            }

            if isComplete || error != nil || nextBuffer.count > 1_048_576 {
                connection.cancel()
                return
            }
            self.receive(
                on: connection,
                connectionID: connectionID,
                buffer: nextBuffer
            )
        }
    }

    private func handle(
        _ data: Data,
        connection: NWConnection,
        connectionID: UUID
    ) {
        let envelope = decodeEnvelope(data)

        switch envelope {
        case let .codex(payload):
            // Codex 走原有路径；旧版 CLI 未带信封时也落到这里。
            eventHandler(.codex(payload))
            if payload.hookEventName == .permissionRequest {
                holdForApproval(
                    sessionID: payload.sessionID,
                    source: .codex,
                    connection: connection,
                    connectionID: connectionID
                )
            } else {
                acknowledge(connection)
            }
        case let .claude(payload):
            eventHandler(.claude(payload))
            if payload.event == .permissionRequest {
                holdForApproval(
                    sessionID: payload.sessionID,
                    source: .claude,
                    connection: connection,
                    connectionID: connectionID
                )
            } else {
                acknowledge(connection)
            }
        case let .zcode(payload, _):
            guard payload.event == .permissionRequest,
                  let requestID = ZCodePendingRequestID.make(
                      sessionID: payload.sessionID,
                      toolUseID: payload.toolUseID
                  ) else {
                let state: ZCodePermissionRequestState? =
                    payload.event == .permissionRequest ? .cancelled : nil
                eventHandler(.zcode(payload, permissionState: state))
                finish(connection, response: ZCodeHookOutput.fallback)
                return
            }
            let registration = registerZCodeForApproval(
                requestID: requestID,
                payload: payload,
                connection: connection,
                connectionID: connectionID
            )
            eventHandler(
                .zcode(payload, permissionState: registration.state)
            )
            if registration.isRegistered {
                return
            }
            finish(connection, response: ZCodeHookOutput.fallback)
        case nil:
            // 无法识别来源时按 Codex 兼容旧 CLI；解析失败则放行不阻塞。
            if let payload = try? JSONDecoder().decode(CodexHookPayload.self, from: data) {
                eventHandler(.codex(payload))
                if payload.hookEventName == .permissionRequest {
                    holdForApproval(
                        sessionID: payload.sessionID,
                        source: .codex,
                        connection: connection,
                        connectionID: connectionID
                    )
                } else {
                    acknowledge(connection)
                }
            } else {
                connection.cancel()
            }
        }
    }

    private func holdForApproval(
        sessionID: String,
        source: HookSource,
        connection: NWConnection,
        connectionID: UUID
    ) {
        lock.withLock {
            pending[legacyKey(source: source, sessionID: sessionID)] = PendingConnection(
                connectionID: connectionID,
                connection: connection,
                source: source,
                sessionID: sessionID
            )
        }
    }

    private func registerZCodeForApproval(
        requestID: String,
        payload: ZCodeHookPayload,
        connection: NWConnection,
        connectionID: UUID
    ) -> ZCodePermissionRegistrationResult {
        let registration = lock.withLock { () -> ZCodePermissionRegistrationResult in
            let result = zcodeRegistry.register(
                requestID,
                channelAvailable: phoneConnected && pending[requestID] == nil
            )
            if result.isRegistered {
                pending[requestID] = PendingConnection(
                    connectionID: connectionID,
                    connection: connection,
                    source: .zcode,
                    sessionID: payload.sessionID
                )
            }
            return result
        }
        guard registration.isRegistered else { return registration }
        queue.asyncAfter(
            deadline: .now() + .milliseconds(zcodeDecisionTimeoutMilliseconds)
        ) { [weak self] in
            self?.expireZCodeRequest(requestID)
        }
        return registration
    }

    private func expireZCodeRequest(_ requestID: String) {
        let entry = lock.withLock { () -> PendingConnection? in
            guard zcodeRegistry.expire(requestID) else { return nil }
            return pending.removeValue(forKey: requestID)
        }
        guard let entry else { return }
        finish(entry.connection, response: ZCodeHookOutput.fallback)
        zcodeStateHandler(requestID, .expired)
    }

    private func cancelPending(connectionID: UUID) {
        let cancelled = lock.withLock { () -> (String, PendingConnection)? in
            guard let match = pending.first(where: { $0.value.connectionID == connectionID }) else {
                return nil
            }
            pending.removeValue(forKey: match.key)
            guard match.value.source == .zcode else { return nil }
            _ = zcodeRegistry.cancel(match.key)
            return match
        }
        if let (requestID, _) = cancelled {
            zcodeStateHandler(requestID, .cancelled)
        }
    }

    private func finish(_ connection: NWConnection, response: Data) {
        guard !response.isEmpty else {
            connection.cancel()
            return
        }
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func legacyKey(source: HookSource, sessionID: String) -> String {
        "legacy:\(source.rawValue):\(sessionID)"
    }

    private func acknowledge(_ connection: NWConnection) {
        // 空行响应：Codex 视为继续；Claude 视为 continue=true。两端都放行。
        connection.send(content: Data("\n".utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func decodeEnvelope(_ data: Data) -> HookEnvelope? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawSource = object["hook_source"] as? String,
              let source = HookSource(rawValue: rawSource),
              let payloadObject = object["payload"] else {
            return nil
        }

        let payloadData = try? JSONSerialization.data(withJSONObject: payloadObject)
        switch source {
        case .codex:
            if let payloadData,
               let payload = try? JSONDecoder().decode(CodexHookPayload.self, from: payloadData) {
                return .codex(payload)
            }
            return nil
        case .claude:
            if let payloadData,
               let payload = try? JSONDecoder().decode(ClaudeHookPayload.self, from: payloadData) {
                return .claude(payload)
            }
            return nil
        case .zcode:
            if let payloadData,
               let payload = try? JSONDecoder().decode(ZCodeHookPayload.self, from: payloadData) {
                return .zcode(payload)
            }
            return nil
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
