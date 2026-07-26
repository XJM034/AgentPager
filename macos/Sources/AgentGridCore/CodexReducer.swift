import Foundation

public enum CodexEventReducer {
    public static func task(
        from hook: CodexHookPayload,
        existing: TaskSnapshot?,
        now: Date = .now
    ) -> TaskSnapshot {
        var task = existing ?? TaskSnapshot(
            id: hook.sessionID,
            source: hook.source == "app" ? .codexDesktop : .codexCLI,
            projectName: hook.projectName,
            lifecycle: .starting,
            startedAt: now,
            updatedAt: now
        )

        task.projectName = hook.projectName
        task.updatedAt = now
        task.completedAt = nil

        switch hook.hookEventName {
        case .sessionStart:
            task.lifecycle = .starting
            task.activity = .thinking
            task.capabilities = []
        case .userPromptSubmit:
            task.lifecycle = .running
            task.activity = .thinking
            if let prompt = normalized(hook.prompt) {
                task.userPrompt = prompt
                if existing == nil || task.title == task.projectName {
                    task.title = title(projectName: task.projectName, prompt: prompt)
                }
            }
            task.capabilities = []
        case .preToolUse:
            task.lifecycle = .running
            task.activity = activity(for: hook.toolName)
            task.latestStep = latestStep(
                toolName: hook.toolName,
                summary: hook.toolInput?.summary
            )
            task.capabilities = []
        case .postToolUse:
            task.lifecycle = .running
            task.activity = .thinking
            task.capabilities = []
        case .permissionRequest:
            task.lifecycle = .waitingApproval
            task.activity = .executing
            task.capabilities = [.approve, .deny]
        case .stop:
            if task.lifecycle != .interrupted && task.lifecycle != .failed {
                task.lifecycle = .succeeded
            }
            task.activity = nil
            task.completedAt = now
            task.isUnread = true
            task.capabilities = []
        }
        return task
    }

    public static func title(projectName: String, prompt: String?) -> String {
        guard let prompt = normalized(prompt) else { return projectName }
        let shortPrompt = String(prompt.prefix(34))
        return "\(projectName) · \(shortPrompt)"
    }

    public static func latestStep(toolName: String?, summary: String?) -> String? {
        let tool = normalized(toolName)
        let detail = normalized(summary)
        switch (tool, detail) {
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

    public static func activity(for toolName: String?) -> AgentActivity {
        let name = toolName?.lowercased() ?? ""
        if name.contains("test") || name.contains("gradle") || name.contains("xcode") {
            return .testing
        }
        if name.contains("read") || name.contains("view") || name.contains("list") {
            return .reading
        }
        if name.contains("web") || name.contains("browser") {
            return .browsing
        }
        if name.contains("search") || name.contains("find") || name.contains("grep") {
            return .searching
        }
        if name.contains("patch") || name.contains("write") || name.contains("edit") {
            return .editing
        }
        if name.contains("agent") || name.contains("thread") {
            return .delegating
        }
        return .executing
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return normalized.isEmpty ? nil : normalized
    }
}
