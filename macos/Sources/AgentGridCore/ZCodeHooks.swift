import CryptoKit
import Foundation

/// ZCode 当前公开的七类 Hook 事件名。Issue #5 只观察本地权限等待；
/// 手机裁决与 stdout 决策仍由 Issue #6 负责。
public enum ZCodeHookEvent: String, Sendable {
    case sessionStart = "SessionStart"
    case userPromptSubmit = "UserPromptSubmit"
    case preToolUse = "PreToolUse"
    case permissionRequest = "PermissionRequest"
    case postToolUse = "PostToolUse"
    case postToolUseFailure = "PostToolUseFailure"
    case stop = "Stop"
}

/// 只保留可安全诊断的错误类别，不保存 ZCode 的错误正文或响应内容。
public enum ZCodeErrorCategory: String, Equatable, Sendable {
    case notFound
    case permissionDenied
    case timeout
    case cancelled
    case invalidInput
    case toolFailure
}

public enum ZCodePermissionRequestState: String, Equatable, Sendable {
    case pending
    case approved
    case denied
    case expired
    case cancelled

    public var userFacingDescription: String {
        switch self {
        case .pending: "仍在等待"
        case .approved: "已批准"
        case .denied: "已拒绝"
        case .expired: "已过期"
        case .cancelled: "已取消"
        }
    }
}

public enum ZCodePermissionResolutionError: LocalizedError, Equatable {
    case unknownRequest
    case completed(ZCodePermissionRequestState)
    case unavailable

    public var errorDescription: String? {
        switch self {
        case .unknownRequest: "未知的 ZCode 权限请求"
        case let .completed(state): "ZCode 权限请求\(state.userFacingDescription)"
        case .unavailable: "ZCode 权限通道不可用"
        }
    }
}

/// ZCode 外层 Hook、CLI 客户端与 Bridge 等待使用同一组有界时间。
/// Bridge 最先结束，CLI 其次，始终给 ZCode 外层超时保留十秒清理余量。
public enum ZCodePermissionTiming {
    public static let bridgeDecisionTimeoutMilliseconds = 45_000
    public static let clientResponseTimeoutMilliseconds = 50_000
    public static let hookOuterTimeoutMilliseconds = 60_000
    public static let terminalHistoryLimit = 512
}

/// Gate 0 已验证的 ZCode `PermissionRequest` stdout 契约。
/// fallback 必须保持空输出，将裁决交还 ZCode 本地权限卡片。
public enum ZCodeHookOutput {
    private struct PermissionResponse: Encodable {
        var hookSpecificOutput: SpecificOutput

        struct SpecificOutput: Encodable {
            var decision: Decision
            var hookEventName = ZCodeHookEvent.permissionRequest.rawValue
        }

        struct Decision: Encodable {
            var behavior: CodexPermissionDecision
        }
    }

    public static let fallback = Data()

    public static func permission(_ decision: CodexPermissionDecision) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(
            PermissionResponse(
                hookSpecificOutput: .init(decision: .init(behavior: decision))
            )
        )
        data.append(UInt8(ascii: "\n"))
        return data
    }
}

/// pending request ID 只暴露来源与不可逆摘要；原始 Session/tool 标识不进入手机快照。
public enum ZCodePendingRequestID {
    public static func make(sessionID: String, toolUseID: String?) -> String? {
        guard !sessionID.isEmpty, let toolUseID, !toolUseID.isEmpty else {
            return nil
        }
        let material = Data("zcode\u{0}\(sessionID)\u{0}\(toolUseID)".utf8)
        let digest = SHA256.hash(data: material)
            .map { String(format: "%02x", $0) }
            .joined()
        return "zcode:\(digest)"
    }
}

