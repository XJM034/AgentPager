import Foundation

public struct CodexRolloutSignal: Equatable, Sendable {
    public var sessionID: String
    public var cwd: String
    public var lifecycle: AgentLifecycle?
    public var activity: AgentActivity?
    public var requestKind: PendingRequestKind?
    public var summary: String?
    public var userPrompt: String?
    public var latestStep: String?
    public var tokenUsage: TokenUsage?
    public var timestamp: Date

    public init(
        sessionID: String,
        cwd: String,
        lifecycle: AgentLifecycle?,
        activity: AgentActivity?,
        requestKind: PendingRequestKind? = nil,
        summary: String? = nil,
        userPrompt: String? = nil,
        latestStep: String? = nil,
        tokenUsage: TokenUsage? = nil,
        timestamp: Date = .now
    ) {
        self.sessionID = sessionID
        self.cwd = cwd
        self.lifecycle = lifecycle
        self.activity = activity
        self.requestKind = requestKind
        self.summary = summary
        self.userPrompt = userPrompt
        self.latestStep = latestStep
        self.tokenUsage = tokenUsage
        self.timestamp = timestamp
    }
}

public struct CodexRolloutReader: Sendable {
    private struct TrackedFile: Sendable {
        var url: URL
        var sessionID: String
        var cwd: String
        var offset: UInt64
        var partialLine = Data()
    }

    private var trackedFiles: [String: TrackedFile] = [:]

    public init() {}

    public var hasTrackedFiles: Bool {
        !trackedFiles.isEmpty
    }

    public mutating func track(
        filePath: String?,
        sessionID: String,
        cwd: String
    ) {
        guard let filePath, !filePath.isEmpty else {
            return
        }

        let url = URL(fileURLWithPath: filePath)
        let key = url.standardizedFileURL.path
        let size = Self.fileSize(at: url)
        if var existing = trackedFiles[key] {
            existing.sessionID = sessionID
            existing.cwd = cwd
            trackedFiles[key] = existing
        } else {
            // 从当前文件尾部开始，只处理注册后的增量事件。
            trackedFiles[key] = TrackedFile(
                url: url,
                sessionID: sessionID,
                cwd: cwd,
                offset: size
            )
        }
    }

    public mutating func poll() -> [CodexRolloutSignal] {
        var signals: [CodexRolloutSignal] = []

        for key in Array(trackedFiles.keys) {
            guard var tracked = trackedFiles[key] else {
                continue
            }
            let size = Self.fileSize(at: tracked.url)
            guard size >= tracked.offset else {
                tracked.offset = size
                tracked.partialLine.removeAll(keepingCapacity: false)
                trackedFiles[key] = tracked
                continue
            }
            guard size > tracked.offset,
                  let handle = try? FileHandle(forReadingFrom: tracked.url) else {
                continue
            }
            defer { try? handle.close() }

            do {
                try handle.seek(toOffset: tracked.offset)
                let appended = try handle.readToEnd() ?? Data()
                tracked.offset = size
                tracked.partialLine.append(appended)

                while let newline = tracked.partialLine.firstIndex(of: UInt8(ascii: "\n")) {
                    let line = tracked.partialLine[..<newline]
                    tracked.partialLine.removeSubrange(
                        tracked.partialLine.startIndex...newline
                    )
                    if let signal = Self.signal(
                        from: Data(line),
                        sessionID: tracked.sessionID,
                        cwd: tracked.cwd
                    ) {
                        signals.append(signal)
                    }
                }
            } catch {
                tracked.offset = size
                tracked.partialLine.removeAll(keepingCapacity: false)
            }
            trackedFiles[key] = tracked
        }

        return signals
    }

