import Dispatch
import Foundation

/// 通过本机 CodexBar CLI 读取按 API 单价折算的 Codex 历史费用。
enum CodexBarCostLoader {
    private static let commandTimeout: TimeInterval = 30

    private struct CostPayload: Decodable {
        var provider: String
        var daily: [DailyEntry]
    }

    private struct DailyEntry: Decodable {
        var date: String
        var inputTokens: Int64
        var outputTokens: Int64
        var cacheReadTokens: Int64?
        var totalTokens: Int64
        var totalCost: Double?
    }

    static func load(
        historyDays: Int,
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [DailyUsagePoint]? {
        guard let executableURL = executableURL(
            fileManager: fileManager,
            environment: environment
        ),
        let data = run(
            executableURL: executableURL,
            arguments: [
                "cost",
                "--provider", "codex",
                "--days", String(historyDays),
                "--format", "json",
            ]
        ) else {
            return nil
        }
        return parse(data)
    }

    static func parse(_ data: Data) -> [DailyUsagePoint]? {
        guard let payloads = try? JSONDecoder().decode([CostPayload].self, from: data),
              let payload = payloads.first(where: { $0.provider == "codex" }) else {
            return nil
        }

        return payload.daily.map { entry in
            DailyUsagePoint(
                date: entry.date,
                inputTokens: entry.inputTokens,
                cachedInputTokens: entry.cacheReadTokens ?? 0,
                outputTokens: entry.outputTokens,
                totalTokens: entry.totalTokens,
                estimatedCostUSD: entry.totalCost
            )
        }
    }

    private static func executableURL(
        fileManager: FileManager,
        environment: [String: String]
    ) -> URL? {
        var candidates: [String] = []
        if let override = environment["CODEXBAR_PATH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            candidates.append(override)
        }

        candidates.append(contentsOf: [
            "/opt/homebrew/bin/codexbar",
            "/usr/local/bin/codexbar",
            "/Applications/CodexBar.app/Contents/Helpers/CodexBarCLI",
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(
                    "Applications/CodexBar.app/Contents/Helpers/CodexBarCLI"
                )
                .path,
        ])

        if let path = environment["PATH"] {
            candidates.append(contentsOf: path
                .split(separator: ":")
                .map { URL(fileURLWithPath: String($0)).appendingPathComponent("codexbar").path })
        }

        return candidates
            .map { URL(fileURLWithPath: $0) }
            .first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    private static func run(
        executableURL: URL,
        arguments: [String]
    ) -> Data? {
        let process = Process()
        let output = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let timeout = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + commandTimeout,
            execute: timeout
        )

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()
        return process.terminationStatus == 0 ? data : nil
    }
}
