import Foundation
import Testing
@testable import AgentGridCore

@Test("实时额度优先当前 codex 桶，重置后的 100% 不被旧 16% 和 Spark 覆盖")
func accountUsagePrefersCurrentBucket() throws {
    let now = Date(timeIntervalSince1970: 1_789_900_000)
    let data = Data(#"{"rateLimits":{"limitId":"codex","primary":{"usedPercent":84,"windowDurationMins":10080}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","planType":"pro","primary":{"usedPercent":0,"windowDurationMins":10080,"resetsAt":1790474255}},"codex_bengalfox":{"limitId":"codex_bengalfox","primary":{"usedPercent":90,"windowDurationMins":300}}}}"#.utf8)
    let snapshot = try #require(CodexAccountUsageLoader.parse(data, now: now))
    #expect(snapshot.quotaGroups.map(\.id) == ["codex"])
    #expect(snapshot.windows.map(\.remainingPercentage) == [100])
    #expect(snapshot.windows.map(\.label) == ["7d"])
    #expect(snapshot.windows.first?.resetsAt == Date(timeIntervalSince1970: 1_790_474_255))
    #expect(snapshot.capturedAt == now)
    #expect(snapshot.dailyUsage.isEmpty)
}

@Test("兼容旧实时响应并保留五小时与每周窗口")
func accountUsageSupportsLegacyResponse() throws {
    let data = Data(#"{"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":300},"secondary":{"usedPercent":84,"windowDurationMins":10080}}}"#.utf8)
    let snapshot = try #require(CodexAccountUsageLoader.parse(data, now: .now))
    #expect(snapshot.windows.map(\.remainingPercentage) == [75, 16])
    #expect(snapshot.windows.map(\.label) == ["5h", "7d"])
}

@Test("不可用、损坏或只有 Spark 的响应不能伪造成当前额度", arguments: [
    "{}", "invalid", #"{"error":{"code":-1}}"#,
    #"{"rateLimits":{"primary":{"usedPercent":84,"windowDurationMins":10080}},"rateLimitsByLimitId":{}}"#,
    #"{"rateLimits":{"limitId":"codex_bengalfox","primary":{"usedPercent":0,"windowDurationMins":300}}}"#,
    #"{"rateLimits":{"limitName":"GPT-5.3-Codex-Spark","primary":{"usedPercent":0,"windowDurationMins":300}}}"#,
    #"{"rateLimits":{"primary":{"usedPercent":-1,"windowDurationMins":300}}}"#,
    #"{"rateLimits":{"primary":{"usedPercent":0,"windowDurationMins":0}}}"#,
    #"{"rateLimits":{"primary":null,"secondary":null}}"#,
])
func accountUsageRejectsUnavailable(_ json: String) {
    #expect(CodexAccountUsageLoader.parse(Data(json.utf8), now: .now) == nil)
}

@Test("只读客户端完成握手、忽略通知、读取额度并回收子进程")
func accountUsageStdioHandshake() throws {
    let script = """
    #!/bin/sh
    IFS= read -r line
    case "$line" in *initialize*) ;; *) exit 2;; esac
    printf '%s\\n' '{"id":1,"result":{}}' '{"method":"notice"}'
    IFS= read -r line
    case "$line" in *initialized*) ;; *) exit 3;; esac
    IFS= read -r line
    case "$line" in *account/rateLimits/read*) ;; *) exit 4;; esac
    printf '%s\\n' '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":0,"windowDurationMins":10080}}}}'
    IFS= read -r line
    """
    try withAccountUsageExecutable(script) { url in
        let data = try #require(CodexAccountUsageLoader.request(executableURL: url, timeout: 2))
        #expect(CodexAccountUsageLoader.parse(data, now: .now)?.windows.first?.remainingPercentage == 100)
    }
}

@Test("查询超时、子进程退出和服务端错误都会结束而不是卡住刷新", arguments: [
    "#!/bin/sh\ntrap '' TERM\nwhile IFS= read -r line; do :; done\n",
    "#!/bin/sh\nexit 1\n",
    "#!/bin/sh\nIFS= read -r line\nprintf '%s\\n' '{\"id\":1,\"error\":{\"code\":-1}}'\n",
])
func accountUsageStdioFailure(_ script: String) throws {
    try withAccountUsageExecutable(script) { url in
        let start = ProcessInfo.processInfo.systemUptime
        #expect(CodexAccountUsageLoader.request(executableURL: url, timeout: 0.15) == nil)
        #expect(ProcessInfo.processInfo.systemUptime - start < 2)
    }
}

private func withAccountUsageExecutable(_ script: String, body: (URL) throws -> Void) throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data(script.utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    defer { try? FileManager.default.removeItem(at: url) }
    try body(url)
}
