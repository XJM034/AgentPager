import Foundation
import Network
import Testing
@testable import AgentGridCore

@Test("七类合成 ZCode Hook 经真实 Bridge 接缝进入脱敏共享快照")
func allSyntheticZCodeHooksReachSanitizedSharedSnapshot() throws {
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
            "tool_name": "Edit",
            "tool_input": ["new_string": "private source", "file_path": "/Users/example/private/App.swift"],
            "tool_use_id": "tool-1",
        ],
        [
            "sessionId": "zcode-e2e-1",
            "hookEventName": "PermissionRequest",
            "cwd": "/private/work/AgentPager",
            "toolName": "Bash",
            "toolInput": ["command": "printenv SECRET && cat /Users/example/private/App.swift"],
            "toolCallId": "tool-2",
            "requestId": "request-2",
            "reason": "private approval reason",
        ],
        [
            "sessionId": "zcode-e2e-1",
            "hookEventName": "PostToolUseFailure",
            "cwd": "/private/work/AgentPager",
            "toolName": "Read",
            "toolUseId": "tool-2",
            "error": "Permission denied: /Users/example/private/App.swift",
            "errorDetails": ["trace": "private error details"],
        ],
        [
            "session_id": "zcode-e2e-1",
            "hook_event_name": "FutureEvent",
            "cwd": "/private/work/AgentPager",
            "unknown_payload": ["secret": "future private value"],
        ],
        [
            "session_id": "zcode-e2e-1",
            "hook_event_name": "Stop",
            "cwd": "/private/work/AgentPager",
            "last_assistant_message": "private response",
        ],
        [
            "session_id": "zcode-e2e-1",
            "hook_event_name": "UserPromptSubmit",
            "cwd": "/private/work/AgentPager",
            "prompt": "下一轮继续，仍保留首轮标题",
        ],
        [
            "session_id": "zcode-e2e-1",
            "hook_event_name": "PostToolUse",
            "cwd": "/private/work/AgentPager",
            "tool_name": "Read",
            "tool_response": ["content": "private source response"],
            "tool_use_id": "tool-2",
        ],
        [
            "session_id": "zcode-e2e-1",
            "hook_event_name": "Stop",
            "cwd": "/private/work/AgentPager",
        ],
        [
            "session_id": "future-only-session",
            "hook_event_name": "FutureEvent",
            "cwd": "/private/work/OtherProject",
        ],
    ]

    var projections: [TaskCatalogProjection] = []
    for event in events {
        try sendZCodeHook(event, port: port)
        #expect(received.wait(timeout: .now() + 2) == .success)
        projections.append(recorder.projection())
    }

    let payloads = projections.map { projection in
        StateSnapshotPayload(
            tasks: projection.tasks,
            usage: nil,
            focusedTaskID: projection.focusedTaskID,
            pendingRequests: projection.pendingRequests
        )
    }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .millisecondsSince1970
    let encoded = try encoder.encode(payloads)
    let encodedText = try #require(String(data: encoded, encoding: .utf8))
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    let decoded = try decoder.decode([StateSnapshotPayload].self, from: encoded)
    let task = try #require(decoded.last?.tasks.single)
    let permissionTask = try #require(decoded[3].tasks.single)
    let permissionRequest = try #require(decoded[3].pendingRequests.single)
    let failedTask = try #require(decoded[4].tasks.single)
    let unknownTask = try #require(decoded[5].tasks.single)
    let resumedTask = try #require(decoded[7].tasks.single)

    #expect(task.source == .zcode)
    #expect(task.projectName == "AgentPager")
    #expect(task.lifecycle == .idle)
    #expect(task.activity == nil)
    #expect(task.completedAt == nil)
    #expect(task.subagents.isEmpty)
    #expect(decoded.last?.tasks.count == 1)
    #expect(permissionTask.lifecycle == .waitingApproval)
    #expect(permissionTask.capabilities.isEmpty)
    #expect(permissionRequest.requestID == "zcode:zcode-e2e-1:request-2")
    #expect(permissionRequest.summary == "执行工具 · 等待本地批准")
    #expect(failedTask.lifecycle == .running)
    #expect(failedTask.latestStep == "读取失败 · 权限拒绝")
    #expect(unknownTask.lifecycle == failedTask.lifecycle)
    #expect(unknownTask.latestStep == failedTask.latestStep)
    #expect(resumedTask.lifecycle == .running)
    #expect(resumedTask.activity == .thinking)
    #expect(!encodedText.contains("/Users/example"))
    #expect(!encodedText.contains("sk-never-send"))
    #expect(!encodedText.contains("printenv"))
    #expect(!encodedText.contains("private source"))
    #expect(!encodedText.contains("private error details"))
    #expect(!encodedText.contains("private response"))
    #expect(!encodedText.contains("future private value"))
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
