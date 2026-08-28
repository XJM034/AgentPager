import Foundation

/// ZCode 当前公开的 Hook 事件名。Issue #4 只归约核心监控事件；权限与失败事件
/// 先保留可解码能力，具体产品行为分别留给后续 Ticket。
public enum ZCodeHookEvent: String, Sendable {
    case sessionStart = "SessionStart"
    case userPromptSubmit = "UserPromptSubmit"
    case preToolUse = "PreToolUse"
    case permissionRequest = "PermissionRequest"
    case postToolUse = "PostToolUse"
    case postToolUseFailure = "PostToolUseFailure"
    case stop = "Stop"
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

    public init(
        sessionID: String,
        hookEventName: String,
        cwd: String,
        prompt: String? = nil,
        toolName: String? = nil,
        toolInput: HookJSONValue? = nil,
        toolUseID: String? = nil
    ) {
        self.sessionID = sessionID
        self.hookEventName = hookEventName
        self.cwd = cwd
        self.prompt = prompt
        self.toolName = toolName
        self.toolInput = toolInput
        self.toolUseID = toolUseID
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
        toolUseID = try container.decodeAliasIfPresent(
            String.self,
            primary: "tool_use_id",
            fallback: "toolUseId"
        )
    }

    public var event: ZCodeHookEvent? {
        ZCodeHookEvent(rawValue: hookEventName)
    }

    public var projectName: String {
        let name = URL(fileURLWithPath: cwd).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "ZCode" : String(name.prefix(48))
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
}

/// 写入 ZCode 用户配置 `hooks.events` 的最小 Issue #4 安装变换。
///
/// 这里只管理五个会话监控事件；权限、失败处理、卸载与完整恢复留给后续 Ticket。
public enum ZCodeHookInstaller {
    public static let managedStatusMessage = "Managed by AgentPager (ZCode)"
    public static let coreEventNames = [
        "SessionStart",
        "UserPromptSubmit",
        "PreToolUse",
        "PostToolUse",
        "Stop",
    ]

    public static func install(
        existingData: Data?,
        command: String
    ) throws -> HookFileMutation {
        var root = try rootObject(existingData)
        var hooks = try dictionary(root["hooks"], field: "hooks")
        var events = try dictionary(hooks["events"], field: "hooks.events")

        for eventName in coreEventNames {
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
        return coreEventNames.allSatisfy { eventName in
            guard let eventGroups = events[eventName] as? [[String: Any]] else {
                return false
            }
            return eventGroups.contains { isCurrentManaged($0, command: command) }
        }
    }

    private static func managedGroup(command: String) -> [String: Any] {
        [
            "hooks": [[
                "type": "process",
                "command": command,
                "args": ["--source", "zcode"],
                "enabled": true,
                "timeoutMs": 10_000,
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
