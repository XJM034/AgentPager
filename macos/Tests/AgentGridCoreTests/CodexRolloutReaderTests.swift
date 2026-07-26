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
}
