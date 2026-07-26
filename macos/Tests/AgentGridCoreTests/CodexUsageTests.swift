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

