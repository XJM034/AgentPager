import Foundation
import Network
import Testing
@testable import AgentGridCore

@Test("合成 ZCode Hook 经真实 Bridge 接缝进入脱敏共享快照")
func syntheticZCodeHookReachesSanitizedSharedSnapshot() throws {
    let recorder = ZCodeCatalogRecorder()
    let received = DispatchSemaphore(value: 0)
    let server = HookBridgeServer { envelope in
        guard case let .zcode(hook) = envelope else { return }
        recorder.accept(hook)
        received.signal()
    }
    let port: UInt16 = 49_381
    try server.start(port: port)
    defer { server.stop() }

    let events: [[String: Any]] = [
        [
            "session_id": "zcode-e2e-1",
            "hook_event_name": "SessionStart",
            "cwd": "/private/work/AgentPager",
        ],
        [
            "sessionId": "zcode-e2e-1",
            "hookEventName": "UserPromptSubmit",
            "cwd": "/private/work/AgentPager",
            "prompt": "检查 /Users/example/private/App.swift token=sk-never-send",
        ],
        [
            "session_id": "zcode-e2e-1",
            "hook_event_name": "PreToolUse",
            "cwd": "/private/work/AgentPager",
            "tool_name": "Task",
            "tool_input": ["prompt": "读取 /Users/example/private/App.swift"],
            "tool_use_id": "tool-1",
        ],
        [
            "session_id": "zcode-e2e-1",
            "hook_event_name": "PostToolUse",
            "cwd": "/private/work/AgentPager",
            "tool_name": "Task",
            "tool_use_id": "tool-1",
        ],
        [
            "session_id": "zcode-e2e-1",
            "hook_event_name": "Stop",
            "cwd": "/private/work/AgentPager",
        ],
    ]

    for event in events {
        try sendZCodeHook(event, port: port)
        #expect(received.wait(timeout: .now() + 2) == .success)
    }

    let projection = recorder.projection()
    let payload = StateSnapshotPayload(
        tasks: projection.tasks,
        usage: nil,
        focusedTaskID: projection.focusedTaskID,
        pendingRequests: projection.pendingRequests
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .millisecondsSince1970
    let encoded = try encoder.encode(payload)
    let encodedText = try #require(String(data: encoded, encoding: .utf8))
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    let decoded = try decoder.decode(StateSnapshotPayload.self, from: encoded)
    let task = try #require(decoded.tasks.single)

    #expect(task.source == .zcode)
    #expect(task.projectName == "AgentPager")
    #expect(task.lifecycle == .idle)
    #expect(task.activity == nil)
    #expect(task.completedAt == nil)
    #expect(task.subagents.isEmpty)
    #expect(!encodedText.contains("/Users/example"))
    #expect(!encodedText.contains("sk-never-send"))
}

private final class ZCodeCatalogRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var catalog = TaskCatalog()

    func accept(_ hook: ZCodeHookPayload) {
        lock.lock()
        _ = catalog.accept(.zcodeHook(hook))
        lock.unlock()
    }

    func projection() -> TaskCatalogProjection {
        lock.lock()
        defer { lock.unlock() }
        return catalog.projection()
    }
}

private final class ZCodeHookClientState: @unchecked Sendable {
    let finished = DispatchSemaphore(value: 0)
}

private func sendZCodeHook(_ payload: [String: Any], port: UInt16) throws {
    var line = try JSONSerialization.data(withJSONObject: [
        "hook_source": "zcode",
        "payload": payload,
    ])
    line.append(UInt8(ascii: "\n"))
    let data = line

    let connection = NWConnection(
        host: "127.0.0.1",
        port: NWEndpoint.Port(rawValue: port)!,
        using: .tcp
    )
    let state = ZCodeHookClientState()
    connection.stateUpdateHandler = { connectionState in
        switch connectionState {
        case .ready:
            connection.send(content: data, completion: .contentProcessed { error in
                guard error == nil else {
                    state.finished.signal()
                    return
                }
                connection.receiveMessage { _, _, _, _ in
                    state.finished.signal()
                }
            })
        case .failed, .cancelled:
            state.finished.signal()
        default:
            break
        }
    }
    connection.start(queue: DispatchQueue(label: "zcode-hook-test-client"))
    let result = state.finished.wait(timeout: .now() + 2)
    connection.cancel()
    #expect(result == .success)
}

private extension Array {
    var single: Element? {
        count == 1 ? first : nil
    }
}
