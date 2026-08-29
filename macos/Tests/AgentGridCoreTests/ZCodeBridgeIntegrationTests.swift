import Foundation
import Network
import Testing
@testable import AgentGridCore

@Test("七类合成 ZCode Hook 经真实 Bridge 接缝进入脱敏共享快照")
func allSyntheticZCodeHooksReachSanitizedSharedSnapshot() throws {
    let recorder = ZCodeCatalogRecorder()
    let received = DispatchSemaphore(value: 0)
    let server = HookBridgeServer { envelope in
        guard case let .zcode(hook, _) = envelope else { return }
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
    #expect(
        permissionRequest.requestID ==
            "zcode:d56f4ad67745e4a1bdbe13dcc1afb430596ebef65e332b2a246d6f9c650ff930"
    )
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

@Test("ZCode 权限经真实 TCP 接缝独立裁决并在离线断线超时时 fallback")
func zcodePermissionRelayIsBoundedAndRequestScoped() throws {
    let events = DispatchSemaphore(value: 0)
    let states = ZCodePermissionStateRecorder()
    let server = HookBridgeServer(
        zcodeDecisionTimeoutMilliseconds: 80,
        eventHandler: { envelope in
            guard case let .zcode(_, permissionState) = envelope else { return }
            if let permissionState,
               permissionState != .pending,
               let requestID = envelope.zcodeRequestID {
                states.record(requestID, permissionState)
            }
            events.signal()
        },
        zcodeStateHandler: states.record
    )
    let port: UInt16 = 49_382
    try server.start(port: port)
    defer { server.stop() }
    server.setPhoneConnected(true)

    let allowHook = zcodePermissionPayload(toolUseID: "tool-allow")
    let denyHook = zcodePermissionPayload(toolUseID: "tool-deny")
    let allowID = try #require(zcodeRequestID(allowHook))
    let denyID = try #require(zcodeRequestID(denyHook))
    let allowExchange = startZCodeHook(allowHook, port: port)
    let denyExchange = startZCodeHook(denyHook, port: port)
    #expect(events.wait(timeout: .now() + 2) == .success)
    #expect(events.wait(timeout: .now() + 2) == .success)

    try server.resolve(
        sessionID: "zcode-e2e-permission",
        pendingRequestID: allowID,
        decision: .allow
    )
    try server.resolve(
        sessionID: "zcode-e2e-permission",
        pendingRequestID: denyID,
        decision: .deny
    )

    let expectedAllow = try ZCodeHookOutput.permission(.allow)
    let expectedDeny = try ZCodeHookOutput.permission(.deny)
    #expect(allowExchange.wait() == expectedAllow)
    #expect(denyExchange.wait() == expectedDeny)
    #expect(states.state(for: allowID) == .approved)
    #expect(states.state(for: denyID) == .denied)
    #expect(throws: ZCodePermissionResolutionError.completed(.approved)) {
        try server.resolve(
            sessionID: "zcode-e2e-permission",
            pendingRequestID: allowID,
            decision: .allow
        )
    }
    #expect(throws: ZCodePermissionResolutionError.unknownRequest) {
        try server.resolve(
            sessionID: "zcode-e2e-permission",
            pendingRequestID: "zcode:unknown",
            decision: .deny
        )
    }

    let duplicateHook = zcodePermissionPayload(toolUseID: "tool-duplicate")
    let duplicateID = try #require(zcodeRequestID(duplicateHook))
    let registeredExchange = startZCodeHook(duplicateHook, port: port)
    #expect(events.wait(timeout: .now() + 2) == .success)
    let rejectedDuplicateExchange = startZCodeHook(duplicateHook, port: port)
    #expect(events.wait(timeout: .now() + 2) == .success)
    #expect(rejectedDuplicateExchange.wait().isEmpty)
    try server.resolve(
        sessionID: "zcode-e2e-permission",
        pendingRequestID: duplicateID,
        decision: .allow
    )
    #expect(registeredExchange.wait() == expectedAllow)

    let timeoutHook = zcodePermissionPayload(toolUseID: "tool-timeout")
    let timeoutID = try #require(zcodeRequestID(timeoutHook))
    let timeoutExchange = startZCodeHook(timeoutHook, port: port)
    #expect(events.wait(timeout: .now() + 2) == .success)
    #expect(timeoutExchange.wait().isEmpty)
    #expect(states.wait(for: timeoutID, expected: .expired))

    let disconnectHook = zcodePermissionPayload(toolUseID: "tool-disconnect")
    let disconnectID = try #require(zcodeRequestID(disconnectHook))
    let disconnectExchange = startZCodeHook(disconnectHook, port: port)
    #expect(events.wait(timeout: .now() + 2) == .success)
    server.setPhoneConnected(false)
    #expect(disconnectExchange.wait().isEmpty)
    #expect(states.wait(for: disconnectID, expected: .cancelled))

    let offlineHook = zcodePermissionPayload(toolUseID: "tool-offline")
    let offlineID = try #require(zcodeRequestID(offlineHook))
    let offlineExchange = startZCodeHook(offlineHook, port: port)
    #expect(events.wait(timeout: .now() + 2) == .success)
    #expect(offlineExchange.wait().isEmpty)
    #expect(states.wait(for: offlineID, expected: .cancelled))

    server.setPhoneConnected(true)
    let missingID = zcodePermissionPayload(toolUseID: nil)
    let missingExchange = startZCodeHook(missingID, port: port)
    #expect(events.wait(timeout: .now() + 2) == .success)
    #expect(missingExchange.wait().isEmpty)
}

