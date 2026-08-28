import Foundation

public enum AgentSource: String, Codable, Sendable {
    case codexDesktop
    case codexCLI
    case claudeCode
    case zcode
    case unknown

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .unknown
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum AgentLifecycle: String, Codable, CaseIterable, Sendable {
    case offline
    case idle
    case starting
    case running
    case waitingApproval
    case waitingAnswer
    case succeeded
    case interrupted

    public var attentionPriority: Int {
        switch self {
        case .waitingApproval: 600
        case .waitingAnswer: 500
        case .succeeded: 300
        case .starting, .running: 200
        case .offline, .idle, .interrupted: 100
        }
    }
}

public enum AgentActivity: String, Codable, CaseIterable, Sendable {
    case thinking
    case reading
    case searching
    case editing
    case executing
    case testing
    case browsing
    case delegating
}

public enum TaskCapability: String, Codable, CaseIterable, Sendable {
    case approve
    case deny
    case answer
    case interrupt
    case retry
}

public struct TokenUsage: Codable, Equatable, Sendable {
    public var input: Int
    public var cachedInput: Int
    public var output: Int
    public var reasoningOutput: Int
    public var total: Int

    public init(
        input: Int = 0,
        cachedInput: Int = 0,
        output: Int = 0,
        reasoningOutput: Int = 0,
        total: Int = 0
    ) {
        self.input = input
        self.cachedInput = cachedInput
        self.output = output
        self.reasoningOutput = reasoningOutput
        self.total = total
    }
}

public struct SubagentSnapshot: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var path: String
    public var displayName: String
    public var lifecycle: AgentLifecycle
    public var activity: AgentActivity?
    /// 只存在内存和实时协议中，绝不写入任务快照文件。
    public var latestStep: String?
    public var tokenUsage: TokenUsage?
    public var startedAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        path: String,
        displayName: String? = nil,
        lifecycle: AgentLifecycle = .running,
        activity: AgentActivity? = .thinking,
        latestStep: String? = nil,
        tokenUsage: TokenUsage? = nil,
        startedAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.path = path
        self.displayName = displayName ?? Self.name(from: path)
        self.lifecycle = lifecycle
        self.activity = activity
        self.latestStep = latestStep
        self.tokenUsage = tokenUsage
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }

    public var isTerminal: Bool {
        [.succeeded, .interrupted].contains(lifecycle)
    }

    public func elapsed(at now: Date = .now) -> TimeInterval {
        max(0, (isTerminal ? updatedAt : now).timeIntervalSince(startedAt))
    }

    public static func name(from path: String) -> String {
        let raw = path
            .split(separator: "/")
            .last
            .map(String.init)?
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        guard let first = raw.first else {
            return "Codex 子代理"
        }
        return String(first).uppercased() + raw.dropFirst()
    }
}

public struct TaskSnapshot: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var source: AgentSource
    public var projectName: String
    public var title: String
    /// 最近一条用户消息，只存在内存和实时协议中，绝不写入任务快照文件。
    public var userPrompt: String?
    /// 只存在内存和实时协议中，绝不写入任务快照文件。
    public var latestStep: String?
    public var tokenUsage: TokenUsage?
    /// 子代理的名称、步骤和用量只存在内存和实时协议中。
    public var subagents: [SubagentSnapshot]
    public var lifecycle: AgentLifecycle
    public var activity: AgentActivity?
    public var startedAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    public var isUnread: Bool
    public var isPinned: Bool
    public var isMuted: Bool
    public var capabilities: Set<TaskCapability>

    public init(
        id: String,
        source: AgentSource,
        projectName: String,
        title: String? = nil,
        userPrompt: String? = nil,
        latestStep: String? = nil,
        tokenUsage: TokenUsage? = nil,
        subagents: [SubagentSnapshot] = [],
        lifecycle: AgentLifecycle,
        activity: AgentActivity? = nil,
        startedAt: Date = .now,
        updatedAt: Date = .now,
        completedAt: Date? = nil,
        isUnread: Bool = false,
        isPinned: Bool = false,
        isMuted: Bool = false,
        capabilities: Set<TaskCapability> = []
    ) {
        self.id = id
        self.source = source
        self.projectName = projectName
        self.title = title ?? projectName
        self.userPrompt = userPrompt
        self.latestStep = latestStep
        self.tokenUsage = tokenUsage
        self.subagents = subagents
        self.lifecycle = lifecycle
        self.activity = activity
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.isUnread = isUnread
        self.isPinned = isPinned
        self.isMuted = isMuted
        self.capabilities = capabilities
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case source
        case projectName
        case title
        case userPrompt
        case latestStep
        case tokenUsage
        case subagents
        case lifecycle
        case activity
        case startedAt
        case updatedAt
        case completedAt
        case isUnread
        case isPinned
        case isMuted
        case capabilities
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        source = try container.decode(AgentSource.self, forKey: .source)
        projectName = try container.decode(String.self, forKey: .projectName)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? projectName
        userPrompt = try container.decodeIfPresent(String.self, forKey: .userPrompt)
        latestStep = try container.decodeIfPresent(String.self, forKey: .latestStep)
        tokenUsage = try container.decodeIfPresent(TokenUsage.self, forKey: .tokenUsage)
        subagents = try container.decodeIfPresent(
            [SubagentSnapshot].self,
            forKey: .subagents
        ) ?? []
        lifecycle = try container.decode(AgentLifecycle.self, forKey: .lifecycle)
        activity = try container.decodeIfPresent(AgentActivity.self, forKey: .activity)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        isUnread = try container.decodeIfPresent(Bool.self, forKey: .isUnread) ?? false
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        capabilities = try container.decodeIfPresent(
            Set<TaskCapability>.self,
            forKey: .capabilities
        ) ?? []
    }

    public var isTerminal: Bool {
        [.succeeded, .interrupted].contains(lifecycle)
    }

    public var effectivePriority: Int {
        var value = lifecycle.attentionPriority
        if isUnread && lifecycle == .succeeded {
            value += 50
        }
        if isPinned {
            value += 25
        }
        return value
    }
}