/// ZCode 通过 stdin 发送的 Hook 载荷。
///
/// Gate 0 已确认同一版本同时出现 snake_case 与 camelCase 字段，因此解码器
/// 明确接受两套别名。原始 prompt、工具输入与响应只在当前 Hook 处理过程中存在，
/// 不由这个类型写入日志或持久化。
public struct ZCodeHookPayload: Decodable, Equatable, Sendable {
    public var sessionID: String
    public var hookEventName: String
    public var cwd: String
    public var prompt: String?
    public var toolName: String?
    public var toolInput: HookJSONValue?
    public var toolUseID: String?
    public var requestID: String?
    public var errorCategory: ZCodeErrorCategory?

    public init(
        sessionID: String,
        hookEventName: String,
        cwd: String,
        prompt: String? = nil,
        toolName: String? = nil,
        toolInput: HookJSONValue? = nil,
        toolUseID: String? = nil,
        requestID: String? = nil,
        errorCategory: ZCodeErrorCategory? = nil
    ) {
        self.sessionID = sessionID
        self.hookEventName = hookEventName
        self.cwd = cwd
        self.prompt = prompt
        self.toolName = toolName
        self.toolInput = toolInput
        self.toolUseID = toolUseID
        self.requestID = requestID
        self.errorCategory = errorCategory
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Field.self)
        sessionID = try container.decodeAlias(
            String.self,
            primary: "session_id",
            fallback: "sessionId"
        )
        hookEventName = try container.decodeAlias(
            String.self,
            primary: "hook_event_name",
            fallback: "hookEventName"
        )
        cwd = try container.decodeIfPresent(String.self, forKey: Field("cwd")) ?? ""
        prompt = try container.decodeIfPresent(String.self, forKey: Field("prompt"))
        toolName = try container.decodeAliasIfPresent(
            String.self,
            primary: "tool_name",
            fallback: "toolName"
        )
        toolInput = try container.decodeAliasIfPresent(
            HookJSONValue.self,
            primary: "tool_input",
            fallback: "toolInput"
        )
        toolUseID = try container.decodeFirstIfPresent(
            String.self,
            keys: ["tool_use_id", "toolUseId", "toolUseID", "tool_call_id", "toolCallId"]
        )
        requestID = try container.decodeFirstIfPresent(
            String.self,
            keys: ["request_id", "requestId"]
        )

        let error = try container.decodeFirstIfPresent(
            HookJSONValue.self,
            keys: ["error"]
        )
        let errorDetails = try container.decodeFirstIfPresent(
            HookJSONValue.self,
            keys: ["error_details", "errorDetails"]
        )
        if hookEventName == ZCodeHookEvent.postToolUseFailure.rawValue {
            errorCategory = Self.classifyError(error, details: errorDetails)
        } else {
            errorCategory = nil
        }
    }

    public var event: ZCodeHookEvent? {
        ZCodeHookEvent(rawValue: hookEventName)
    }

    public var projectName: String {
        let url = URL(fileURLWithPath: cwd).standardizedFileURL
        let components = url.pathComponents
        if components.count == 3, components[1] == "Users" {
            return "ZCode"
        }
        let name = url.lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "ZCode" : String(name.prefix(48))
    }

    private static func classifyError(
        _ error: HookJSONValue?,
        details: HookJSONValue?
    ) -> ZCodeErrorCategory {
        let text = [error, details]
            .compactMap { $0 }
            .flatMap(\.diagnosticStrings)
            .joined(separator: " ")
            .lowercased()

        if text.contains("no such file") || text.contains("not found") {
            return .notFound
        }
        if text.contains("permission denied") || text.contains("not permitted") {
            return .permissionDenied
        }
        if text.contains("timed out") || text.contains("timeout") {
            return .timeout
        }
        if text.contains("cancelled") || text.contains("canceled") {
            return .cancelled
        }
        if text.contains("invalid") || text.contains("malformed") {
            return .invalidInput
        }
        return .toolFailure
    }
}

private extension HookJSONValue {
    var diagnosticStrings: [String] {
        switch self {
        case let .string(value):
            [value]
        case let .object(value):
            value.values.flatMap(\.diagnosticStrings)
        case let .array(value):
            value.flatMap(\.diagnosticStrings)
        case .number, .boolean, .null:
            []
        }
    }
}

