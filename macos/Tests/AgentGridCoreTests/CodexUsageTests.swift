import Foundation
import Testing
@testable import AgentGridCore

@Test("用量解析器读取双窗口和剩余比例")
func usageLoaderParsesWindows() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let file = root.appendingPathComponent("rollout-fixture.jsonl")
    let contents = """
    {"timestamp":"2026-07-26T10:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"plan_type":"pro","limit_id":"codex","primary":{"used_percent":25,"window_minutes":300,"resets_at":1785067200},"secondary":{"used_percent":"91","window_minutes":"10080","resets_at":"1785672000"}}}}
    """
    try Data(contents.utf8).write(to: file)

    let snapshot = try #require(CodexUsageLoader.load(fromRootURL: root))
    #expect(snapshot.planType == "pro")
    #expect(snapshot.windows.map(\.label) == ["5h", "7d"])
    #expect(snapshot.windows[0].remainingPercentage == 75)
    #expect(snapshot.windows[1].remainingPercentage == 9)
}

@Test("近期用量优先读取单次增量并用累计差值兼容旧日志")
func usageLoaderAggregatesDailyTokenDeltas() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let file = root.appendingPathComponent("rollout-history.jsonl")
    let contents = """
    {"timestamp":"2026-07-25T08:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":800,"cached_input_tokens":200,"output_tokens":200,"reasoning_output_tokens":50,"total_tokens":1000},"last_token_usage":{"input_tokens":800,"cached_input_tokens":200,"output_tokens":200,"reasoning_output_tokens":50,"total_tokens":1000}}}}
    {"timestamp":"2026-07-25T09:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1200,"cached_input_tokens":300,"output_tokens":300,"reasoning_output_tokens":70,"total_tokens":1500}}}}
    {"timestamp":"2026-07-26T10:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1750,"cached_input_tokens":450,"output_tokens":450,"reasoning_output_tokens":100,"total_tokens":2200},"last_token_usage":{"input_tokens":550,"cached_input_tokens":150,"output_tokens":150,"reasoning_output_tokens":30,"total_tokens":700}},"rate_limits":{"primary":{"used_percent":25,"window_minutes":300,"resets_at":1785067200}}}}
    """
    try Data(contents.utf8).write(to: file)

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
    let now = try #require(
        ISO8601DateFormatter().date(from: "2026-07-26T12:00:00Z")
    )
    let snapshot = try #require(
        CodexUsageLoader.load(
            fromRootURL: root,
            now: now,
            calendar: calendar
        )
    )

    #expect(snapshot.dailyUsage.count == CodexUsageLoader.historyDayCount)
    #expect(snapshot.dailyUsage.suffix(3).map(\.date) == [
        "2026-07-24",
        "2026-07-25",
        "2026-07-26",
    ])
    #expect(snapshot.dailyUsage[snapshot.dailyUsage.count - 3].totalTokens == 0)
    #expect(snapshot.dailyUsage[snapshot.dailyUsage.count - 2].totalTokens == 1_500)
    #expect(snapshot.dailyUsage.last?.totalTokens == 700)
    #expect(snapshot.dailyUsage[snapshot.dailyUsage.count - 2].cachedInputTokens == 300)
    #expect(snapshot.dailyUsage.last?.cachedInputTokens == 150)
}

@Test("只有历史用量而没有额度窗口时仍返回快照")
func usageLoaderReturnsHistoryWithoutQuotaWindows() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let file = root.appendingPathComponent("rollout-history-only.jsonl")
    let contents = """
    {"timestamp":"2026-07-26T10:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":80,"output_tokens":20,"total_tokens":100}}}}
    """
    try Data(contents.utf8).write(to: file)

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
    let now = try #require(
        ISO8601DateFormatter().date(from: "2026-07-26T12:00:00Z")
    )
    let snapshot = try #require(
        CodexUsageLoader.load(
            fromRootURL: root,
            now: now,
            calendar: calendar
        )
    )

    #expect(snapshot.windows.isEmpty)
    #expect(snapshot.dailyUsage.last?.date == "2026-07-26")
    #expect(snapshot.dailyUsage.last?.totalTokens == 100)
}

@Test("大型会话只读取尾部累计值并及时生成历史用量")
func usageLoaderReadsLargeSessionTail() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let file = root.appendingPathComponent("rollout-large.jsonl")
    let first = """
    {"timestamp":"2026-07-25T08:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":80,"output_tokens":20,"total_tokens":100}}}}
    """
    let filler = String(repeating: "{}\n", count: 100_000)
    let latest = """
    {"timestamp":"2026-07-26T10:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":200,"cached_input_tokens":50,"output_tokens":50,"total_tokens":250}},"rate_limits":{"primary":{"used_percent":25,"window_minutes":300,"resets_at":1785067200}}}}
    """
    try Data((first + "\n" + filler + latest).utf8).write(to: file)

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
    let now = try #require(
        ISO8601DateFormatter().date(from: "2026-07-26T12:00:00Z")
    )
    let snapshot = try #require(
        CodexUsageLoader.load(
            fromRootURL: root,
            now: now,
            calendar: calendar
        )
    )

    #expect(snapshot.dailyUsage[snapshot.dailyUsage.count - 2].totalTokens == 0)
    #expect(snapshot.dailyUsage.last?.totalTokens == 250)
    #expect(snapshot.dailyUsage.last?.cachedInputTokens == 50)
}