private extension HookEnvelope {
    var zcodeRequestID: String? {
        guard case let .zcode(payload, _) = self else { return nil }
        return ZCodeEventReducer.safeRequestID(from: payload)
    }
}

@Test("ZCode Hook 客户端在 Bridge 不可用时快速空输出 fallback")
func zcodeHookClientFallsBackWhenBridgeIsUnavailable() throws {
    let startedAt = Date()
    let response = HookBridgeClient.exchange(
        input: try JSONSerialization.data(
            withJSONObject: zcodePermissionPayload(toolUseID: "tool-no-bridge")
        ),
        source: .zcode,
        port: 49_399,
        timeoutMilliseconds: 2_000
    )

    #expect(response.isEmpty)
    #expect(Date().timeIntervalSince(startedAt) < 1)
}

@Test("已签名手机控制经真实 TCP Bridge 只裁决所选 ZCode 请求并拒绝重放")
func signedMobileControlRoutesOnlySelectedZCodeRequest() throws {
    let harness = ZCodeSignedControlHarness()
    let server = HookBridgeServer(
        zcodeDecisionTimeoutMilliseconds: 2_000,
        eventHandler: harness.accept
    )
    let port: UInt16 = 49_383
    try server.start(port: port)
    defer { server.stop() }
    server.setPhoneConnected(true)

    let firstHook = zcodePermissionPayload(toolUseID: "tool-signed-first")
    let secondHook = zcodePermissionPayload(toolUseID: "tool-signed-second")
    let firstID = try #require(zcodeRequestID(firstHook))
    let secondID = try #require(zcodeRequestID(secondHook))
    let firstExchange = startZCodeHook(firstHook, port: port)
    let secondExchange = startZCodeHook(secondHook, port: port)
    #expect(harness.waitForRequestCount(2))

    let secret = Data(repeating: 0x42, count: 32)
    let now = Date(timeIntervalSince1970: 1_785_067_200)
    let denySelected = try signedControl(
        pendingRequestID: secondID,
        decision: .deny,
        sequence: 1,
        secret: secret,
        now: now
    )
    let denied = try harness.perform(
        denySelected,
        secret: secret,
        resolver: server,
        now: now
    )

    #expect(denied.result == .accepted)
    let expectedDeny = try ZCodeHookOutput.permission(.deny)
    #expect(secondExchange.wait() == expectedDeny)
    #expect(harness.pendingRequestIDs() == [firstID])
    #expect(throws: ProtocolError.replayed) {
        try harness.perform(
            denySelected,
            secret: secret,
            resolver: server,
            now: now
        )
    }

    let approveRemaining = try signedControl(
        pendingRequestID: firstID,
        decision: .allow,
        sequence: 2,
        secret: secret,
        now: now
    )
    let approved = try harness.perform(
        approveRemaining,
        secret: secret,
        resolver: server,
        now: now
    )

    #expect(approved.result == .accepted)
    let expectedAllow = try ZCodeHookOutput.permission(.allow)
    #expect(firstExchange.wait() == expectedAllow)
    #expect(harness.pendingRequestIDs().isEmpty)
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

private final class ZCodeHookExchange: @unchecked Sendable {
    private let lock = NSLock()
    private let finished = DispatchSemaphore(value: 0)
    private var response = Data()

    func complete(_ data: Data?) {
        lock.lock()
        response = data ?? Data()
        lock.unlock()
        finished.signal()
    }

    func wait() -> Data {
        #expect(finished.wait(timeout: .now() + 2) == .success)
        lock.lock()
        defer { lock.unlock() }
        return response
    }
}

