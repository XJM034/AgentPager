import Foundation

public struct CodexRolloutSignal: Equatable, Sendable {
    public var sessionID: String
    public var cwd: String
    public var lifecycle: AgentLifecycle
    public var activity: AgentActivity?
    public var requestKind: PendingRequestKind?
    public var summary: String?
    public var timestamp: Date

    public init(
        sessionID: String,
        cwd: String,
        lifecycle: AgentLifecycle,
        activity: AgentActivity?,
        requestKind: PendingRequestKind? = nil,
        summary: String? = nil,
        timestamp: Date = .now
    ) {
        self.sessionID = sessionID
        self.cwd = cwd
        self.lifecycle = lifecycle
        self.activity = activity
        self.requestKind = requestKind
        self.summary = summary
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
        guard
            let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            root["type"] as? String == "event_msg",
            let payload = root["payload"] as? [String: Any],
            let type = payload["type"] as? String
        else {
            return nil
        }

        let timestamp = (root["timestamp"] as? String)
            .flatMap { ISO8601DateFormatter().date(from: $0) } ?? now

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
        case "exec_command_begin", "terminal_interaction":
            return signal(.running, .executing, timestamp: timestamp)
        case "patch_apply_begin", "patch_apply_updated":
            return signal(.running, .editing, timestamp: timestamp)
        case "mcp_tool_call_begin", "dynamic_tool_call_request":
            return signal(.running, .executing, timestamp: timestamp)
        case "web_search_begin", "web_search_end":
            return signal(.running, .browsing, timestamp: timestamp)
        case "image_generation_begin", "image_generation_end",
             "view_image_tool_call":
            return signal(.running, .reading, timestamp: timestamp)
        case "plan_update":
            return signal(.running, .thinking, timestamp: timestamp)
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
            _ lifecycle: AgentLifecycle,
            _ activity: AgentActivity?,
            kind: PendingRequestKind? = nil,
            summary: String? = nil,
            timestamp: Date
        ) -> CodexRolloutSignal {
            CodexRolloutSignal(
                sessionID: sessionID,
                cwd: cwd,
                lifecycle: lifecycle,
                activity: activity,
                requestKind: kind,
                summary: summary,
                timestamp: timestamp
            )
        }
    }

    private static func fileSize(at url: URL) -> UInt64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    private static func clipped(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let normalized = value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return nil
        }
        return String(normalized.prefix(180))
    }
}
