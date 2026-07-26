import Foundation

/// 这部分解析逻辑源自作者自己的 Open Vibe Island，并针对 AgentGrid 的领域模型做了收敛。
public enum CodexUsageLoader {
    public static var defaultRootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
    }

    private struct Candidate {
        var fileURL: URL
        var modifiedAt: Date
    }

    public static func load(
        fromRootURL rootURL: URL = defaultRootURL,
        fileManager: FileManager = .default
    ) -> UsageSnapshot? {
        guard fileManager.fileExists(atPath: rootURL.path),
              let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return nil
        }

        var candidates: [Candidate] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent.hasPrefix("rollout-"),
                  fileURL.pathExtension == "jsonl",
                  let values = try? fileURL.resourceValues(
                    forKeys: [.contentModificationDateKey, .isRegularFileKey]
                  ),
                  values.isRegularFile == true else {
                continue
            }
            candidates.append(
                Candidate(
                    fileURL: fileURL,
                    modifiedAt: values.contentModificationDate ?? .distantPast
                )
            )
        }

        for candidate in candidates.sorted(by: { $0.modifiedAt > $1.modifiedAt }) {
            if let snapshot = latestSnapshot(
                from: candidate.fileURL,
                modifiedAt: candidate.modifiedAt
            ) {
                return snapshot
            }
        }
        return nil
    }

    private static func latestSnapshot(from fileURL: URL, modifiedAt: Date) -> UsageSnapshot? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let tailSize = min(size, 512 * 1_024)
        try? handle.seek(toOffset: size - tailSize)
        guard let data = try? handle.readToEnd(),
              let contents = String(data: data, encoding: .utf8) else {
            return nil
        }

        var latest: UsageSnapshot?
        contents.enumerateLines { line, _ in
            if let snapshot = snapshot(
                from: line,
                fallbackTimestamp: modifiedAt
            ) {
                latest = snapshot
            }
        }
        return latest
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
            windows: windows
        )
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

