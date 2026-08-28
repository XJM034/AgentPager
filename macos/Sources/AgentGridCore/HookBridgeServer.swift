import Foundation
import Network

/// 桥接服务器收到并已分类的 Hook 事件。
public enum HookEnvelope: Sendable {
    case codex(CodexHookPayload)
    case claude(ClaudeHookPayload)
    case zcode(ZCodeHookPayload)
}

public final class HookBridgeServer: CodexPermissionResolving, @unchecked Sendable {
    public typealias EventHandler = @Sendable (HookEnvelope) -> Void

    private let queue = DispatchQueue(label: "com.agentgrid.hook-server")
    private let lock = NSLock()
    private var listener: NWListener?
    /// 等待手机端裁决的权限连接，按会话 ID 索引并携带来源以选择响应格式。
    private var pending: [String: (connection: NWConnection, source: HookSource)] = [:]
    private let eventHandler: EventHandler

    public init(eventHandler: @escaping EventHandler) {
        self.eventHandler = eventHandler
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
        lock.withLock {
            pending.values.forEach { $0.connection.cancel() }
            pending.removeAll()
        }
    }

    public func resolve(sessionID: String, decision: CodexPermissionDecision) {
        let entry = lock.withLock { pending.removeValue(forKey: sessionID) }
        guard let entry else { return }
        let response: Data?
        switch entry.source {
        case .codex:
            response = try? CodexHookOutput.permission(decision)
        case .claude:
            let claudeDecision: ClaudePermissionDecision = decision == .allow ? .allow : .deny
            response = try? ClaudeHookOutput.permission(claudeDecision)
        case .zcode:
            // ZCode 手机权限回传属于 Issue #6；#4 不会登记此类等待连接。
            response = nil
        }
        guard let response else {
            entry.connection.cancel()
            return
        }
        entry.connection.send(content: response, completion: .contentProcessed { _ in
            entry.connection.cancel()
        })
    }

    private func accept(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            if case let .failed(error) = state {
                fputs("AgentPager Hook 连接错误：\(error)\n", stderr)
                connection.cancel()
            }
        }
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1_024) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            var nextBuffer = buffer
            if let data {
                nextBuffer.append(data)
            }

            if let newline = nextBuffer.firstIndex(of: UInt8(ascii: "\n")) {
                let payloadData = nextBuffer.prefix(upTo: newline)
                self.handle(Data(payloadData), connection: connection)
                return
            }

            if isComplete || error != nil || nextBuffer.count > 1_048_576 {
                connection.cancel()
                return
            }
            self.receive(on: connection, buffer: nextBuffer)
        }
    }

    private func handle(_ data: Data, connection: NWConnection) {
        let envelope = decodeEnvelope(data)

        switch envelope {
        case let .codex(payload):
            // Codex 走原有路径；旧版 CLI 未带信封时也落到这里。
            eventHandler(.codex(payload))
            if payload.hookEventName == .permissionRequest {
                holdForApproval(
                    sessionID: payload.sessionID,
                    source: .codex,
                    connection: connection
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
                    connection: connection
                )
            } else {
                acknowledge(connection)
            }
        case let .zcode(payload):
            eventHandler(.zcode(payload))
            // #4 只监控会话。即使收到尚未注册的权限事件也立即放行，
            // 让 ZCode 使用本地权限体验，不能由 Bridge 无限阻塞。
            acknowledge(connection)
        case nil:
            // 无法识别来源时按 Codex 兼容旧 CLI；解析失败则放行不阻塞。
            if let payload = try? JSONDecoder().decode(CodexHookPayload.self, from: data) {
                eventHandler(.codex(payload))
                if payload.hookEventName == .permissionRequest {
                    holdForApproval(
                        sessionID: payload.sessionID,
                        source: .codex,
                        connection: connection
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
        connection: NWConnection
    ) {
        lock.withLock {
            pending[sessionID] = (connection: connection, source: source)
        }
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
