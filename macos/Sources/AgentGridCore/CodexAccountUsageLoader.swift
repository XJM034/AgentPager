import Darwin
import Foundation

/// Query the signed-in Codex account without starting a turn or reading credentials.
/// A failed query returns unavailable; rollout logs are not a current account balance.
public enum CodexAccountUsageLoader {
    public static func load() -> UsageSnapshot? {
        guard let executable = executableURL(),
              let data = request(executableURL: executable) else { return nil }
        return parse(data, now: .now)
    }

    static func parse(_ data: Data, now: Date) -> UsageSnapshot? {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        // An explicitly supplied bucket map is authoritative, including an empty map.
        let quota: Quota?
        if let buckets = response.rateLimitsByLimitId {
            quota = buckets.codex
        } else {
            quota = response.rateLimits
        }
        guard let quota,
              quota.limitId == nil || quota.limitId?.lowercased() == "codex",
              ![quota.limitName ?? ""].contains(where: {
                  $0.lowercased().contains("spark") || $0.lowercased().contains("bengalfox")
              }) else { return nil }
        let windows = [("primary", quota.primary), ("secondary", quota.secondary)].compactMap { key, value -> UsageWindow? in
            guard let value, value.usedPercent.isFinite,
                  (0...100).contains(value.usedPercent), value.windowDurationMins > 0 else { return nil }
            return UsageWindow(
                key: key,
                label: value.windowDurationMins == 300 ? "5h" :
                    value.windowDurationMins == 10_080 ? "7d" : "\(value.windowDurationMins)m",
                usedPercentage: value.usedPercent,
                remainingPercentage: 100 - value.usedPercent,
                windowMinutes: value.windowDurationMins,
                resetsAt: value.resetsAt.map { Date(timeIntervalSince1970: $0) }
            )
        }
        guard !windows.isEmpty else { return nil }
        return UsageSnapshot(
            capturedAt: now, planType: quota.planType, limitID: "codex",
            limitName: quota.limitName, windows: windows,
            quotaGroups: [QuotaGroup(id: "codex", name: quota.limitName, capturedAt: now, windows: windows)]
        )
    }

    private struct Response: Decodable {
        var rateLimits: Quota?
        var rateLimitsByLimitId: Buckets?
    }

    private struct Buckets: Decodable {
        // Unknown/retired buckets are ignored without decoding their contents.
        var codex: Quota?
    }

    private struct Quota: Decodable {
        var limitId: String?
        var limitName: String?
        var planType: String?
        var primary: Window?
        var secondary: Window?
    }

    private struct Window: Decodable {
        var usedPercent: Double
        var windowDurationMins: Int
        var resetsAt: Double?
    }

    private static func executableURL() -> URL? {
        // Prefer the desktop app's CLI so its account and protocol match Codex Desktop.
        let paths = [
            "/Applications/Codex.app/Contents/Resources/codex",
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/Codex.app/Contents/Resources/codex").path,
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
        ] + (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map { "\($0)/codex" }
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    /// Short-lived stdio connection, bounded in both time and output size.
    /// No prompts, login changes, reset redemption, or raw response logging.
    static func request(executableURL: URL, timeout: TimeInterval = 10) -> Data? {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executableURL
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        // Close parent copies so EOF is observable when the child exits.
        try? output.fileHandleForWriting.close()
        try? input.fileHandleForReading.close()
        defer {
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
            if process.isRunning {
                process.terminate()
                let deadline = ProcessInfo.processInfo.systemUptime + 0.25
                while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline {
                    Thread.sleep(forTimeInterval: 0.01)
                }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
            process.waitUntilExit()
        }
        func send(_ message: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: message, options: .withoutEscapingSlashes)
            data.append(0x0a)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        do {
            try send(["id": 1, "method": "initialize", "params": [
                "clientInfo": ["name": "agentpager_bridge", "version": "0.3.0"],
            ]])
            let deadline = ProcessInfo.processInfo.systemUptime + timeout
            var buffer = Data()
            var totalBytes = 0
            var initialized = false
            while ProcessInfo.processInfo.systemUptime < deadline {
                var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
                let milliseconds = Int32(max(1, (deadline - ProcessInfo.processInfo.systemUptime) * 1_000))
                let ready = poll(&descriptor, 1, milliseconds)
                if ready < 0 && errno == EINTR { continue }
                guard ready > 0 else { return nil }
                var bytes = [UInt8](repeating: 0, count: 8_192)
                let count = read(descriptor.fd, &bytes, bytes.count)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { return nil }
                totalBytes += count
                guard totalBytes <= 1_048_576 else { return nil }
                buffer.append(contentsOf: bytes.prefix(count))
                while let newline = buffer.firstIndex(of: 0x0a) {
                    let line = Data(buffer[..<newline])
                    buffer.removeSubrange(...newline)
                    guard let message = try JSONSerialization.jsonObject(with: line) as? [String: Any],
                          let id = message["id"] as? Int else { continue }
                    guard message["error"] == nil else { return nil }
                    if id == 1 && !initialized {
                        guard message["result"] != nil else { return nil }
                        initialized = true
                        try send(["method": "initialized"])
                        try send(["id": 2, "method": "account/rateLimits/read"])
                    } else if id == 2 && initialized {
                        guard let result = message["result"] as? [String: Any] else { return nil }
                        return try JSONSerialization.data(withJSONObject: result)
                    }
                }
            }
        } catch { return nil }
        return nil
    }
}
