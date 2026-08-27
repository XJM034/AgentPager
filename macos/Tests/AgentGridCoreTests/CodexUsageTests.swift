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

    let snapshot = try #require(CodexUsageLoader().load(fromRootURL: root))
    #expect(snapshot.planType == "pro")
    #expect(snapshot.windows.map(\.label) == ["5h", "7d"])
    #expect(snapshot.windows[0].remainingPercentage == 75)
    #expect(snapshot.windows[1].remainingPercentage == 9)
}

@Test("用量解析器同时保留通用额度和 Spark 双窗口")
func usageLoaderKeepsGeneralAndSparkQuotaGroups() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let file = root.appendingPathComponent("rollout-switching-limits.jsonl")
    try Data("""
    {"timestamp":"2026-08-27T05:33:04.510Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"plan_type":"pro","limit_id":"codex","primary":{"used_percent":8,"window_minutes":10080,"resets_at":1788304521}}}}
    {"timestamp":"2026-08-27T05:30:21.040Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"plan_type":"pro","limit_id":"codex_bengalfox","limit_name":"GPT-5.3-Codex-Spark","primary":{"used_percent":0,"window_minutes":300,"resets_at":1787826616},"secondary":{"used_percent":0,"window_minutes":10080,"resets_at":1788413416}}}}
    {"timestamp":"2026-08-27T05:50:13.774Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"plan_type":"pro","limit_id":"codex","primary":{"used_percent":9,"window_minutes":10080,"resets_at":1788304521}}}}
    """.utf8).write(to: file)

    let snapshot = try #require(CodexUsageLoader().load(fromRootURL: root))

    #expect(snapshot.limitID == "codex")
    #expect(snapshot.windows.map(\.remainingPercentage) == [91])
    #expect(snapshot.quotaGroups.map(\.id) == ["codex", "codex_bengalfox"])
    #expect(snapshot.quotaGroups[0].windows.map(\.label) == ["7d"])
    #expect(snapshot.quotaGroups[1].name == "GPT-5.3-Codex-Spark")
    #expect(snapshot.quotaGroups[1].windows.map(\.label) == ["5h", "7d"])
}

@Test("跨文件额度乱序时保留 capturedAt 更新的 Spark")
func usageLoaderKeepsNewestSparkAcrossFiles() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let newerFile = root.appendingPathComponent("rollout-newer-file.jsonl")
    try Data("""
    {"timestamp":"2026-08-27T12:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"plan_type":"pro","limit_id":"codex","primary":{"used_percent":8,"window_minutes":10080}}}}
    {"timestamp":"2026-08-25T08:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"plan_type":"pro","limit_id":"codex_bengalfox","limit_name":"GPT-5.3-Codex-Spark","primary":{"used_percent":80,"window_minutes":300}}}}
    """.utf8).write(to: newerFile)

    let olderFile = root.appendingPathComponent("rollout-older-file.jsonl")
    try Data("""
    {"timestamp":"2026-08-27T11:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"plan_type":"pro","limit_id":"codex_bengalfox","limit_name":"GPT-5.3-Codex-Spark","primary":{"used_percent":20,"window_minutes":300}}}}
    """.utf8).write(to: olderFile)

    let newerModificationDate = try #require(
        ISO8601DateFormatter().date(from: "2026-08-27T13:00:00Z")
    )
    let olderModificationDate = try #require(
        ISO8601DateFormatter().date(from: "2026-08-27T12:30:00Z")
    )
    try FileManager.default.setAttributes(
        [.modificationDate: newerModificationDate],
        ofItemAtPath: newerFile.path
    )
    try FileManager.default.setAttributes(
        [.modificationDate: olderModificationDate],
        ofItemAtPath: olderFile.path
    )

    let now = try #require(
        ISO8601DateFormatter().date(from: "2026-08-27T14:00:00Z")
    )
    let snapshot = try #require(
        CodexUsageLoader().load(fromRootURL: root, now: now)
    )
    let spark = try #require(
        snapshot.quotaGroups.first(where: { $0.id == "codex_bengalfox" })
    )

    #expect(spark.capturedAt == ISO8601DateFormatter().date(from: "2026-08-27T11:00:00Z"))
    #expect(spark.windows.map(\.remainingPercentage) == [80])
}

@Test("额度文件未变化时复用缓存，变化后重新解析")
func usageLoaderCachesQuotaFilesByMetadata() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let file = root.appendingPathComponent("rollout-cache.jsonl")
    let firstContents = """
    {"timestamp":"2026-08-27T12:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"plan_type":"pro","limit_id":"codex","primary":{"used_percent":8,"window_minutes":10080}}}}
    """
    let changedContents = firstContents.replacingOccurrences(
        of: "\"used_percent\":8",
        with: "\"used_percent\":9"
    )
    #expect(firstContents.utf8.count == changedContents.utf8.count)
    try Data(firstContents.utf8).write(to: file)

    let originalModificationDate = try #require(
        ISO8601DateFormatter().date(from: "2026-08-27T12:30:00Z")
    )
    try FileManager.default.setAttributes(
        [.modificationDate: originalModificationDate],
        ofItemAtPath: file.path
    )
    let now = try #require(
        ISO8601DateFormatter().date(from: "2026-08-27T14:00:00Z")
    )
    let loader = CodexUsageLoader()

    let first = try #require(loader.load(fromRootURL: root, now: now))
    #expect(first.windows.map(\.remainingPercentage) == [92])

    try Data(changedContents.utf8).write(to: file)
    try FileManager.default.setAttributes(
        [.modificationDate: originalModificationDate],
        ofItemAtPath: file.path
    )
    let cached = try #require(loader.load(fromRootURL: root, now: now))
    #expect(cached.windows.map(\.remainingPercentage) == [92])

    try FileManager.default.setAttributes(
        [.modificationDate: originalModificationDate.addingTimeInterval(60)],
        ofItemAtPath: file.path
    )
    let refreshed = try #require(loader.load(fromRootURL: root, now: now))
    #expect(refreshed.windows.map(\.remainingPercentage) == [91])
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
        CodexUsageLoader().load(
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
        CodexUsageLoader().load(
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
        CodexUsageLoader().load(
            fromRootURL: root,
            now: now,
            calendar: calendar
        )
    )

    #expect(snapshot.dailyUsage[snapshot.dailyUsage.count - 2].totalTokens == 0)
    #expect(snapshot.dailyUsage.last?.totalTokens == 250)
    #expect(snapshot.dailyUsage.last?.cachedInputTokens == 50)
}
