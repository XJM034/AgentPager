import Foundation
import Testing
@testable import AgentGridCore

struct CodexRolloutReaderTests {
    @Test
    func 回放信号按时间排序以保留最新用户消息() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let rollout = root.appendingPathComponent("rollout-session-1.jsonl")
        let lines = [
            """
            {"timestamp":"2026-07-26T08:02:00Z","type":"event_msg","payload":{"type":"user_message","message":"最新消息"}}
            """,
            """
            {"timestamp":"2026-07-26T08:01:00Z","type":"event_msg","payload":{"type":"user_message","message":"较早消息"}}
            """,
        ]
        try (lines.joined(separator: "\n") + "\n")
            .write(to: rollout, atomically: true, encoding: .utf8)

        var reader = CodexRolloutReader()
        reader.track(
            filePath: rollout.path,
            sessionID: "session-1",
            cwd: "/tmp/AgentGrid",
            readExisting: true
        )

        let signals = reader.poll()

        #expect(signals.map(\.userPrompt) == ["较早消息", "最新消息"])
    }

    @Test
    func discoversRunningSessionCreatedBeforeHookRegistration() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let directory = root.appendingPathComponent("2026/07/26", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let rollout = directory.appendingPathComponent("rollout-session-live.jsonl")
        let lines = [
            """
            {"type":"session_meta","payload":{"id":"session-live","cwd":"/tmp/AgentGrid"}}
            """,
            """
            {"type":"response_item","payload":{"type":"custom_tool_call","name":"exec","input":"{\\"cmd\\":\\"swift test\\"}"}}
            """,
        ]
        try (lines.joined(separator: "\n") + "\n")
            .write(to: rollout, atomically: true, encoding: .utf8)

        var reader = CodexRolloutReader()
        let discovered = reader.discoverSessions(
            in: root,
            modifiedAfter: .distantPast
        )
        let signals = reader.poll()

        #expect(discovered == 1)
        #expect(signals.last?.sessionID == "session-live")
        #expect(signals.last?.cwd == "/tmp/AgentGrid")
        #expect(signals.last?.latestStep == "swift test")
    }

    @Test
    func parsesQuestionWithoutRetainingConversation() throws {
        let line = """
        {"timestamp":"2026-07-26T06:00:00Z","type":"event_msg","payload":{"type":"request_user_input","prompt":"选择继续方式"}}
        """

        let signal = CodexRolloutReader.signal(
            from: Data(line.utf8),
            sessionID: "session-1",
            cwd: "/tmp/AgentGrid"
        )

        #expect(signal?.lifecycle == .waitingAnswer)
        #expect(signal?.requestKind == .question)
        #expect(signal?.summary == "选择继续方式")
    }

    @Test
    func parsesInterruptedStateAndIgnoresErrorEvents() throws {
        let aborted = """
        {"type":"event_msg","payload":{"type":"turn_aborted"}}
        """
        let error = """
        {"type":"event_msg","payload":{"type":"error"}}
        """

        #expect(
            CodexRolloutReader.signal(
                from: Data(aborted.utf8),
                sessionID: "session-1",
                cwd: "/tmp"
            )?.lifecycle == .interrupted
        )
        #expect(
            CodexRolloutReader.signal(
                from: Data(error.utf8),
                sessionID: "session-1",
                cwd: "/tmp"
            ) == nil
        )
    }

    @Test
    func ignoresConversationMessages() throws {
        let line = """
        {"type":"event_msg","payload":{"type":"agent_message","message":"不应进入运行态存储"}}
        """

        #expect(
            CodexRolloutReader.signal(
                from: Data(line.utf8),
                sessionID: "session-1",
                cwd: "/tmp"
            ) == nil
        )
    }

    @Test
    func parsesUserPromptCommandAndTokenUsage() throws {
        let promptLine = """
        {"type":"event_msg","payload":{"type":"user_message","message":"优化像素动画"}}
        """
        let commandLine = """
        {"type":"response_item","payload":{"type":"function_call","name":"tools.exec_command","arguments":"{\\"cmd\\":\\"swift test\\"}"}}
        """
        let tokenLine = """
        {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1200,"cached_input_tokens":800,"output_tokens":240,"reasoning_output_tokens":60,"total_tokens":1440}}}}
        """

        let prompt = CodexRolloutReader.signal(
            from: Data(promptLine.utf8),
            sessionID: "session-1",
            cwd: "/tmp/AgentGrid"
        )
        let command = CodexRolloutReader.signal(
            from: Data(commandLine.utf8),
            sessionID: "session-1",
            cwd: "/tmp/AgentGrid"
        )
        let tokens = CodexRolloutReader.signal(
            from: Data(tokenLine.utf8),
            sessionID: "session-1",
            cwd: "/tmp/AgentGrid"
        )

        #expect(prompt?.userPrompt == "优化像素动画")
        #expect(command?.latestStep == "swift test")
        #expect(tokens?.tokenUsage == TokenUsage(
            input: 1200,
            cachedInput: 800,
            output: 240,
            reasoningOutput: 60,
            total: 1440
        ))
    }

    @Test
    func functionsExec只显示内部工具参数() throws {
        let input = """
        const r = await tools.exec_command({cmd:"swift test --filter CodexRolloutReaderTests",workdir:"/tmp/AgentGrid"});text(r.output)
        """
        let line = try JSONSerialization.data(withJSONObject: [
            "type": "response_item",
            "payload": [
                "type": "custom_tool_call",
                "name": "functions.exec",
                "input": input,
            ],
        ])

        let signal = CodexRolloutReader.signal(
            from: line,
            sessionID: "session-1",
            cwd: "/tmp/AgentGrid"
        )

        #expect(signal?.latestStep == "swift test --filter CodexRolloutReaderTests")
    }

    @Test
    func applyPatch只显示修改目标() throws {
        let input = """
        *** Begin Patch
        *** Update File: /tmp/AgentGrid/Sources/AgentGridCore/CodexRolloutReader.swift
        @@
        -旧内容
        +新内容
        *** End Patch
        """
        let line = try JSONSerialization.data(withJSONObject: [
            "type": "response_item",
            "payload": [
                "type": "custom_tool_call",
                "name": "apply_patch",
                "input": input,
            ],
        ])

        let signal = CodexRolloutReader.signal(
            from: line,
            sessionID: "session-1",
            cwd: "/tmp/AgentGrid"
        )

        #expect(
            signal?.latestStep
                == "/tmp/AgentGrid/Sources/AgentGridCore/CodexRolloutReader.swift"
        )
    }

    @Test
    func followsSubagentRolloutAndRoutesSignalsToParent() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let childID = "019f-child"
        let parentURL = directory.appendingPathComponent("rollout-parent.jsonl")
        let childURL = directory.appendingPathComponent("rollout-\(childID).jsonl")
        try Data("{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\"}}\n".utf8)
            .write(to: parentURL)
        let childLines = """
        {"type":"event_msg","payload":{"type":"task_started"}}
        {"type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\\"cmd\\":\\"swift test\\"}"}}
        {"type":"event_msg","payload":{"type":"task_complete"}}

        """
        try Data(childLines.utf8).write(to: childURL)

        var reader = CodexRolloutReader()
        reader.track(
            filePath: parentURL.path,
            sessionID: "parent-session",
            cwd: "/tmp/AgentGrid"
        )
        let activity = """
        {"type":"event_msg","payload":{"type":"sub_agent_activity","kind":"started","agent_thread_id":"\(childID)","agent_path":"/root/protocol_v2","occurred_at_ms":1785054818810}}

        """
        let handle = try FileHandle(forWritingTo: parentURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(activity.utf8))
        try handle.close()

        let discovery = reader.poll()
        let childSignals = reader.poll()

        #expect(discovery.first?.sessionID == "parent-session")
        #expect(discovery.first?.subagentID == childID)
        #expect(discovery.first?.subagentPath == "/root/protocol_v2")
        #expect(childSignals.allSatisfy { $0.sessionID == "parent-session" })
        #expect(childSignals.allSatisfy { $0.subagentID == childID })
        #expect(childSignals.contains { $0.latestStep == "swift test" })
        #expect(childSignals.contains { $0.lifecycle == .succeeded })
    }

    @Test
    func retriesSubagentDiscoveryWhenRolloutAppearsLater() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let parentID = "parent-late"
        let childID = "child-late"
        let parentURL = directory
            .appendingPathComponent("rollout-\(parentID).jsonl")
        try Data().write(to: parentURL)

        var reader = CodexRolloutReader()
        reader.track(
            filePath: parentURL.path,
            sessionID: parentID,
            cwd: "/tmp/AgentGrid"
        )
        let parentEvent = """
        {"type":"event_msg","payload":{"type":"sub_agent_activity","agent_thread_id":"\(childID)","agent_path":"/root/late_worker","kind":"started"}}
        """
        let parentHandle = try FileHandle(forWritingTo: parentURL)
        try parentHandle.seekToEnd()
        try parentHandle.write(contentsOf: Data("\(parentEvent)\n".utf8))
        try parentHandle.close()

        let discovery = reader.poll()
        #expect(discovery.first?.subagentID == childID)

        let childURL = directory
            .appendingPathComponent("rollout-\(childID).jsonl")
        let childLines = """
        {"type":"event_msg","payload":{"type":"task_started"}}
        {"type":"response_item","payload":{"type":"function_call","name":"search_graph","arguments":"{\\"query\\":\\"late worker\\"}"}}
        """
        try Data("\(childLines)\n".utf8).write(to: childURL)

        // 下一次轮询会发现迟到的文件，并读取已登记的子代理内容。
        let childSignals = reader.poll()

        #expect(childSignals.contains { $0.subagentID == childID })
        #expect(childSignals.contains { $0.latestStep?.contains("search_graph") == true })
    }
}