private final class ZCodePermissionStateRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let changed = DispatchSemaphore(value: 0)
    private var states: [String: ZCodePermissionRequestState] = [:]

    func record(_ requestID: String, _ state: ZCodePermissionRequestState) {
        lock.lock()
        states[requestID] = state
        lock.unlock()
        changed.signal()
    }

    func state(for requestID: String) -> ZCodePermissionRequestState? {
        lock.lock()
        defer { lock.unlock() }
        return states[requestID]
    }

    func wait(for requestID: String, expected: ZCodePermissionRequestState) -> Bool {
        if state(for: requestID) == expected { return true }
        _ = changed.wait(timeout: .now() + 2)
        return state(for: requestID) == expected
    }
}

private final class ZCodeSignedControlHarness: @unchecked Sendable {
    private let lock = NSLock()
    private let changed = DispatchSemaphore(value: 0)
    private var catalog = TaskCatalog()
    private var authorizer = SignedTaskControlAuthorizer()

    func accept(_ envelope: HookEnvelope) {
        guard case let .zcode(payload, permissionState) = envelope else { return }
        lock.lock()
        _ = catalog.accept(
            .zcodeHook(payload, permissionState: permissionState)
        )
        lock.unlock()
        changed.signal()
    }

    func waitForRequestCount(_ expected: Int) -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            lock.lock()
            let count = catalog.projection().pendingRequests.count
            lock.unlock()
            if count == expected { return true }
            _ = changed.wait(timeout: .now() + 0.05)
        }
        return false
    }

    func perform(
        _ envelope: SignedControlEnvelope,
        secret: Data,
        resolver: any CodexPermissionResolving,
        now: Date
    ) throws -> TaskControlReceipt {
        lock.lock()
        defer { lock.unlock() }
        let control = try authorizer.authorize(
            envelope,
            secret: secret,
            now: now
        )
        return catalog.perform(
            control,
            permissionResolver: resolver,
            now: now
        )
    }

    func pendingRequestIDs() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return catalog.projection().pendingRequests.compactMap(\.requestID)
    }
}

private func signedControl(
    pendingRequestID: String,
    decision: CodexPermissionDecision,
    sequence: UInt64,
    secret: Data,
    now: Date
) throws -> SignedControlEnvelope {
    var envelope = SignedControlEnvelope(
        messageId: UUID(),
        sentAt: Int64(now.timeIntervalSince1970 * 1_000),
        deviceId: "android-test-device",
        sequence: sequence,
        nonce: "nonce-\(sequence)",
        payload: ControlPayload(
            taskID: "zcode-e2e-permission",
            action: decision == .allow ? .approve : .deny,
            pendingRequestID: pendingRequestID
        )
    )
    envelope.signature = try ControlSigner.sign(envelope, secret: secret)
    return envelope
}

private func zcodePermissionPayload(toolUseID: String?) -> [String: Any] {
    var payload: [String: Any] = [
        "session_id": "zcode-e2e-permission",
        "hook_event_name": "PermissionRequest",
        "cwd": "/private/work/AgentPager",
        "tool_name": "Read",
        "tool_input": ["file_path": "/Users/example/private.txt"],
    ]
    if let toolUseID {
        payload["tool_use_id"] = toolUseID
    }
    return payload
}

private func zcodeRequestID(_ payload: [String: Any]) -> String? {
    guard let sessionID = payload["session_id"] as? String else { return nil }
    return ZCodePendingRequestID.make(
        sessionID: sessionID,
        toolUseID: payload["tool_use_id"] as? String
    )
}

private func startZCodeHook(
    _ payload: [String: Any],
    port: UInt16
) -> ZCodeHookExchange {
    let exchange = ZCodeHookExchange()
    let line = try! JSONSerialization.data(withJSONObject: [
        "hook_source": "zcode",
        "payload": payload,
    ]) + Data("\n".utf8)
    let connection = NWConnection(
        host: "127.0.0.1",
        port: NWEndpoint.Port(rawValue: port)!,
        using: .tcp
    )
    connection.stateUpdateHandler = { state in
        switch state {
        case .ready:
            connection.send(content: line, completion: .contentProcessed { error in
                guard error == nil else {
                    exchange.complete(nil)
                    return
                }
                connection.receiveMessage { data, _, _, _ in
                    exchange.complete(data)
                    connection.cancel()
                }
            })
        case .failed, .cancelled:
            break
        default:
            break
        }
    }
    connection.start(queue: DispatchQueue(label: "zcode-permission-exchange"))
    return exchange
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
