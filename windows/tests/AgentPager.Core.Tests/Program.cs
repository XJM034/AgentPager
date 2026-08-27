using AgentPager.Core;
using System.Globalization;

namespace AgentPager.Core.Tests;

internal static class Program
{
    private static int Main()
    {
        var failures = new List<string>();
        Run("跨文件额度乱序时保留 capturedAt 更新的 Spark", KeepsNewestSparkAcrossFiles, failures);
        Run("额度文件未变化时复用缓存，变化后重新解析", CachesQuotaFilesByMetadata, failures);

        if (failures.Count == 0)
        {
            Console.WriteLine("AgentPager.Core regression tests passed (2/2).");
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

    private static DateTimeOffset Utc(string value) =>
        DateTimeOffset.Parse(value, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal);

    private static T Require<T>(T? value, string message) where T : class =>
        value ?? throw new InvalidOperationException(message);

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
