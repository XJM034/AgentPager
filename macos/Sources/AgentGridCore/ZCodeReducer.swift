import Foundation

/// 把 ZCode 核心 Hook 事件归约为共享 `TaskSnapshot`。
///
/// ZCode 的 `Stop` 只证明模型轮次停止，因此映射到已有的非终态 `.idle`，
/// 不设置完成时间、未读完成标记或终态提醒。
public enum ZCodeEventReducer {
    public static func task(
        from hook: ZCodeHookPayload,
        existing: TaskSnapshot?,
        now: Date = .now
    ) -> TaskSnapshot {
        var task = existing ?? TaskSnapshot(
            id: hook.sessionID,
            source: .zcode,
            projectName: hook.projectName,
            lifecycle: .starting,
            startedAt: now,
            updatedAt: now
        )

        task.source = .zcode
        task.projectName = hook.projectName
        task.updatedAt = now

        switch hook.event {
        case .sessionStart:
            task.lifecycle = .starting
            task.activity = .thinking
            task.latestStep = nil
            task.completedAt = nil
            task.capabilities = []
        case .userPromptSubmit:
            task.lifecycle = .running
            task.activity = .thinking
            task.latestStep = nil
            task.completedAt = nil
            // 完整 prompt 不进入共享快照或本地任务持久化；只保留脱敏短标题。
            task.userPrompt = nil
            if existing == nil || task.title == task.projectName {
                task.title = safeTitle(projectName: task.projectName, prompt: hook.prompt)
            }
            task.capabilities = []
        case .preToolUse:
            let activity = activity(for: hook.toolName)
            task.lifecycle = .running
            task.activity = activity
            task.latestStep = safeStep(for: activity)
            task.completedAt = nil
            task.capabilities = []
        case .postToolUse:
            task.lifecycle = .running
            task.activity = .thinking
            task.latestStep = nil
            task.completedAt = nil
            task.capabilities = []
        case .stop:
            task.lifecycle = .idle
            task.activity = nil
            task.latestStep = nil
            task.completedAt = nil
            task.isUnread = false
            task.capabilities = []
        case .permissionRequest, .postToolUseFailure, nil:
            // #4 不实现权限回传或失败降级；未知/后续事件不得擅自改变生命周期。
            break
        }
        return task
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
        if name.contains("agent") || name.contains("task") || name.contains("thread") {
            return .delegating
        }
        return .executing
    }

    public static func safeStep(for activity: AgentActivity) -> String {
        switch activity {
        case .thinking: "处理工具"
        case .reading: "读取文件"
        case .searching: "搜索内容"
        case .editing: "编辑文件"
        case .executing: "执行工具"
        case .testing: "运行测试"
        case .browsing: "浏览内容"
        case .delegating: "协作任务"
        }
    }

    public static func safeTitle(projectName: String, prompt: String?) -> String {
        guard let prompt else { return projectName }
        var value = prompt
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")

        let replacements: [(pattern: String, template: String)] = [
            (#"(?i)\b(?:token|api[_ -]?key|secret|password|authorization)\s*[:=]\s*\S+"#, "[敏感信息]"),
            (#"(?i)\b(?:sk|key)-[A-Za-z0-9_-]{8,}\b"#, "[敏感信息]"),
            (#"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#, "[邮箱]"),
            (#"(?<![A-Za-z0-9])/(?:[^\s/]+/)+[^\s，。；;：:,]*"#, "[路径]"),
            (#"\b[A-Za-z]:\\(?:[^\s\\]+\\)+[^\s，。；;：:,]*"#, "[路径]"),
        ]
        for replacement in replacements {
            value = replacing(
                pattern: replacement.pattern,
                in: value,
                with: replacement.template
            )
        }
        value = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !value.isEmpty else { return projectName }
        return "\(projectName) · \(String(value.prefix(34)))"
    }

    private static func replacing(
        pattern: String,
        in value: String,
        with template: String
    ) -> String {
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return value
        }
        return expression.stringByReplacingMatches(
            in: value,
            range: NSRange(value.startIndex..., in: value),
            withTemplate: template
        )
    }
}