public struct UsageWindow: Identifiable, Codable, Equatable, Sendable {
    public var id: String { key }
    public var key: String
    public var label: String
    public var usedPercentage: Double
    public var remainingPercentage: Double
    public var windowMinutes: Int
    public var resetsAt: Date?
    public var quotaType: String?
    public var limitAmount: Double?
    public var usedAmount: Double?
    public var remainingAmount: Double?

    public init(
        key: String,
        label: String,
        usedPercentage: Double,
        remainingPercentage: Double,
        windowMinutes: Int,
        resetsAt: Date?,
        quotaType: String? = nil,
        limitAmount: Double? = nil,
        usedAmount: Double? = nil,
        remainingAmount: Double? = nil
    ) {
        self.key = key
        self.label = label
        self.usedPercentage = usedPercentage
        self.remainingPercentage = remainingPercentage
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
        self.quotaType = quotaType
        self.limitAmount = limitAmount
        self.usedAmount = usedAmount
        self.remainingAmount = remainingAmount
    }
}

public struct QuotaGroup: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String?
    public var capturedAt: Date?
    public var windows: [UsageWindow]

    public init(
        id: String,
        name: String?,
        capturedAt: Date?,
        windows: [UsageWindow]
    ) {
        self.id = id
        self.name = name
        self.capturedAt = capturedAt
        self.windows = windows
    }
}

public struct UsageProviderSnapshot: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var displayName: String?
    public var planName: String?
    /// 上游套餐等级只按原值转发，不能据此推断面向用户的套餐名称。
    public var planLevel: String?
    public var capturedAt: Date?
    public var status: String?
    public var quotaGroups: [QuotaGroup]

    public init(
        id: String,
        displayName: String? = nil,
        planName: String? = nil,
        planLevel: String? = nil,
        capturedAt: Date? = nil,
        status: String? = nil,
        quotaGroups: [QuotaGroup] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.planName = planName
        self.planLevel = planLevel
        self.capturedAt = capturedAt
        self.status = status
        self.quotaGroups = quotaGroups
    }
}

public struct DailyUsagePoint: Identifiable, Codable, Equatable, Sendable {
    public var id: String { date }
    public var date: String
    public var inputTokens: Int64
    public var cachedInputTokens: Int64
    public var outputTokens: Int64
    public var reasoningOutputTokens: Int64
    public var totalTokens: Int64
    public var estimatedCostUSD: Double?

    public init(
        date: String,
        inputTokens: Int64 = 0,
        cachedInputTokens: Int64 = 0,
        outputTokens: Int64 = 0,
        reasoningOutputTokens: Int64 = 0,
        totalTokens: Int64 = 0,
        estimatedCostUSD: Double? = nil
    ) {
        self.date = date
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.totalTokens = totalTokens
        self.estimatedCostUSD = estimatedCostUSD
    }
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public var capturedAt: Date?
    public var planType: String?
    public var limitID: String?
    public var limitName: String?
    public var windows: [UsageWindow]
    public var quotaGroups: [QuotaGroup]
    public var dailyUsage: [DailyUsagePoint]

    public init(
        capturedAt: Date?,
        planType: String?,
        limitID: String?,
        limitName: String? = nil,
        windows: [UsageWindow],
        quotaGroups: [QuotaGroup] = [],
        dailyUsage: [DailyUsagePoint] = []
    ) {
        self.capturedAt = capturedAt
        self.planType = planType
        self.limitID = limitID
        self.limitName = limitName
        self.windows = windows
        self.quotaGroups = quotaGroups
        self.dailyUsage = dailyUsage
    }
}

public enum ControlAction: String, Codable, Equatable, Sendable {
    case approve
    case deny
    case answer
    case interrupt
    case retry
    case mute
    case markRead
    case pin
}

public struct ControlPayload: Codable, Equatable, Sendable {
    public var taskID: String
    public var action: ControlAction
    public var value: String?
    public var pendingRequestID: String?

    public init(
        taskID: String,
        action: ControlAction,
        value: String? = nil,
        pendingRequestID: String? = nil
    ) {
        self.taskID = taskID
        self.action = action
        self.value = value
        self.pendingRequestID = pendingRequestID
    }
}

public enum ControlResult: String, Codable, Equatable, Sendable {
    case accepted
    case rejected
    case stale
    case unsupported
}
