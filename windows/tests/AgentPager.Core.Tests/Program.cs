using AgentPager.Core;
using System.Globalization;
using System.Text;
using System.Text.Json;

namespace AgentPager.Core.Tests;

internal static class Program
{
    private static int Main()
    {
        var failures = new List<string>();
        Run("跨文件额度乱序时保留 capturedAt 更新的 Spark", KeepsNewestSparkAcrossFiles, failures);
        Run("额度文件未变化时复用缓存，变化后重新解析", CachesQuotaFilesByMetadata, failures);
        Run("新快照保留 ZCode、多提供方额度和待审批请求标识", DecodesExtendedProtocolFixture, failures);
        Run("未知来源和额度组可解析并兼容转发", ForwardsUnknownProtocolFixture, failures);
        Run("旧 Codex 快照缺少扩展字段时仍可解析", DecodesLegacyProtocolFixture, failures);
        Run("控制载荷兼容可选待审批请求标识", SupportsOptionalPendingRequestID, failures);

        if (failures.Count == 0)
        {
            Console.WriteLine("AgentPager.Core regression tests passed (6/6).");
            return 0;
        }

        foreach (var failure in failures) Console.Error.WriteLine(failure);
        return 1;
    }

    private static void Run(string name, Action test, List<string> failures)
    {
        try
        {
            test();
            Console.WriteLine("PASS: " + name);
        }
        catch (Exception error)
        {
            failures.Add("FAIL: " + name + "\n" + error);
        }
    }

    private static void KeepsNewestSparkAcrossFiles()
    {
        WithTemporaryDirectory(root =>
        {
            var newerFile = Path.Combine(root, "rollout-newer-file.jsonl");
            File.WriteAllText(newerFile, """
                {"timestamp":"2026-08-27T12:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"plan_type":"pro","limit_id":"codex","primary":{"used_percent":8,"window_minutes":10080}}}}
                {"timestamp":"2026-08-25T08:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"plan_type":"pro","limit_id":"codex_bengalfox","limit_name":"GPT-5.3-Codex-Spark","primary":{"used_percent":80,"window_minutes":300}}}}
                """);
            var olderFile = Path.Combine(root, "rollout-older-file.jsonl");
            File.WriteAllText(olderFile, """
                {"timestamp":"2026-08-27T11:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"plan_type":"pro","limit_id":"codex_bengalfox","limit_name":"GPT-5.3-Codex-Spark","primary":{"used_percent":20,"window_minutes":300}}}}
                """);
            File.SetLastWriteTimeUtc(newerFile, Utc("2026-08-27T13:00:00Z").UtcDateTime);
            File.SetLastWriteTimeUtc(olderFile, Utc("2026-08-27T12:30:00Z").UtcDateTime);

            var snapshot = Require(
                new CodexUsageLoader().LoadFromRoot(root, Utc("2026-08-27T14:00:00Z")),
                "未生成额度快照");
            var spark = snapshot.QuotaGroups.Single(group => group.Id == "codex_bengalfox");

            Equal(
                Utc("2026-08-27T11:00:00Z"),
                spark.CapturedAt ?? throw new InvalidOperationException("Spark 缺少 capturedAt"),
                "Spark capturedAt");
            Equal(80d, spark.Windows.Single().RemainingPercentage, "Spark 剩余额度");
        });
    }

    private static void CachesQuotaFilesByMetadata()
    {
        WithTemporaryDirectory(root =>
        {
            var file = Path.Combine(root, "rollout-cache.jsonl");
            var firstContents = """
                {"timestamp":"2026-08-27T12:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"plan_type":"pro","limit_id":"codex","primary":{"used_percent":8,"window_minutes":10080}}}}
                """;
            var changedContents = firstContents.Replace("\"used_percent\":8", "\"used_percent\":9");
            Equal(firstContents.Length, changedContents.Length, "测试数据长度");
            File.WriteAllText(file, firstContents);

            var originalModificationDate = Utc("2026-08-27T12:30:00Z");
            File.SetLastWriteTimeUtc(file, originalModificationDate.UtcDateTime);
            var now = Utc("2026-08-27T14:00:00Z");
            var loader = new CodexUsageLoader();

            var first = Require(loader.LoadFromRoot(root, now), "首次加载失败");
            Equal(92d, first.Windows.Single().RemainingPercentage, "首次剩余额度");

            File.WriteAllText(file, changedContents);
            File.SetLastWriteTimeUtc(file, originalModificationDate.UtcDateTime);
            var cached = Require(loader.LoadFromRoot(root, now), "缓存加载失败");
            Equal(92d, cached.Windows.Single().RemainingPercentage, "缓存剩余额度");

            File.SetLastWriteTimeUtc(file, originalModificationDate.AddMinutes(1).UtcDateTime);
            var refreshed = Require(loader.LoadFromRoot(root, now), "刷新加载失败");
            Equal(91d, refreshed.Windows.Single().RemainingPercentage, "刷新后剩余额度");
        });
    }

