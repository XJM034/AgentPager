import Foundation

public enum ZCodeDiagnosticOutcome: String, Equatable, Sendable {
    case observed
    case success
    case failure
    case unknown
}

/// 可展示在普通诊断页的 ZCode 事件摘要。类型中没有 prompt、命令、路径、
/// tool_input、tool_response 或错误正文的存储位置。
public struct ZCodeDiagnosticEvent: Equatable, Sendable {
    public var source: AgentSource
    public var eventCategory: String
    public var lifecycle: AgentLifecycle
    public var toolCategory: AgentActivity?
    public var outcome: ZCodeDiagnosticOutcome
    public var errorCategory: ZCodeErrorCategory?

    public init(hook: ZCodeHookPayload, lifecycle: AgentLifecycle) {
        source = .zcode
        eventCategory = hook.event?.rawValue ?? "UnknownEvent"
        self.lifecycle = lifecycle
        toolCategory = hook.toolName == nil
            ? nil
            : ZCodeEventReducer.activity(for: hook.toolName)
        outcome = switch hook.event {
        case .postToolUse: .success
        case .postToolUseFailure: .failure
        case nil: .unknown
        case .sessionStart, .userPromptSubmit, .preToolUse,
             .permissionRequest, .stop: .observed
        }
        errorCategory = hook.event == .postToolUseFailure
            ? (hook.errorCategory ?? .toolFailure)
            : nil
    }

    public var summary: String {
        var fields = [
            "ZCode",
            eventCategory,
            lifecycle.rawValue,
        ]
        if let toolCategory {
            fields.append(toolCategory.rawValue)
        }
        fields.append(outcome.rawValue)
        if let errorCategory {
            fields.append(errorCategory.rawValue)
        }
        return fields.joined(separator: " · ")
    }
}

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
            // prompt 不进入共享快照或本地任务持久化；首轮只映射为固定安全类别。
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
        case .permissionRequest:
            let activity = activity(for: hook.toolName)
            task.lifecycle = .waitingApproval
            task.activity = activity
            task.latestStep = approvalSummary(for: activity)
            task.completedAt = nil
            // Issue #5 只观察 ZCode 本地审批，不向手机开放裁决能力。
            task.capabilities = []
        case .stop:
            task.lifecycle = .idle
            task.activity = nil
            task.latestStep = nil
            task.completedAt = nil
            task.isUnread = false
            task.capabilities = []
        case .postToolUseFailure:
            let activity = activity(for: hook.toolName)
            task.lifecycle = .running
            task.activity = activity
            task.latestStep = failureSummary(
                for: activity,
                error: hook.errorCategory ?? .toolFailure
            )
            task.completedAt = nil
            task.isUnread = false
            task.capabilities = []
        case nil:
            // 未知/后续事件不得擅自改变生命周期。
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
        activityPresentation(for: activity).step
    }

    public static func approvalSummary(for activity: AgentActivity) -> String {
        "\(safeStep(for: activity)) · 等待本地批准"
    }

    public static func failureSummary(
        for activity: AgentActivity,
        error: ZCodeErrorCategory
    ) -> String {
        let step = activityPresentation(for: activity).failure
        let category = switch error {
        case .notFound: "未找到"
        case .permissionDenied: "权限拒绝"
        case .timeout: "超时"
        case .cancelled: "已取消"
        case .invalidInput: "输入无效"
        case .toolFailure: "工具错误"
        }
        return "\(step) · \(category)"
    }

    public static func safeRequestID(from hook: ZCodeHookPayload) -> String? {
        guard let rawRequestID = hook.requestID ?? hook.toolUseID,
              let session = safeIdentifierComponent(hook.sessionID),
              let request = safeIdentifierComponent(rawRequestID) else {
            return nil
        }
        return "zcode:\(session):\(request)"
    }

    public static func safeTitle(projectName: String, prompt: String?) -> String {
        guard prompt?.isEmpty == false else { return projectName }
        // 任意基于黑名单的脱敏都可能漏掉新格式凭据。这里只把首轮 prompt
        // 映射为有限的固定类别，不复制任何原文片段到 Android 或持久化。
        let normalized = prompt?.lowercased() ?? ""
        let categories: [([String], String)] = [
            (["测试", "验证", "test", "verify", "gradle", "xcode"], "验证请求"),
            (["修复", "修改", "编辑", "fix", "edit", "patch"], "变更请求"),
            (["实现", "创建", "开发", "implement", "create", "build"], "开发请求"),
            (["读取", "查看", "阅读", "read", "view"], "阅读请求"),
            (["搜索", "查找", "检索", "search", "find", "grep"], "检索请求"),
            (["解释", "分析", "诊断", "explain", "analyze", "diagnose"], "分析请求"),
        ]
        let category = categories.first { needles, _ in
            needles.contains { normalized.contains($0) }
        }?.1 ?? "新请求"
        return "\(projectName) · \(category)"
    }

    private static func activityPresentation(
        for activity: AgentActivity
    ) -> (step: String, failure: String) {
        switch activity {
        case .thinking: ("处理工具", "工具失败")
        case .reading: ("读取文件", "读取失败")
        case .searching: ("搜索内容", "搜索失败")
        case .editing: ("编辑文件", "编辑失败")
        case .executing: ("执行工具", "执行失败")
        case .testing: ("运行测试", "测试失败")
        case .browsing: ("浏览内容", "浏览失败")
        case .delegating: ("协作任务", "协作失败")
        }
    }

    private static func safeIdentifierComponent(_ value: String) -> String? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.filter { allowed.contains($0) }
        let sanitized = String(String.UnicodeScalarView(scalars).prefix(64))
        return sanitized.isEmpty ? nil : sanitized
    }
}
