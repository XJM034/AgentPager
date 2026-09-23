import AgentGridCore
import CryptoKit
import Darwin
import Foundation

enum PaseoMonitoringStatus {
    case disabled, unavailable, connected, empty

    var text: String {
        switch self {
        case .disabled: "未启用"
        case .unavailable: "连接不可用"
        case .connected: "已连接"
        case .empty: "已连接 · 暂无会话"
        }
    }
    var isConnected: Bool { self == .connected || self == .empty }
}

/// Owns only AgentPager's local settings and its named Paseo plugin.
struct PaseoIntegration: Sendable {
    enum Action: Sendable { case enable, disable, revoke }
    enum Failure: Error, LocalizedError {
        case unavailable, prerequisites, conflictingPlugin, invalidConfiguration, incompatibleVersion
        var errorDescription: String? {
            switch self {
            case .unavailable: "Paseo 连接不可用，请确认本机 Paseo 已启动。"
            case .prerequisites: "请先在 Paseo 设置中启用插件及 omp；插件总开关会影响其他插件，AgentPager 不会自动改写。"
            case .conflictingPlugin: "同名插件来自其他位置，未覆盖；请先在 Paseo 核对。"
            case .invalidConfiguration: "接入配置或插件资源无效，未继续操作。"
            case .incompatibleVersion: "Paseo 版本与监控插件不兼容，请更新 AgentPager Bridge 后恢复接入。"
            }
        }
    }
    private struct Plugin: Decodable {
        var id: String
        var path: String
        var enabled: Bool
        var status: String
        var error: String?
        var isIncompatible: Bool {
            status == "failed" && error?.hasPrefix("Plugin \"agentpager-omp\" requires Paseo ") == true
        }
    }
    private struct Settings: Codable, Equatable {
        var enabled: Bool
        var port: UInt16
        var token: String
        var hostID: String
        var paseoURL: String
        var pluginFingerprint: String?
        var ingress: PaseoIngressConfiguration {
            PaseoIngressConfiguration(port: port, token: token, hostID: hostID)
        }
    }
    let directory: URL
    let pluginURL: URL
    let daemonConfigURL: URL
    let command: @Sendable ([String]) throws -> Data
    var backupDirectory: URL { directory.appendingPathComponent("backups") }
    private var settingsURL: URL { directory.appendingPathComponent("paseo.json") }

    init(directory: URL, pluginURL: URL, daemonConfigURL: URL,
         command: @escaping @Sendable ([String]) throws -> Data) {
        self.directory = directory
        self.pluginURL = pluginURL
        self.daemonConfigURL = daemonConfigURL
        self.command = command
    }

    static func local() -> Self {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return Self(directory: home.appendingPathComponent(".config/agentpager"),
            pluginURL: Bundle.main.resourceURL!.appendingPathComponent("paseo-omp"),
            daemonConfigURL: home.appendingPathComponent(".paseo/config.json"), command: PaseoCommand.run)
    }

    func configuration() throws -> PaseoIngressConfiguration? {
        guard let settings = try readSettings(), settings.enabled else { return nil }
        return settings.ingress
    }

    func perform(_ action: Action) throws -> PaseoIngressConfiguration? {
        let existing = try readSettings()
        // Local shutdown must remain durable even when Paseo is unreachable.
        if action == .disable, var settings = existing {
            settings.enabled = false
            try writeSettings(settings)
        }
        let daemonData = try Data(contentsOf: daemonConfigURL)
        guard let daemon = try JSONSerialization.jsonObject(with: daemonData) as? [String: Any] else {
            throw Failure.invalidConfiguration
        }
        let plugins = daemon["plugins"] as? [String: Any] ?? [:]
        if let entry = plugins["agentpager-omp"] as? [String: Any],
           entry["path"] as? String != pluginURL.path { throw Failure.conflictingPlugin }
        switch action {
        case .enable:
            guard daemon["pluginsEnabled"] as? Bool == true else { throw Failure.prerequisites }
            let fingerprint = try pluginFingerprint()
            let running = try pluginState()
            if let existing, existing.enabled, existing.pluginFingerprint == fingerprint,
               running?.enabled == true, running?.status == "running" { return existing.ingress }
            var settings = existing ?? Settings(enabled: false, port: 49_463,
                token: SymmetricKey(size: .bits256).withUnsafeBytes { Data($0).map { String(format: "%02x", $0) }.joined() },
                hostID: UUID().uuidString, paseoURL: "ws://127.0.0.1:6767/ws")
            settings.enabled = true
            try writeSettings(settings)
            try backup(daemonConfigURL)
            do {
                if plugins["agentpager-omp"] == nil {
                    _ = try command(["plugin", "install", pluginURL.path, "--json", "--host", "localhost:6767"])
                } else {
                    _ = try command(["plugin", "enable", "agentpager-omp", "--json", "--host", "localhost:6767"])
                    _ = try command(["plugin", "reload", "agentpager-omp", "--json", "--host", "localhost:6767"])
                }
            } catch {
                if (try? pluginState())?.isIncompatible == true { throw Failure.incompatibleVersion }
                throw error
            }
            let installed = try pluginState()
            if installed?.isIncompatible == true {
                throw Failure.incompatibleVersion
            }
            guard installed?.enabled == true, installed?.status == "running" else {
                throw Failure.unavailable
            }
            settings.pluginFingerprint = fingerprint
            try writeSettings(settings)
            return settings.ingress
        case .disable, .revoke:
            guard var settings = existing else { return nil }
            let installed = try pluginState()
            if action == .disable && !settings.enabled && installed?.enabled != true { return nil }
            settings.enabled = false
            try writeSettings(settings)
            try backup(daemonConfigURL)
            if installed != nil {
                _ = try command(["plugin", action == .revoke ? "remove" : "disable", "agentpager-omp", "--json", "--host", "localhost:6767"])
            }
            if action == .revoke {
                try backup(settingsURL)
                try FileManager.default.removeItem(at: settingsURL)
            }
            return nil
        }
    }