    private static void DecodesExtendedProtocolFixture()
    {
        var envelope = Require(
            JsonSerializer.Deserialize<MessageEnvelope<StateSnapshotPayload>>(
                File.ReadAllText(ProtocolFixture("task-snapshot-v2.json")),
                WireJson.Options),
            "新协议样本解码失败");

        Equal(AgentSource.ZCode, envelope.Payload.Tasks.Single().Source, "ZCode 来源");
        Equal("codex", Require(envelope.Payload.Usage, "缺少旧 Codex usage").LimitID!, "旧 usage");
        var glm = Require(envelope.Payload.UsageProviders, "缺少多提供方额度")
            .Single(provider => provider.Id == "glm");
        Equal("GLM Coding Plan", glm.PlanName!, "GLM 套餐回退名");
        Equal("lite", glm.PlanLevel!, "GLM 不透明 level");
        var fiveHour = glm.QuotaGroups.Single().Windows.First();
        Equal("CREDIT_LIMIT", fiveHour.QuotaType!, "额度类型");
        Equal(5d, fiveHour.UsedPercentage, "已使用百分比");
        Equal(1_897d, fiveHour.RemainingAmount!.Value, "服务端 remaining");
        Equal(
            "zcode:dba8317bdc0b859fdf59bc62bbe9631112fec8b939e2b5630f454f2c12db9b52",
            envelope.Payload.PendingRequests.Single().RequestID!,
            "待审批请求标识");
    }

    private static void ForwardsUnknownProtocolFixture()
    {
        var envelope = Require(
            JsonSerializer.Deserialize<MessageEnvelope<StateSnapshotPayload>>(
                File.ReadAllText(ProtocolFixture("task-snapshot-unknown.json")),
                WireJson.Options),
            "未知协议样本解码失败");

        Equal(AgentSource.Unknown, envelope.Payload.Tasks.Single().Source, "未知来源回退");
        var provider = Require(envelope.Payload.UsageProviders, "未知提供方被丢弃").Single();
        Equal("futureProvider", provider.Id, "未知提供方 ID");
        Equal("futureQuotaGroup", provider.QuotaGroups.Single().Id, "未知额度组 ID");

        var forwarded = Require(
            JsonSerializer.Deserialize<MessageEnvelope<StateSnapshotPayload>>(
                JsonSerializer.Serialize(envelope, WireJson.Options),
                WireJson.Options),
            "未知协议样本转发后解码失败");
        Equal(
            "futureQuotaGroup",
            Require(forwarded.Payload.UsageProviders, "转发后提供方丢失")
                .Single().QuotaGroups.Single().Id,
            "转发后的未知额度组");
    }

    private static void DecodesLegacyProtocolFixture()
    {
        var envelope = Require(
            JsonSerializer.Deserialize<MessageEnvelope<StateSnapshotPayload>>(
                File.ReadAllText(ProtocolFixture("task-snapshot.json")),
                WireJson.Options),
            "旧协议样本解码失败");

        Equal(AgentSource.CodexCLI, envelope.Payload.Tasks.Single().Source, "旧 Codex 来源");
        if (envelope.Payload.UsageProviders is not null)
            throw new InvalidOperationException("旧快照不应伪造多提供方额度");
    }

    private static void SupportsOptionalPendingRequestID()
    {
        var envelope = new SignedControlEnvelope(
            1,
            Guid.Parse("6f539e96-6bce-4fdc-94d5-3cf4ea755622"),
            "control.request",
            1_785_067_200_000,
            "android-test",
            7,
            "nonce-7",
            new ControlPayload(
                "zcode-session-1",
                ControlAction.Approve,
                null,
                "zcode:session-1:tool-1"),
            "");
        var signingText = Encoding.UTF8.GetString(ControlSigner.SigningData(envelope));
        Equal(
            "{\"action\":\"approve\",\"pendingRequestID\":\"zcode:session-1:tool-1\",\"taskID\":\"zcode-session-1\"}",
            signingText.Split('\n').Last(),
            "扩展控制载荷规范 JSON");

        var legacy = Require(
            JsonSerializer.Deserialize<ControlPayload>(
                "{\"taskID\":\"task-1\",\"action\":\"deny\"}",
                WireJson.Options),
            "旧控制载荷解码失败");
        if (legacy.PendingRequestID is not null)
            throw new InvalidOperationException("旧控制载荷不应伪造待审批请求标识");
    }

    private static DateTimeOffset Utc(string value) =>
        DateTimeOffset.Parse(value, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal);

    private static T Require<T>(T? value, string message) where T : class =>
        value ?? throw new InvalidOperationException(message);

    private static string ProtocolFixture(string name)
    {
        for (var directory = new DirectoryInfo(Directory.GetCurrentDirectory());
             directory is not null;
             directory = directory.Parent)
        {
            var candidate = Path.Combine(directory.FullName, "protocol", "fixtures", name);
            if (File.Exists(candidate)) return candidate;
        }
        throw new FileNotFoundException("找不到协议样本", name);
    }

    private static void Equal<T>(T expected, T actual, string label) where T : notnull
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
            throw new InvalidOperationException(
                label + ": expected " + expected + ", actual " + actual);
    }

    private static void WithTemporaryDirectory(Action<string> action)
    {
        var root = Path.Combine(
            Path.GetTempPath(),
            "AgentPager.Core.Tests",
            Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try { action(root); }
        finally { Directory.Delete(root, recursive: true); }
    }
}
