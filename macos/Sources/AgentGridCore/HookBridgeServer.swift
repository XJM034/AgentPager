import Foundation
import Network

public final class HookBridgeServer: CodexPermissionResolving, @unchecked Sendable {
    public typealias EventHandler = @Sendable (CodexHookPayload) -> Void

    private let queue = DispatchQueue(label: "com.agentgrid.hook-server")
    private let lock = NSLock()
    private var listener: NWListener?
    private var pending: [String: NWConnection] = [:]
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
            pending.values.forEach { $0.cancel() }
            pending.removeAll()
        }
    }

    public func resolve(sessionID: String, decision: CodexPermissionDecision) {
        let connection = lock.withLock { pending.removeValue(forKey: sessionID) }
        guard let connection,
              let response = try? CodexHookOutput.permission(decision) else {
            return
        }
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
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
        guard let hook = try? JSONDecoder().decode(CodexHookPayload.self, from: data) else {
            connection.cancel()
            return
        }

        eventHandler(hook)
        if hook.hookEventName == .permissionRequest {
            lock.withLock {
                pending[hook.sessionID] = connection
            }
        } else {
            connection.send(content: Data("\n".utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
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
