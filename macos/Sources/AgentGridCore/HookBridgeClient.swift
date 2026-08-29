import Foundation
import Network

private final class HookBridgeClientState: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var didFinish = false
    private var response = Data()

    func append(_ data: Data) {
        lock.lock()
        response.append(data)
        lock.unlock()
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        guard !didFinish else { return }
        didFinish = true
        semaphore.signal()
    }

    func wait(milliseconds: Int) -> Data {
        _ = semaphore.wait(timeout: .now() + .milliseconds(milliseconds))
        lock.lock()
        defer { lock.unlock() }
        return response
    }
}

/// Hook CLI 到本地 Bridge 的有界 TCP 接缝。连接失败、无响应或超时都返回空数据，
/// 调用方据此保持 stdout 为空并把审批交还对应 Agent 的本地流程。
public enum HookBridgeClient {
    public static func exchange(
        input: Data,
        source: HookSource,
        port: UInt16 = 49_361,
        timeoutMilliseconds: Int
    ) -> Data {
        precondition(timeoutMilliseconds > 0)
        let line = wrapInEnvelope(input: input, source: source)
        let connection = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        let queue = DispatchQueue(label: "com.agentgrid.hook-client")
        let state = HookBridgeClientState()

        connection.stateUpdateHandler = { connectionState in
            switch connectionState {
            case .ready:
                connection.send(content: line, completion: .contentProcessed { error in
                    guard error == nil else {
                        state.finish()
                        return
                    }
                    connection.receiveMessage { data, _, _, _ in
                        if let data {
                            state.append(data)
                        }
                        state.finish()
                    }
                })
            case .waiting:
                // Loopback Bridge 不可达时 Network.framework 会先进入 waiting。
                // 必须先终止连接再交还本地审批，避免 waiting 后恢复 ready 又发送 Hook。
                connection.cancel()
                state.finish()
            case .failed, .cancelled:
                state.finish()
            default:
                break
            }
        }
        connection.start(queue: queue)
        let response = state.wait(milliseconds: timeoutMilliseconds)
        connection.cancel()
        return response
    }

    private static func wrapInEnvelope(input: Data, source: HookSource) -> Data {
        guard let payload = try? JSONSerialization.jsonObject(with: input) else {
            var fallback = input
            fallback.append(UInt8(ascii: "\n"))
            return fallback
        }
        let envelope: [String: Any] = [
            "hook_source": source.rawValue,
            "payload": payload,
        ]
        let data = (try? JSONSerialization.data(
            withJSONObject: envelope,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )) ?? input
        var line = data
        line.append(UInt8(ascii: "\n"))
        return line
    }
}
