import Foundation

/// 把 Claude Code 的 Hook 事件归约为 `TaskSnapshot`。
///
/// 与 `CodexEventReducer` 同构，仅事件集合与字段来源不同。
/// 工具活动归类、latestStep 文案、标题生成复用 Codex 的实现，保证两端观感一致。
public enum ClaudeEventReducer {
    public static func task(
        from hook: ClaudeHookPayload,
        existing: TaskSnapshot?,
        now: Date = .now
    ) -> TaskSnapshot {
        var task = existing ?? TaskSnapshot(
            id: hook.sessionID,
            source: .claudeCode,
            projectName: hook.projectName,
            lifecycle: .starting,
            startedAt: now,
            updatedAt: now
        )

        task.projectName = hook.projectName
        task.updatedAt = now

        switch hook.event {
        case .sessionStart:
            task.lifecycle = .starting
            task.activity = .thinking
            task.completedAt = nil
            task.capabilities = []
        case .userPromptSubmit:
            task.lifecycle = .running
            task.activity = .thinking
            task.completedAt = nil
            if let prompt = CodexEventReducer.normalized(hook.prompt) {
                task.userPrompt = prompt
                if existing == nil || task.title == task.projectName {
                    task.title = CodexEventReducer.title(
                        projectName: task.projectName,
                        prompt: prompt
                    )
                }
            }
            task.capabilities = []
        case .preToolUse:
            task.lifecycle = .running
            task.activity = CodexEventReducer.activity(for: hook.toolName)
            task.completedAt = nil
            task.latestStep = latestStep(
                toolName: hook.toolName,
                summary: summary(from: hook.toolInput)
            )
            task.capabilities = []
        case .postToolUse, .postToolUseFailure, .preCompact:
            task.lifecycle = .running
            task.activity = .thinking
            task.completedAt = nil
            task.capabilities = []
        case .permissionRequest:
            task.lifecycle = .waitingApproval
            task.activity = .executing
            task.completedAt = nil
            task.latestStep = latestStep(
                toolName: hook.toolName,
                summary: summary(from: hook.toolInput)
            )
            task.capabilities = [.approve, .deny]
        case .permissionDenied:
            task.lifecycle = .interrupted
            task.activity = nil
            task.completedAt = now
            task.isUnread = true
            task.capabilities = []
        case .notification:
            // 只有确实等待用户输入的通知才进入等待回答。
            // permission_prompt 由 PermissionRequest 负责，其他状态通知不应覆盖任务状态。
            if isAnswerNotification(hook.notificationType) {
                task.lifecycle = .waitingAnswer
                task.activity = .thinking
                task.completedAt = nil
                task.capabilities = []
            }
        case .stop:
            if task.lifecycle != .interrupted {
                task.lifecycle = .succeeded
            }
            task.activity = nil
            task.completedAt = now
            task.isUnread = true
            task.capabilities = []
        case .stopFailure:
            // Stop 失败时保持当前运行态，不误标为完成。
            if task.lifecycle == .succeeded {
                task.lifecycle = .running
                task.completedAt = nil
            }
            task.capabilities = []
        case .sessionEnd:
            if !task.isTerminal {
                task.lifecycle = .offline
                task.completedAt = nil
            }
            task.activity = nil
            task.capabilities = []
        case .subagentStart, .subagentStop:
            // Claude 子代理通过 SubagentStart/SubagentStop 事件显式建模，
            // 与 Codex 的 rollout 子代理路径一致。
            applySubagent(hook, task: &task, now: now)
            task.lifecycle = .running
            task.completedAt = nil
            task.activity = task.subagents.contains { !$0.isTerminal }
                ? .delegating
                : .thinking
            task.capabilities = []
        case nil:
            // 未知事件：只刷新时间戳，不改变生命周期，避免误判。
            task.updatedAt = now
        }
        return task
    }

    /// 从 Claude 的任意 `tool_input` JSON 中提取最具信息量的字段。
    public static func summary(from toolInput: HookJSONValue?) -> String? {
        guard case let .object(obj) = toolInput else {
            return CodexEventReducer.stringValue(for: toolInput)
        }
        let keyPriority = [
            "command", "file_path", "path", "pattern",
            "query", "prompt", "description", "url",
        ]
        for key in keyPriority {
            if let value = obj[key], let text = CodexEventReducer.stringValue(for: value), !text.isEmpty {
                return text
            }
        }
        return nil
    }

    /// 会让 Claude 暂停并等待用户输入的通知类型。
    public static func isAnswerNotification(_ notificationType: String?) -> Bool {
        ["idle_prompt", "elicitation_dialog", "agent_needs_input"]
            .contains(notificationType)
    }

    private static func applySubagent(
        _ hook: ClaudeHookPayload,
        task: inout TaskSnapshot,
        now: Date
    ) {
        guard let agentID = hook.agentID ?? hook.toolUseID else { return }
        let agentType = hook.agentType?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = (agentType?.isEmpty == false) ? agentType! : "Claude 子代理"
        let path = "/\(hook.agentType ?? "subagent")"
        var subagent = task.subagents.first { $0.id == agentID }
            ?? SubagentSnapshot(
                id: agentID,
                path: path,
                displayName: displayName,
                lifecycle: .running,
                activity: .thinking,
                startedAt: now,
                updatedAt: now
            )

        switch hook.event {
        case .subagentStart:
            subagent.lifecycle = .running
            subagent.activity = .delegating
            subagent.path = path
            subagent.displayName = displayName
            if let description = CodexEventReducer.normalized(hook.taskDescription) {
                subagent.latestStep = description
            }
        case .subagentStop:
            subagent.lifecycle = .succeeded
            subagent.activity = nil
        default:
            break
        }
        subagent.updatedAt = now

        task.subagents.removeAll { $0.id == agentID }
        task.subagents.append(subagent)
        task.subagents.sort {
            if $0.isTerminal != $1.isTerminal {
                return !$0.isTerminal
            }
            return $0.startedAt < $1.startedAt
        }
    }

    private static func latestStep(toolName: String?, summary: String?) -> String? {
        let tool = CodexEventReducer.normalized(toolName)
        let detail = CodexEventReducer.normalized(summary)
        switch (tool, detail) {
        case let (tool?, detail?) where CodexEventReducer.isCommandTool(tool):
            return String(detail.prefix(220))
        case let (tool?, nil) where CodexEventReducer.isCommandTool(tool):
            return nil
        case let (tool?, detail?):
            return String("\(tool) \(detail)".prefix(220))
        case let (tool?, nil):
            return String(tool.prefix(220))
        case let (nil, detail?):
            return String(detail.prefix(220))
        case (nil, nil):
            return nil
        }
    }
}