private struct Field: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        return nil
    }
}

private extension KeyedDecodingContainer where Key == Field {
    func decodeAlias<T: Decodable>(
        _ type: T.Type,
        primary: String,
        fallback: String
    ) throws -> T {
        if let value = try decodeIfPresent(type, forKey: Field(primary)) {
            return value
        }
        return try decode(type, forKey: Field(fallback))
    }

    func decodeAliasIfPresent<T: Decodable>(
        _ type: T.Type,
        primary: String,
        fallback: String
    ) throws -> T? {
        try decodeIfPresent(type, forKey: Field(primary))
            ?? decodeIfPresent(type, forKey: Field(fallback))
    }

    func decodeFirstIfPresent<T: Decodable>(
        _ type: T.Type,
        keys: [String]
    ) throws -> T? {
        for key in keys {
            if let value = try decodeIfPresent(type, forKey: Field(key)) {
                return value
            }
        }
        return nil
    }
}

/// 写入 ZCode 用户配置 `hooks.events` 的 AgentPager 管理变换。
public enum ZCodeHookInstaller {
    public static let managedStatusMessage = "Managed by AgentPager (ZCode)"
    private static let orderedEventNames = [
        "SessionStart",
        "UserPromptSubmit",
        "PreToolUse",
        "PermissionRequest",
        "PostToolUse",
        "PostToolUseFailure",
        "Stop",
    ]
    public static let managedEventNames = Set(orderedEventNames)

    public static func install(
        existingData: Data?,
        command: String
    ) throws -> HookFileMutation {
        var root = try rootObject(existingData)
        var hooks = try dictionary(root["hooks"], field: "hooks")
        var events = try dictionary(hooks["events"], field: "hooks.events")

        for eventName in orderedEventNames {
            let existingGroups = try groups(events[eventName], eventName: eventName)
            let userGroups = preservingThirdPartyHooks(in: existingGroups)
            events[eventName] = userGroups + [managedGroup(command: command)]
        }
        hooks["enabled"] = true
        hooks["events"] = events
        root["hooks"] = hooks

        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        return HookFileMutation(
            contents: data,
            changed: data != existingData,
            hasRemainingHooks: true
        )
    }

    public static func isInstalled(data: Data?, command: String) -> Bool {
        guard let root = try? rootObject(data),
              let hooks = root["hooks"] as? [String: Any],
              hooks["enabled"] as? Bool == true,
              let events = hooks["events"] as? [String: Any] else {
            return false
        }
        return orderedEventNames.allSatisfy { eventName in
            guard let eventGroups = events[eventName] as? [[String: Any]] else {
                return false
            }
            return eventGroups.contains { isCurrentManaged($0, command: command) }
        }
    }

    public static func containsManagedHooks(data: Data?) -> Bool {
        guard let root = try? rootObject(data),
              let hooks = root["hooks"] as? [String: Any],
              let events = hooks["events"] as? [String: Any] else {
            return false
        }
        return orderedEventNames.contains { eventName in
            guard let groups = events[eventName] as? [[String: Any]] else {
                return false
            }
            return groups.contains(where: groupContainsManagedHook)
        }
    }

    public static func uninstall(existingData: Data?) throws -> HookFileMutation {
        var root = try rootObject(existingData)
        var hooks = try dictionary(root["hooks"], field: "hooks")
        var events = try dictionary(hooks["events"], field: "hooks.events")
        var removedManagedHook = false

        for eventName in orderedEventNames {
            let existingGroups = try groups(events[eventName], eventName: eventName)
            if existingGroups.contains(where: groupContainsManagedHook) {
                removedManagedHook = true
            }
            let remainingGroups = preservingThirdPartyHooks(in: existingGroups)
            if remainingGroups.isEmpty {
                events.removeValue(forKey: eventName)
            } else {
                events[eventName] = remainingGroups
            }
        }

        guard removedManagedHook else {
            return HookFileMutation(
                contents: existingData,
                changed: false,
                hasRemainingHooks: containsAnyHook(events)
            )
        }

        hooks["events"] = events
        root["hooks"] = hooks
        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        return HookFileMutation(
            contents: data,
            changed: true,
            hasRemainingHooks: containsAnyHook(events)
        )
    }

