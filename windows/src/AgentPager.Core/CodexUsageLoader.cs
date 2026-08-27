using System.Globalization;
using System.Text;
using System.Text.Json;

namespace AgentPager.Core;

public sealed class CodexUsageLoader
{
    private const int HistoryDays = 90;
    private const int TailSize = 256 * 1024;
    private static readonly TimeSpan QuotaFreshness = TimeSpan.FromDays(8);
    private sealed record Candidate(string Path, DateTimeOffset ModifiedAt, long Size);
    private sealed record Raw(long Input, long Cached, long Output, long Reasoning, long Total)
    {
        public static Raw Zero { get; } = new(0, 0, 0, 0, 0);
        public bool IsEmpty => Input == 0 && Cached == 0 && Output == 0 && Reasoning == 0 && Total == 0;
        public static Raw operator +(Raw left, Raw right) =>
            new(left.Input + right.Input, left.Cached + right.Cached, left.Output + right.Output,
                left.Reasoning + right.Reasoning, left.Total + right.Total);
        public Raw Subtract(Raw? previous) =>
            new(Math.Max(0, Input - (previous?.Input ?? 0)), Math.Max(0, Cached - (previous?.Cached ?? 0)),
                Math.Max(0, Output - (previous?.Output ?? 0)), Math.Max(0, Reasoning - (previous?.Reasoning ?? 0)),
                Math.Max(0, Total - (previous?.Total ?? 0)));
    }

    public UsageSnapshot? Load(DateTimeOffset? now = null)
    {
        var current = now ?? DateTimeOffset.Now;
        var roots = new[]
        {
            Path.Combine(CodexPaths.Home, "sessions"),
            Path.Combine(CodexPaths.Home, "archived_sessions"),
        };
        var candidates = roots.Where(Directory.Exists).SelectMany(root =>
        {
            try { return Directory.EnumerateFiles(root, "rollout-*.jsonl", SearchOption.AllDirectories); }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { return []; }
        }).Distinct(StringComparer.OrdinalIgnoreCase).Select(path =>
        {
            var info = new FileInfo(path);
            return new Candidate(path, info.LastWriteTimeUtc, info.Length);
        }).ToList();
        if (candidates.Count == 0) return null;

        var quotaSnapshots = LatestQuotaSnapshots(candidates, current);
        var quotaGroups = LatestQuotaGroups(quotaSnapshots);
        var quota = PreferredLegacyQuota(quotaSnapshots);

        var start = current.Date.AddDays(-(HistoryDays - 1));
        var buckets = new Dictionary<string, Raw>();
        foreach (var candidate in candidates.Where(value => value.ModifiedAt >= start))
        {
            if (candidate.Size <= TailSize)
                AggregateFile(candidate.Path, start, buckets);
            else if (LatestCumulative(candidate.Path) is { } latest && latest.Timestamp >= start && !latest.Usage.IsEmpty)
                Add(buckets, latest.Timestamp.ToLocalTime().ToString("yyyy-MM-dd", CultureInfo.InvariantCulture), latest.Usage);
        }
        if (quota is null && buckets.Count == 0) return null;

        var daily = Enumerable.Range(0, HistoryDays).Select(offset =>
        {
            var date = start.AddDays(offset).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
            var usage = buckets.GetValueOrDefault(date, Raw.Zero);
            return new DailyUsagePoint(date, usage.Input, usage.Cached, usage.Output, usage.Reasoning, usage.Total);
        }).ToList();
        return new(quota?.CapturedAt ?? candidates.Max(value => value.ModifiedAt), quota?.PlanType, quota?.LimitID,
            quota?.LimitName, quota?.Windows ?? [], quotaGroups, daily);
    }

