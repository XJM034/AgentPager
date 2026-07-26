import Foundation
import Testing
@testable import AgentGridCore

struct CodexRolloutReaderTests {
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
    func parsesInterruptedAndFailedStates() throws {
        let aborted = """
        {"type":"event_msg","payload":{"type":"turn_aborted"}}
        """
        let failed = """
        {"type":"event_msg","payload":{"type":"turn_failed"}}
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
                from: Data(failed.utf8),
                sessionID: "session-1",
                cwd: "/tmp"
            )?.lifecycle == .failed
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
        {"type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\\"cmd\\":\\"swift test\\"}"}}
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
        #expect(command?.latestStep == "exec_command swift test")
        #expect(tokens?.tokenUsage == TokenUsage(
            input: 1200,
            cachedInput: 800,
            output: 240,
            reasoningOutput: 60,
            total: 1440
        ))
    }
}
