import Foundation

/// 读取 Codex 本地日志中的额度窗口与近期 Token 用量。
public final class CodexUsageLoader: @unchecked Sendable {
    public static let historyDayCount = 90
    private static let historyTailSize = 256 * 1_024
    private static let exactHistoryFileSizeLimit = historyTailSize
    private static let quotaFreshnessInterval: TimeInterval = 8 * 24 * 60 * 60

    private struct QuotaCacheEntry {
        var modifiedAt: Date
        var fileSize: Int
        var snapshots: [UsageSnapshot]
    }

    private let quotaCacheLock = NSLock()
    private var quotaCache: [String: QuotaCacheEntry] = [:]

    public init() {}

    public static var defaultRootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
    }

    public static var defaultRootURLs: [URL] {
        let codexRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
        return [
            codexRoot.appendingPathComponent("sessions", isDirectory: true),
            codexRoot.appendingPathComponent("archived_sessions", isDirectory: true),
        ]
    }

    private struct Candidate {
        var fileURL: URL
        var modifiedAt: Date
        var fileSize: Int
    }

    private struct RawUsage {
        var input: Int64
        var cachedInput: Int64
        var output: Int64
        var reasoningOutput: Int64
        var total: Int64

        static let zero = RawUsage(
            input: 0,
            cachedInput: 0,
            output: 0,
            reasoningOutput: 0,
            total: 0
        )

        var isEmpty: Bool {
            input == 0 &&
                cachedInput == 0 &&
                output == 0 &&
                reasoningOutput == 0 &&
                total == 0
        }

        func subtracting(_ previous: RawUsage?) -> RawUsage {
            RawUsage(
                input: max(0, input - (previous?.input ?? 0)),
                cachedInput: max(0, cachedInput - (previous?.cachedInput ?? 0)),
                output: max(0, output - (previous?.output ?? 0)),
                reasoningOutput: max(0, reasoningOutput - (previous?.reasoningOutput ?? 0)),
                total: max(0, total - (previous?.total ?? 0))
            )
        }

        static func + (lhs: RawUsage, rhs: RawUsage) -> RawUsage {
            RawUsage(
                input: lhs.input + rhs.input,
                cachedInput: lhs.cachedInput + rhs.cachedInput,
                output: lhs.output + rhs.output,
                reasoningOutput: lhs.reasoningOutput + rhs.reasoningOutput,
                total: lhs.total + rhs.total
            )
        }
    }

    public func load(
        fileManager: FileManager = .default,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> UsageSnapshot? {
        let nativeSnapshot = load(
            fromRootURLs: Self.defaultRootURLs,
            fileManager: fileManager,
            now: now,
            calendar: calendar
        )
        guard let codexBarUsage = CodexBarCostLoader.load(
            historyDays: Self.historyDayCount,
            fileManager: fileManager
        ) else {
            return nativeSnapshot
        }
        return Self.mergedSnapshot(
            nativeSnapshot,
            codexBarUsage: codexBarUsage,
            now: now,
            calendar: calendar
        )
    }

    public func load(
        fromRootURL rootURL: URL,
        fileManager: FileManager = .default,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> UsageSnapshot? {
        load(
            fromRootURLs: [rootURL],
            fileManager: fileManager,
            now: now,
            calendar: calendar
        )
    }

    private func load(
        fromRootURLs rootURLs: [URL],
        fileManager: FileManager,
        now: Date,
        calendar: Calendar
    ) -> UsageSnapshot? {
        let candidates = Self.candidates(
            fromRootURLs: rootURLs,
            fileManager: fileManager
        )
        guard !candidates.isEmpty else {
            return nil
        }

        let quotaSnapshots = latestQuotaSnapshots(
            from: candidates,
            now: now
        )
        let quotaGroups = Self.latestQuotaGroups(from: quotaSnapshots)
        let quotaSnapshot = Self.preferredLegacySnapshot(from: quotaSnapshots)
        let dailyUsage = Self.dailyUsage(
            from: candidates,
            now: now,
            calendar: calendar
        )
        guard quotaSnapshot != nil || !dailyUsage.isEmpty else {
            return nil
        }

        return UsageSnapshot(
            capturedAt: quotaSnapshot?.capturedAt ??
                candidates.max(by: { $0.modifiedAt < $1.modifiedAt })?.modifiedAt,
            planType: quotaSnapshot?.planType,
            limitID: quotaSnapshot?.limitID,
            limitName: quotaSnapshot?.limitName,
            windows: quotaSnapshot?.windows ?? [],
            quotaGroups: quotaGroups,
            dailyUsage: dailyUsage
        )
    }

    private static func candidates(
        fromRootURLs rootURLs: [URL],
        fileManager: FileManager
    ) -> [Candidate] {
        var result: [Candidate] = []
        var visitedPaths = Set<String>()

        for rootURL in rootURLs {
            guard fileManager.fileExists(atPath: rootURL.path),
                  let enumerator = fileManager.enumerator(
                    at: rootURL,
                    includingPropertiesForKeys: [
                        .contentModificationDateKey,
                        .fileSizeKey,
                        .isRegularFileKey,
                    ],
                    options: [.skipsHiddenFiles]
                  ) else {
                continue
            }

            for case let fileURL as URL in enumerator {
                guard fileURL.lastPathComponent.hasPrefix("rollout-"),
                      fileURL.pathExtension == "jsonl",
                      visitedPaths.insert(fileURL.standardizedFileURL.path).inserted,
                      let values = try? fileURL.resourceValues(
                        forKeys: [
                            .contentModificationDateKey,
                            .fileSizeKey,
                            .isRegularFileKey,
                        ]
                      ),
                      values.isRegularFile == true else {
                    continue
                }
                result.append(
                    Candidate(
                        fileURL: fileURL,
                        modifiedAt: values.contentModificationDate ?? .distantPast,
                        fileSize: values.fileSize ?? 0
                    )
                )
            }
        }
        return result
    }

    private func latestSnapshots(from candidate: Candidate) -> [UsageSnapshot] {
        let path = candidate.fileURL.standardizedFileURL.path
        quotaCacheLock.lock()
        if let entry = quotaCache[path],
           entry.modifiedAt == candidate.modifiedAt,
           entry.fileSize == candidate.fileSize {
            quotaCacheLock.unlock()
            return entry.snapshots
        }
        quotaCacheLock.unlock()

        let snapshots = Self.readLatestSnapshots(
            from: candidate.fileURL,
            modifiedAt: candidate.modifiedAt
        )
        quotaCacheLock.lock()
        quotaCache[path] = QuotaCacheEntry(
            modifiedAt: candidate.modifiedAt,
            fileSize: candidate.fileSize,
            snapshots: snapshots
        )
        quotaCacheLock.unlock()
        return snapshots
    }

    private static func readLatestSnapshots(
        from fileURL: URL,
        modifiedAt: Date
    ) -> [UsageSnapshot] {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return []
        }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let tailSize = min(size, 512 * 1_024)
        try? handle.seek(toOffset: size - tailSize)
        guard let data = try? handle.readToEnd(),
              let contents = String(data: data, encoding: .utf8) else {
            return []
        }

        var latestByID: [String: UsageSnapshot] = [:]
        contents.enumerateLines { line, _ in
            guard line.contains("\"token_count\"") else { return }
            if let snapshot = snapshot(
                from: line,
                fallbackTimestamp: modifiedAt
            ) {
                latestByID[snapshot.limitID ?? "default"] = snapshot
            }
        }
        return Array(latestByID.values)
    }

    private func latestQuotaSnapshots(
        from candidates: [Candidate],
        now: Date
    ) -> [UsageSnapshot] {
        let cutoff = now.addingTimeInterval(-Self.quotaFreshnessInterval)
        let recentCandidates = candidates
            .filter({ $0.modifiedAt >= cutoff })
            .sorted(by: { $0.modifiedAt > $1.modifiedAt })
        let activePaths = Set(
            recentCandidates.map { $0.fileURL.standardizedFileURL.path }
        )
        quotaCacheLock.lock()
        quotaCache = quotaCache.filter { activePaths.contains($0.key) }
        quotaCacheLock.unlock()

        var snapshots: [UsageSnapshot] = []
        for candidate in recentCandidates {
            snapshots.append(contentsOf: latestSnapshots(from: candidate))
        }
        return snapshots
    }

    private static func snapshot(from line: String, fallbackTimestamp: Date) -> UsageSnapshot? {
        guard let object = object(from: line),
              object["type"] as? String == "event_msg" else {
            return nil
        }
        let payload = object["payload"] as? [String: Any] ?? [:]
        guard payload["type"] as? String == "token_count",
              let rateLimits = payload["rate_limits"] as? [String: Any]
                ?? (payload["info"] as? [String: Any])?["rate_limits"] as? [String: Any] else {
            return nil
        }

        let windows = ["primary", "secondary"].compactMap {
            usageWindow(key: $0, rateLimits: rateLimits)
        }
        guard !windows.isEmpty else {
            return nil
        }

        return UsageSnapshot(
            capturedAt: parseTimestamp(object["timestamp"]) ?? fallbackTimestamp,
            planType: scalarString(rateLimits["plan_type"]),
            limitID: scalarString(rateLimits["limit_id"]),
            limitName: scalarString(rateLimits["limit_name"]),
            windows: windows
        )
    }

    private static func latestQuotaGroups(
        from snapshots: [UsageSnapshot]
    ) -> [QuotaGroup] {
        var latestByID: [String: UsageSnapshot] = [:]
        for snapshot in snapshots {
            let id = snapshot.limitID ?? "default"
            let current = latestByID[id]
            if current == nil ||
                (snapshot.capturedAt ?? .distantPast) > (current?.capturedAt ?? .distantPast) {
                latestByID[id] = snapshot
            }
        }

        return latestByID.values
            .sorted { lhs, rhs in
                let lhsRank = quotaGroupRank(lhs)
                let rhsRank = quotaGroupRank(rhs)
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return (lhs.capturedAt ?? .distantPast) > (rhs.capturedAt ?? .distantPast)
            }
            .map { snapshot in
                QuotaGroup(
                    id: snapshot.limitID ?? "default",
                    name: snapshot.limitName,
                    capturedAt: snapshot.capturedAt,
                    windows: snapshot.windows
                )
            }
    }

    private static func preferredLegacySnapshot(
        from snapshots: [UsageSnapshot]
    ) -> UsageSnapshot? {
        snapshots
            .sorted { lhs, rhs in
                let lhsRank = quotaGroupRank(lhs)
                let rhsRank = quotaGroupRank(rhs)
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return (lhs.capturedAt ?? .distantPast) > (rhs.capturedAt ?? .distantPast)
            }
            .first
    }

    private static func quotaGroupRank(_ snapshot: UsageSnapshot) -> Int {
        if snapshot.limitID?.lowercased() == "codex" { return 0 }
        let searchable = [snapshot.limitID, snapshot.limitName]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        if searchable.contains("spark") || searchable.contains("bengalfox") { return 1 }
        return 2
    }

    private static func usageWindow(
        key: String,
        rateLimits: [String: Any]
    ) -> UsageWindow? {
        guard let payload = rateLimits[key] as? [String: Any],
              let used = number(payload["used_percent"]),
              let minutes = integer(payload["window_minutes"]) else {
            return nil
        }

        return UsageWindow(
            key: key,
            label: windowLabel(minutes),
            usedPercentage: used,
            remainingPercentage: max(0, 100 - used),
            windowMinutes: minutes,
            resetsAt: epochDate(payload["resets_at"])
        )
    }

    private static func dailyUsage(
        from candidates: [Candidate],
        now: Date,
        calendar: Calendar
    ) -> [DailyUsagePoint] {
        let startOfToday = calendar.startOfDay(for: now)
        guard let historyStart = calendar.date(
            byAdding: .day,
            value: -(historyDayCount - 1),
            to: startOfToday
        ) else {
            return []
        }

        var buckets: [String: RawUsage] = [:]
        let formatter = dayFormatter(calendar: calendar)

        for candidate in candidates where candidate.modifiedAt >= historyStart {
            if candidate.fileSize <= exactHistoryFileSizeLimit {
                aggregateDailyUsage(
                    from: candidate.fileURL,
                    historyStart: historyStart,
                    calendar: calendar,
                    formatter: formatter,
                    into: &buckets
                )
            } else if let latest = latestCumulativeUsage(from: candidate.fileURL),
                      latest.timestamp >= historyStart,
                      !latest.usage.isEmpty {
                // 大型长会话只读取尾部累计值，避免空状态首次出现时串行扫描数 GB 日志。
                let day = calendar.startOfDay(for: latest.timestamp)
                let key = formatter.string(from: day)
                buckets[key] = (buckets[key] ?? .zero) + latest.usage
            }
        }
        guard !buckets.isEmpty else {
            return []
        }

        return (0..<historyDayCount).compactMap { offset in
            guard let day = calendar.date(
                byAdding: .day,
                value: offset - (historyDayCount - 1),
                to: startOfToday
            ) else {
                return nil
            }
            let key = formatter.string(from: day)
            let usage = buckets[key] ?? .zero
            return DailyUsagePoint(
                date: key,
                inputTokens: usage.input,
                cachedInputTokens: usage.cachedInput,
                outputTokens: usage.output,
                reasoningOutputTokens: usage.reasoningOutput,
                totalTokens: usage.total
            )
        }
    }

    private static func mergedSnapshot(
        _ nativeSnapshot: UsageSnapshot?,
        codexBarUsage: [DailyUsagePoint],
        now: Date,
        calendar: Calendar
    ) -> UsageSnapshot? {
        guard nativeSnapshot != nil || !codexBarUsage.isEmpty else {
            return nil
        }

        let nativeByDate = Dictionary(
            uniqueKeysWithValues: nativeSnapshot?.dailyUsage.map { ($0.date, $0) } ?? []
        )
        let codexBarByDate = Dictionary(
            uniqueKeysWithValues: codexBarUsage.map { ($0.date, $0) }
        )
        let formatter = dayFormatter(calendar: calendar)
        let startOfToday = calendar.startOfDay(for: now)
        let dailyUsage = (0..<historyDayCount).compactMap { offset -> DailyUsagePoint? in
            guard let day = calendar.date(
                byAdding: .day,
                value: offset - (historyDayCount - 1),
                to: startOfToday
            ) else {
                return nil
            }
            let key = formatter.string(from: day)
            if var point = codexBarByDate[key] {
                point.reasoningOutputTokens = nativeByDate[key]?.reasoningOutputTokens ?? 0
                return point
            }
            return nativeByDate[key] ?? DailyUsagePoint(date: key)
        }

        return UsageSnapshot(
            capturedAt: nativeSnapshot?.capturedAt ?? now,
            planType: nativeSnapshot?.planType,
            limitID: nativeSnapshot?.limitID,
            limitName: nativeSnapshot?.limitName,
            windows: nativeSnapshot?.windows ?? [],
            quotaGroups: nativeSnapshot?.quotaGroups ?? [],
            dailyUsage: dailyUsage
        )
    }

    private static func aggregateDailyUsage(
        from fileURL: URL,
        historyStart: Date,
        calendar: Calendar,
        formatter: DateFormatter,
        into buckets: inout [String: RawUsage]
    ) {
        var previousTotals: RawUsage?
        forEachLine(in: fileURL) { line in
            guard line.contains("\"token_count\""),
                  let object = object(from: line),
                  object["type"] as? String == "event_msg",
                  let timestamp = parseTimestamp(object["timestamp"]),
                  let payload = object["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count" else {
                return
            }

            let info = payload["info"] as? [String: Any] ?? [:]
            let totalUsage = rawUsage(
                info["total_token_usage"] ?? payload["total_token_usage"]
            )
            let lastUsage = rawUsage(
                info["last_token_usage"] ?? payload["last_token_usage"]
            )
            let delta = lastUsage ?? totalUsage?.subtracting(previousTotals)
            if let totalUsage {
                previousTotals = totalUsage
            }
            guard timestamp >= historyStart,
                  let delta,
                  !delta.isEmpty else {
                return
            }

            let day = calendar.startOfDay(for: timestamp)
            let key = formatter.string(from: day)
            buckets[key] = (buckets[key] ?? .zero) + delta
        }
    }

    private static func latestCumulativeUsage(
        from fileURL: URL
    ) -> (timestamp: Date, usage: RawUsage)? {
        guard let data = tailData(from: fileURL, maximumSize: historyTailSize) else {
            return nil
        }

        var lineEnd = data.endIndex
        while lineEnd > data.startIndex {
            let searchEnd = data.index(before: lineEnd)
            let lineBreak = data[data.startIndex..<searchEnd].lastIndex(of: 0x0A)
            let lineStart = lineBreak.map { data.index(after: $0) } ?? data.startIndex
            let lineData = data[lineStart..<lineEnd]
            lineEnd = lineBreak ?? data.startIndex

            guard let line = String(data: lineData, encoding: .utf8),
                  line.contains("\"token_count\""),
                  let object = object(from: line),
                  object["type"] as? String == "event_msg",
                  let timestamp = parseTimestamp(object["timestamp"]),
                  let payload = object["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count" else {
                continue
            }
            let info = payload["info"] as? [String: Any] ?? [:]
            if let usage = rawUsage(
                info["total_token_usage"] ?? payload["total_token_usage"]
            ) {
                return (timestamp, usage)
            }
        }
        return nil
    }

    private static func tailData(from fileURL: URL, maximumSize: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }
        defer { try? handle.close() }

        guard let size = try? handle.seekToEnd() else {
            return nil
        }
        let tailSize = min(size, UInt64(maximumSize))
        try? handle.seek(toOffset: size - tailSize)
        return try? handle.readToEnd()
    }

    private static func forEachLine(in fileURL: URL, body: (String) -> Void) {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return
        }
        defer { try? handle.close() }

        var pending = Data()
        while let chunk = try? handle.read(upToCount: 64 * 1_024),
              !chunk.isEmpty {
            pending.append(chunk)
            var lineStart = pending.startIndex
            while let lineEnd = pending[lineStart...].firstIndex(of: 0x0A) {
                if let line = String(
                    data: pending[lineStart..<lineEnd],
                    encoding: .utf8
                ) {
                    body(line)
                }
                lineStart = pending.index(after: lineEnd)
            }
            if lineStart > pending.startIndex {
                pending.removeSubrange(pending.startIndex..<lineStart)
            }
        }
        if !pending.isEmpty,
           let line = String(data: pending, encoding: .utf8) {
            body(line)
        }
    }

    private static func rawUsage(_ value: Any?) -> RawUsage? {
        guard let payload = value as? [String: Any] else {
            return nil
        }
        let input = int64(payload["input_tokens"]) ?? 0
        let output = int64(payload["output_tokens"]) ?? 0
        let reportedTotal = int64(payload["total_tokens"]) ?? 0
        let total = reportedTotal > 0 ? reportedTotal : input + output
        return RawUsage(
            input: input,
            cachedInput: min(
                input,
                int64(payload["cached_input_tokens"] ?? payload["cache_read_input_tokens"]) ?? 0
            ),
            output: output,
            reasoningOutput: int64(payload["reasoning_output_tokens"]) ?? 0,
            total: total
        )
    }

    private static func dayFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static func windowLabel(_ minutes: Int) -> String {
        let days = minutes / 1_440
        let hours = (minutes % 1_440) / 60
        let rest = minutes % 60
        if days > 0, hours == 0, rest == 0 { return "\(days)d" }
        if days > 0, hours > 0 { return "\(days)d \(hours)h" }
        if hours > 0, rest == 0 { return "\(hours)h" }
        if hours > 0 { return "\(hours)h \(rest)m" }
        return "\(minutes)m"
    }

    private static func object(from line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return value as? [String: Any]
    }

    private static func parseTimestamp(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func int64(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber { return number.int64Value }
        if let string = value as? String { return Int64(string) }
        return nil
    }

    private static func epochDate(_ value: Any?) -> Date? {
        guard let seconds = number(value) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private static func scalarString(_ value: Any?) -> String? {
        if let string = value as? String, !string.isEmpty { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }
}