    private static List<UsageSnapshot> LatestQuotas(Candidate candidate)
    {
        var latestByID = new Dictionary<string, UsageSnapshot>(StringComparer.OrdinalIgnoreCase);
        foreach (var line in TailLines(candidate.Path, 512 * 1024).Reverse())
        {
            try
            {
                using var document = JsonDocument.Parse(line);
                var root = document.RootElement;
                if (root.GetStringOrNull("type") != "event_msg" ||
                    !root.TryGetProperty("payload", out var payload) ||
                    payload.GetStringOrNull("type") != "token_count")
                    continue;
                JsonElement limits;
                if (payload.TryGetProperty("rate_limits", out var direct)) limits = direct;
                else if (payload.TryGetProperty("info", out var info) &&
                         info.TryGetProperty("rate_limits", out var nested)) limits = nested;
                else continue;
                if (limits.ValueKind != JsonValueKind.Object) continue;
                var windows = new List<UsageWindow>();
                foreach (var key in new[] { "primary", "secondary" })
                {
                    if (!limits.TryGetProperty(key, out var window) ||
                        window.ValueKind != JsonValueKind.Object) continue;
                    if (!Number(window, "used_percent", out var used) ||
                        !Integer(window, "window_minutes", out var minutes)) continue;
                    DateTimeOffset? resets = Number(window, "resets_at", out var seconds)
                        ? DateTimeOffset.FromUnixTimeSeconds((long)seconds) : null;
                    windows.Add(new(key, WindowLabel(minutes), used, Math.Max(0, 100 - used), minutes, resets));
                }
                if (windows.Count == 0) continue;
                var captured = DateTimeOffset.TryParse(root.GetStringOrNull("timestamp"), out var parsed)
                    ? parsed : candidate.ModifiedAt;
                var limitID = Scalar(limits, "limit_id") ?? "default";
                if (!latestByID.ContainsKey(limitID))
                    latestByID[limitID] = new(captured, Scalar(limits, "plan_type"), limitID,
                        Scalar(limits, "limit_name"), windows, [], []);
            }
            catch (JsonException) { }
        }
        return latestByID.Values.ToList();
    }

    private static List<UsageSnapshot> LatestQuotaSnapshots(
        List<Candidate> candidates,
        DateTimeOffset now)
    {
        var snapshots = new List<UsageSnapshot>();
        var foundGeneral = false;
        var foundSpark = false;
        var cutoff = now - QuotaFreshness;

        foreach (var candidate in candidates
                     .Where(value => value.ModifiedAt >= cutoff)
                     .OrderByDescending(value => value.ModifiedAt))
        {
            foreach (var snapshot in LatestQuotas(candidate))
            {
                snapshots.Add(snapshot);
                var rank = QuotaRank(snapshot);
                foundGeneral |= rank == 0;
                foundSpark |= rank == 1;
            }
            if (foundGeneral && foundSpark) break;
        }
        return snapshots;
    }

    private static List<QuotaGroup> LatestQuotaGroups(List<UsageSnapshot> snapshots) =>
        snapshots
            .GroupBy(value => value.LimitID ?? "default", StringComparer.OrdinalIgnoreCase)
            .Select(group => group.MaxBy(value => value.CapturedAt ?? DateTimeOffset.MinValue)!)
            .OrderBy(QuotaRank)
            .ThenByDescending(value => value.CapturedAt)
            .Select(value => new QuotaGroup(
                value.LimitID ?? "default",
                value.LimitName,
                value.CapturedAt,
                value.Windows))
            .ToList();

    private static UsageSnapshot? PreferredLegacyQuota(List<UsageSnapshot> snapshots) =>
        snapshots
            .OrderBy(QuotaRank)
            .ThenByDescending(value => value.CapturedAt)
            .FirstOrDefault();

    private static int QuotaRank(UsageSnapshot snapshot)
    {
        if (string.Equals(snapshot.LimitID, "codex", StringComparison.OrdinalIgnoreCase)) return 0;
        var searchable = $"{snapshot.LimitID} {snapshot.LimitName}";
        if (searchable.Contains("spark", StringComparison.OrdinalIgnoreCase) ||
            searchable.Contains("bengalfox", StringComparison.OrdinalIgnoreCase)) return 1;
        return 2;
    }