    public static func signal(
        from line: Data,
        sessionID: String,
        cwd: String,
        now: Date = .now
    ) -> CodexRolloutSignal? {
        guard let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let rootType = root["type"] as? String,
              let payload = root["payload"] as? [String: Any],
              let type = payload["type"] as? String else {
            return nil
        }

        let timestamp = parseTimestamp(root["timestamp"] as? String) ?? now

        if rootType == "response_item" {
            return responseItemSignal(
                type: type,
                payload: payload,
                sessionID: sessionID,
                cwd: cwd,
                timestamp: timestamp
            )
        }
        guard rootType == "event_msg" else { return nil }

        switch type {
        case "task_started", "turn_started":
            return signal(.running, .thinking, timestamp: timestamp)
        case "task_complete", "turn_complete":
            return signal(.succeeded, nil, timestamp: timestamp)
        case "turn_aborted":
            return signal(.interrupted, nil, timestamp: timestamp)
        case "error", "task_failed", "turn_failed":
            return signal(.failed, nil, timestamp: timestamp)
        case "agent_reasoning", "agent_reasoning_raw_content",
             "agent_reasoning_section_break", "context_compacted":
            return signal(.running, .thinking, timestamp: timestamp)
        case "user_message":
            let prompt = clipped(payload["message"] as? String, limit: 240)
            return signal(
                .running,
                .thinking,
                userPrompt: prompt,
                timestamp: timestamp
            )
        case "token_count":
            guard let usage = tokenUsage(from: payload) else { return nil }
            return signal(nil, nil, tokenUsage: usage, timestamp: timestamp)
        case "exec_command_begin", "terminal_interaction":
            return signal(
                .running,
                .executing,
                latestStep: commandSummary(payload),
                timestamp: timestamp
            )
        case "patch_apply_begin", "patch_apply_updated":
            return signal(.running, .editing, latestStep: "apply_patch", timestamp: timestamp)
        case "mcp_tool_call_begin", "dynamic_tool_call_request":
            return signal(
                .running,
                .executing,
                latestStep: toolSummary(payload),
                timestamp: timestamp
            )
        case "web_search_begin", "web_search_end":
            return signal(
                .running,
                .browsing,
                latestStep: prefixed("Web", clipped(payload["query"] as? String)),
                timestamp: timestamp
            )
        case "image_generation_begin", "image_generation_end",
             "view_image_tool_call":
            return signal(.running, .reading, latestStep: "Image", timestamp: timestamp)
        case "plan_update":
            return signal(.running, .thinking, latestStep: "更新计划", timestamp: timestamp)
        case "exec_command_end", "patch_apply_end", "mcp_tool_call_end",
             "dynamic_tool_call_response":
            return signal(.running, .thinking, timestamp: timestamp)
        case "request_user_input", "elicitation_request":
            return signal(
                .waitingAnswer,
                .thinking,
                kind: .question,
                summary: clipped(payload["prompt"] as? String)
                    ?? clipped(payload["message"] as? String),
                timestamp: timestamp
            )
        case "exec_approval_request", "apply_patch_approval_request",
             "request_permissions":
            return signal(
                .waitingApproval,
                .executing,
                kind: .approval,
                summary: clipped(payload["reason"] as? String)
                    ?? clipped(payload["message"] as? String),
                timestamp: timestamp
            )
        default:
            return nil
        }

        func signal(
            _ lifecycle: AgentLifecycle?,
            _ activity: AgentActivity?,
            kind: PendingRequestKind? = nil,
            summary: String? = nil,
            userPrompt: String? = nil,
            latestStep: String? = nil,
            tokenUsage: TokenUsage? = nil,
            timestamp: Date
        ) -> CodexRolloutSignal {
            CodexRolloutSignal(
                sessionID: sessionID,
                cwd: cwd,
                lifecycle: lifecycle,
                activity: activity,
                requestKind: kind,
                summary: summary,
                userPrompt: userPrompt,
                latestStep: latestStep,
                tokenUsage: tokenUsage,
                timestamp: timestamp
            )
        }
    }

    private static func responseItemSignal(
        type: String,
        payload: [String: Any],
        sessionID: String,
        cwd: String,
        timestamp: Date
    ) -> CodexRolloutSignal? {
        guard ["function_call", "custom_tool_call", "tool_search_call"].contains(type) else {
            return nil
        }
        let name = payload["name"] as? String
            ?? (type == "tool_search_call" ? "tool_search" : nil)
        let rawArguments = payload["arguments"] as? String
            ?? payload["input"] as? String
        let detail = argumentSummary(rawArguments, toolName: name)
        let step = prefixed(name, detail)
        let activity = CodexEventReducer.activity(for: name)
        return CodexRolloutSignal(
            sessionID: sessionID,
            cwd: cwd,
            lifecycle: .running,
            activity: activity,
            latestStep: step,
            timestamp: timestamp
        )
    }

    private static func argumentSummary(_ raw: String?, toolName: String?) -> String? {
        guard let raw, let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return clipped(raw)
        }
        if let dictionary = object as? [String: Any] {
            for key in ["cmd", "command", "query", "path", "ref_id", "step"] {
                if let value = displayValue(dictionary[key]) {
                    return clipped(value)
                }
            }
            if toolName?.contains("apply_patch") == true {
                return nil
            }
            return dictionary
                .sorted { $0.key < $1.key }
                .compactMap { displayValue($0.value) }
                .first
                .flatMap { clipped($0) }
        }
        return displayValue(object).flatMap { clipped($0) }
    }

    private static func commandSummary(_ payload: [String: Any]) -> String? {
        let command = displayValue(payload["command"])
            ?? displayValue(payload["cmd"])
        return prefixed("Bash", clipped(command))
    }

    private static func toolSummary(_ payload: [String: Any]) -> String? {
        let name = payload["tool_name"] as? String
            ?? payload["name"] as? String
            ?? payload["app_name"] as? String
        let detail = clipped(payload["reason"] as? String)
            ?? clipped(payload["message"] as? String)
        return prefixed(name, detail)
    }

    private static func tokenUsage(from payload: [String: Any]) -> TokenUsage? {
        guard let info = payload["info"] as? [String: Any],
              let total = info["total_token_usage"] as? [String: Any] else {
            return nil
        }
        return TokenUsage(
            input: integer(total["input_tokens"]),
            cachedInput: integer(total["cached_input_tokens"]),
            output: integer(total["output_tokens"]),
            reasoningOutput: integer(total["reasoning_output_tokens"]),
            total: integer(total["total_tokens"])
        )
    }

    private static func integer(_ value: Any?) -> Int {
        (value as? NSNumber)?.intValue ?? 0
    }

    private static func displayValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let strings as [String]:
            return strings.joined(separator: " ")
        case let values as [Any]:
            return values.compactMap(displayValue).joined(separator: " ")
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func prefixed(_ prefix: String?, _ detail: String?) -> String? {
        switch (clipped(prefix, limit: 60), clipped(detail)) {
        case let (prefix?, detail?): return "\(prefix) \(detail)"
        case let (prefix?, nil): return prefix
        case let (nil, detail?): return detail
        case (nil, nil): return nil
        }
    }

    private static func parseTimestamp(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func fileSize(at url: URL) -> UInt64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    private static func clipped(_ value: String?, limit: Int = 220) -> String? {
        guard let value else {
            return nil
        }
        let normalized = value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return nil
        }
        return String(normalized.prefix(limit))
    }
}