    private func pluginState() throws -> Plugin? {
        let records = try JSONDecoder().decode([Plugin].self, from:
            command(["plugin", "ls", "--json", "--host", "localhost:6767"]))
        guard let plugin = records.first(where: { $0.id == "agentpager-omp" }) else { return nil }
        guard plugin.path == pluginURL.path else { throw Failure.conflictingPlugin }
        return plugin
    }

    private func pluginFingerprint() throws -> String {
        var digest = SHA256()
        for path in ["index.server.ts", "server/discovery.mjs", "paseo-plugin.json", "package-lock.json"] {
            digest.update(data: try Data(contentsOf: pluginURL.appendingPathComponent(path)))
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func readSettings() throws -> Settings? {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return nil }
        let attributes = try FileManager.default.attributesOfItem(atPath: settingsURL.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600 else { throw Failure.invalidConfiguration }
        let settings = try JSONDecoder().decode(Settings.self, from: Data(contentsOf: settingsURL))
        guard settings.port > 1024, settings.token.count == 64,
              settings.token.allSatisfy({ $0.isASCII && $0.isHexDigit }),
              UUID(uuidString: settings.hostID) != nil,
              settings.paseoURL == "ws://127.0.0.1:6767/ws" else { throw Failure.invalidConfiguration }
        return settings
    }

    private func writeSettings(_ settings: Settings) throws {
        let data = try JSONEncoder().encode(settings)
        if let previous = try readSettings(),
           previous == settings { return }
        try privateDirectory(directory)
        try backup(settingsURL)
        try data.write(to: settingsURL, options: [.atomic, .completeFileProtection])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsURL.path)
    }

    private func backup(_ file: URL) throws {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try privateDirectory(backupDirectory)
        let data = try Data(contentsOf: file)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let destination = backupDirectory.appendingPathComponent("\(digest)-\(file.lastPathComponent)")
        if FileManager.default.fileExists(atPath: destination.path) {
            guard try Data(contentsOf: destination) == data else { throw Failure.invalidConfiguration }
            return
        }
        try FileManager.default.copyItem(at: file, to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }

    private func privateDirectory(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw Failure.invalidConfiguration }
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                              attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }
}

/// Executes the official local CLI off the UI thread, with bounded output and runtime.
private enum PaseoCommand {
    static func run(_ arguments: [String]) throws -> Data {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/Applications/Paseo.app/Contents/Resources/bin/paseo")
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        try? output.fileHandleForWriting.close()
        defer {
            try? output.fileHandleForReading.close()
            if process.isRunning { process.terminate() }
            let deadline = ProcessInfo.processInfo.systemUptime + 0.25
            while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline { Thread.sleep(forTimeInterval: 0.01) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 20
        var data = Data()
        while ProcessInfo.processInfo.systemUptime < deadline {
            var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 100)
            if ready < 0 && errno == EINTR { continue }
            guard ready >= 0 else { throw PaseoIntegration.Failure.unavailable }
            if ready == 0 { continue }
            var bytes = [UInt8](repeating: 0, count: 8192)
            let count = read(descriptor.fd, &bytes, bytes.count)
            if count == 0 {
                while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline {
                    Thread.sleep(forTimeInterval: 0.01)
                }
                guard !process.isRunning, process.terminationStatus == 0 else { throw PaseoIntegration.Failure.unavailable }
                return data
            }
            guard count > 0, data.count + count <= 1_048_576 else { throw PaseoIntegration.Failure.unavailable }
            data.append(contentsOf: bytes.prefix(count))
        }
        throw PaseoIntegration.Failure.unavailable
    }
}