    private static void AggregateFile(string path, DateTimeOffset start, Dictionary<string, Raw> buckets)
    {
        Raw? previous = null;
        foreach (var line in File.ReadLines(path))
        {
            if (!line.Contains("\"token_count\"", StringComparison.Ordinal)) continue;
            try
            {
                using var document = JsonDocument.Parse(line);
                var root = document.RootElement;
                if (root.GetStringOrNull("type") != "event_msg" ||
                    !DateTimeOffset.TryParse(root.GetStringOrNull("timestamp"), out var timestamp) ||
                    !root.TryGetProperty("payload", out var payload) ||
                    payload.GetStringOrNull("type") != "token_count")
                    continue;
                var info = payload.TryGetProperty("info", out var infoValue) ? infoValue : payload;
                var total = RawUsage(info, "total_token_usage") ?? RawUsage(payload, "total_token_usage");
                var last = RawUsage(info, "last_token_usage") ?? RawUsage(payload, "last_token_usage");
                var delta = last ?? total?.Subtract(previous);
                if (total is not null) previous = total;
                if (timestamp < start || delta is null || delta.IsEmpty) continue;
                Add(buckets, timestamp.ToLocalTime().ToString("yyyy-MM-dd", CultureInfo.InvariantCulture), delta);
            }
            catch (JsonException) { }
        }
    }

    private static (DateTimeOffset Timestamp, Raw Usage)? LatestCumulative(string path)
    {
        foreach (var line in TailLines(path, TailSize).Reverse())
        {
            if (!line.Contains("\"token_count\"", StringComparison.Ordinal)) continue;
            try
            {
                using var document = JsonDocument.Parse(line);
                var root = document.RootElement;
                if (!DateTimeOffset.TryParse(root.GetStringOrNull("timestamp"), out var timestamp) ||
                    !root.TryGetProperty("payload", out var payload)) continue;
                var info = payload.TryGetProperty("info", out var infoValue) ? infoValue : payload;
                var usage = RawUsage(info, "total_token_usage") ?? RawUsage(payload, "total_token_usage");
                if (usage is not null) return (timestamp, usage);
            }
            catch (JsonException) { }
        }
        return null;
    }

    private static IEnumerable<string> TailLines(string path, int maximum)
    {
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        stream.Seek(Math.Max(0, stream.Length - maximum), SeekOrigin.Begin);
        using var reader = new StreamReader(stream, Encoding.UTF8);
        if (stream.Position > 0) _ = reader.ReadLine();
        while (reader.ReadLine() is { } line) yield return line;
    }

    private static Raw? RawUsage(JsonElement parent, string key)
    {
        if (!parent.TryGetProperty(key, out var value) || value.ValueKind != JsonValueKind.Object) return null;
        var input = Long(value, "input_tokens");
        var cached = Math.Min(input, Long(value, "cached_input_tokens", "cache_read_input_tokens"));
        var output = Long(value, "output_tokens");
        var total = Long(value, "total_tokens");
        if (total == 0) total = input + output;
        return new(input, cached, output, Long(value, "reasoning_output_tokens"), total);
    }

    private static long Long(JsonElement value, params string[] keys)
    {
        foreach (var key in keys)
            if (value.TryGetProperty(key, out var item) && item.TryGetInt64(out var result))
                return result;
        return 0;
    }

    private static void Add(Dictionary<string, Raw> buckets, string key, Raw value) =>
        buckets[key] = buckets.GetValueOrDefault(key, Raw.Zero) + value;

    private static bool Number(JsonElement parent, string key, out double value)
    {
        value = 0;
        if (!parent.TryGetProperty(key, out var item)) return false;
        return item.TryGetDouble(out value) ||
               item.ValueKind == JsonValueKind.String && double.TryParse(item.GetString(), out value);
    }

    private static bool Integer(JsonElement parent, string key, out int value)
    {
        value = 0;
        if (!parent.TryGetProperty(key, out var item)) return false;
        return item.TryGetInt32(out value) ||
               item.ValueKind == JsonValueKind.String && int.TryParse(item.GetString(), out value);
    }

    private static string? Scalar(JsonElement parent, string key)
    {
        if (!parent.TryGetProperty(key, out var item)) return null;
        return item.ValueKind == JsonValueKind.String ? item.GetString() : item.GetRawText();
    }

    private static string WindowLabel(int minutes)
    {
        var days = minutes / 1440;
        var hours = minutes % 1440 / 60;
        var rest = minutes % 60;
        if (days > 0 && hours == 0 && rest == 0) return $"{days}d";
        if (days > 0 && hours > 0) return $"{days}d {hours}h";
        if (hours > 0 && rest == 0) return $"{hours}h";
        return hours > 0 ? $"{hours}h {rest}m" : $"{minutes}m";
    }
}