    private static func managedGroup(command: String) -> [String: Any] {
        [
            "hooks": [[
                "type": "process",
                "command": command,
                "args": ["--source", "zcode"],
                "enabled": true,
                "timeoutMs": ZCodePermissionTiming.hookOuterTimeoutMilliseconds,
                "statusMessage": managedStatusMessage,
            ]],
        ]
    }

    private static func preservingThirdPartyHooks(
        in groups: [[String: Any]]
    ) -> [[String: Any]] {
        groups.compactMap { group in
            guard let hooks = group["hooks"] as? [[String: Any]],
                  hooks.contains(where: isManagedHook) else {
                return group
            }
            let remainingHooks = hooks.filter { !isManagedHook($0) }
            guard !remainingHooks.isEmpty else { return nil }
            var preservedGroup = group
            preservedGroup["hooks"] = remainingHooks
            return preservedGroup
        }
    }

    private static func isManagedHook(_ hook: [String: Any]) -> Bool {
        hook["statusMessage"] as? String == managedStatusMessage
    }

    private static func groupContainsManagedHook(_ group: [String: Any]) -> Bool {
        guard let hooks = group["hooks"] as? [[String: Any]] else {
            return false
        }
        return hooks.contains(where: isManagedHook)
    }

    private static func containsAnyHook(_ events: [String: Any]) -> Bool {
        events.values.contains { value in
            guard let groups = value as? [[String: Any]] else { return false }
            return groups.contains { group in
                guard let hooks = group["hooks"] as? [[String: Any]] else {
                    return false
                }
                return !hooks.isEmpty
            }
        }
    }

    private static func isCurrentManaged(
        _ group: [String: Any],
        command: String
    ) -> Bool {
        guard let hooks = group["hooks"] as? [[String: Any]] else {
            return false
        }
        return hooks.contains { hook in
            hook["statusMessage"] as? String == managedStatusMessage
                && hook["type"] as? String == "process"
                && hook["command"] as? String == command
                && hook["args"] as? [String] == ["--source", "zcode"]
                && hook["enabled"] as? Bool == true
                && hook["timeoutMs"] as? Int ==
                    ZCodePermissionTiming.hookOuterTimeoutMilliseconds
        }
    }

    private static func rootObject(_ data: Data?) throws -> [String: Any] {
        guard let data, !data.isEmpty else { return [:] }
        let value = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = value as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return dictionary
    }

    private static func dictionary(
        _ value: Any?,
        field: String
    ) throws -> [String: Any] {
        guard let value else { return [:] }
        guard let dictionary = value as? [String: Any] else {
            throw ZCodeHookConfigurationError.invalidObject(field)
        }
        return dictionary
    }

    private static func groups(
        _ value: Any?,
        eventName: String
    ) throws -> [[String: Any]] {
        guard let value else { return [] }
        guard let groups = value as? [[String: Any]] else {
            throw ZCodeHookConfigurationError.invalidEvent(eventName)
        }
        guard groups.allSatisfy({ $0["hooks"] is [[String: Any]] }) else {
            throw ZCodeHookConfigurationError.invalidEvent(eventName)
        }
        return groups
    }
}

public enum ZCodeHookConfigurationError: LocalizedError, Equatable {
    case invalidObject(String)
    case invalidEvent(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidObject(field):
            "ZCode 配置字段 \(field) 不是对象，未执行覆盖"
        case let .invalidEvent(event):
            "ZCode Hook 事件 \(event) 不是数组，未执行覆盖"
        }
    }
}
