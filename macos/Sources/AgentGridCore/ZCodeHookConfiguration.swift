import CryptoKit
import Foundation

public enum ZCodeHookConfigurationStatus: String, Equatable, Sendable {
    case installed
    case repaired
    case unchanged
    case uninstalled
    case alreadyUninstalled
    case restoreConfirmationRequired
    case restored
    case noBackup
}

public struct ZCodeHookRestorePlan: Equatable, Sendable {
    public var backupURL: URL
    public var currentFingerprint: String

    public init(backupURL: URL, currentFingerprint: String) {
        self.backupURL = backupURL
        self.currentFingerprint = currentFingerprint
    }
}

public struct ZCodeHookConfigurationChange: Equatable, Sendable {
    public var status: ZCodeHookConfigurationStatus
    public var backupURL: URL?
    public var restoredFromURL: URL?
    public var restorePlan: ZCodeHookRestorePlan?

    public init(
        status: ZCodeHookConfigurationStatus,
        backupURL: URL? = nil,
        restoredFromURL: URL? = nil,
        restorePlan: ZCodeHookRestorePlan? = nil
    ) {
        self.status = status
        self.backupURL = backupURL
        self.restoredFromURL = restoredFromURL
        self.restorePlan = restorePlan
    }

    public var changed: Bool {
        [.installed, .repaired, .uninstalled, .restored].contains(status)
    }
}

public enum ZCodeHookFileError: LocalizedError, Equatable, Sendable {
    case readFailed
    case invalidJSON
    case backupFailed
    case writeFailed
    case invalidBackup
    case configurationChangedAfterConfirmation

    public var errorDescription: String? {
        switch self {
        case .readFailed:
            "无法安全读取 ZCode 配置，未执行修改"
        case .invalidJSON:
            "ZCode 配置不是有效的 JSON 对象，未执行覆盖"
        case .backupFailed:
            "无法创建并验证权限受限的 ZCode 配置备份，未执行修改"
        case .writeFailed:
            "ZCode 配置原子写入失败，原配置已尽力保持不变"
        case .invalidBackup:
            "最近的 AgentPager ZCode 备份无效，未执行恢复"
        case .configurationChangedAfterConfirmation:
            "ZCode 配置在恢复确认后发生变化，请重新检查并再次确认"
        }
    }
}

/// ZCode 用户级 Hook 配置入口。
///
/// 每次实际写入前都会创建 0600 权限的恢复点；无变化不会制造备份。
/// 恢复采用“检查后再次确认”的两步流程，并在确认与写入之间核对字节指纹。
public struct ZCodeHookConfiguration: Sendable {
    public let settingsURL: URL
    private let replacementWriter: @Sendable (Data, URL) throws -> Void

    private let backupPrefix = "config.json.agentpager-zcode-backup"
    private let beforeRestorePrefix = "config.json.agentpager-zcode-before-restore"
    private let absentMarker = Data("AgentPager ZCode backup: source file absent\n".utf8)

    public init(settingsURL: URL? = nil) {
        self.settingsURL = settingsURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".zcode/cli/config.json")
        replacementWriter = { contents, url in
            try contents.write(to: url, options: .atomic)
        }
    }

    init(
        settingsURL: URL,
        replacementWriter: @escaping @Sendable (Data, URL) throws -> Void
    ) {
        self.settingsURL = settingsURL
        self.replacementWriter = replacementWriter
    }

    public func isInstalled(command: String) -> Bool {
        ZCodeHookInstaller.isInstalled(
            data: try? Data(contentsOf: settingsURL),
            command: command
        )
    }

    public func containsManagedHooks() -> Bool {
        ZCodeHookInstaller.containsManagedHooks(
            data: try? Data(contentsOf: settingsURL)
        )
    }

    public func install(
        command: String,
        now: Date = .now
    ) throws -> ZCodeHookConfigurationChange {
        let existing = try readExisting()
        let hadManagedHooks = ZCodeHookInstaller.containsManagedHooks(data: existing)
        let mutation: HookFileMutation
        do {
            mutation = try ZCodeHookInstaller.install(
                existingData: existing,
                command: command
            )
        } catch let error as ZCodeHookConfigurationError {
            throw error
        } catch {
            throw ZCodeHookFileError.invalidJSON
        }
        guard mutation.changed, let contents = mutation.contents else {
            return ZCodeHookConfigurationChange(status: .unchanged)
        }

        try createParentDirectory()
        let backupURL = try createBackup(existing, prefix: backupPrefix, now: now)
        try replaceSettings(with: contents, previous: existing)
        return ZCodeHookConfigurationChange(
            status: hadManagedHooks ? .repaired : .installed,
            backupURL: backupURL
        )
    }

    public func uninstall(
        now: Date = .now
    ) throws -> ZCodeHookConfigurationChange {
        let existing = try readExisting()
        let mutation: HookFileMutation
        do {
            mutation = try ZCodeHookInstaller.uninstall(existingData: existing)
        } catch let error as ZCodeHookConfigurationError {
            throw error
        } catch {
            throw ZCodeHookFileError.invalidJSON
        }
        guard mutation.changed, let contents = mutation.contents else {
            return ZCodeHookConfigurationChange(status: .alreadyUninstalled)
        }

        try createParentDirectory()
        let backupURL = try createBackup(existing, prefix: backupPrefix, now: now)
        try replaceSettings(with: contents, previous: existing)
        return ZCodeHookConfigurationChange(status: .uninstalled, backupURL: backupURL)
    }

    public func prepareRestoreLatestBackup() throws -> ZCodeHookConfigurationChange {
        guard let backupURL = latestBackupURL() else {
            return ZCodeHookConfigurationChange(status: .noBackup)
        }
        let plan = ZCodeHookRestorePlan(
            backupURL: backupURL,
            currentFingerprint: fingerprint(try readExisting())
        )
        return ZCodeHookConfigurationChange(
            status: .restoreConfirmationRequired,
            restoredFromURL: backupURL,
            restorePlan: plan
        )
    }

    public func restoreLatestBackup(
        using plan: ZCodeHookRestorePlan,
        now: Date = .now
    ) throws -> ZCodeHookConfigurationChange {
        guard isManagedBackupURL(plan.backupURL) else {
            throw ZCodeHookFileError.invalidBackup
        }
        let existing = try readExisting()
        guard fingerprint(existing) == plan.currentFingerprint else {
            throw ZCodeHookFileError.configurationChangedAfterConfirmation
        }

        let restored: Data?
        if plan.backupURL.pathExtension == "absent" {
            guard (try? Data(contentsOf: plan.backupURL)) == absentMarker else {
                throw ZCodeHookFileError.invalidBackup
            }
            restored = nil
        } else {
            do {
                let data = try Data(contentsOf: plan.backupURL)
                guard try JSONSerialization.jsonObject(with: data) is [String: Any] else {
                    throw ZCodeHookFileError.invalidBackup
                }
                restored = data
            } catch let error as ZCodeHookFileError {
                throw error
            } catch {
                throw ZCodeHookFileError.invalidBackup
            }
        }

        guard restored != existing else {
            return ZCodeHookConfigurationChange(status: .unchanged)
        }

        try createParentDirectory()
        let recoveryURL = try createBackup(
            existing,
            prefix: beforeRestorePrefix,
            now: now
        )
        if let restored {
            try replaceSettings(with: restored, previous: existing)
        } else {
            do {
                if FileManager.default.fileExists(atPath: settingsURL.path) {
                    try FileManager.default.removeItem(at: settingsURL)
                }
            } catch {
                throw ZCodeHookFileError.writeFailed
            }
        }
        return ZCodeHookConfigurationChange(
            status: .restored,
            backupURL: recoveryURL,
            restoredFromURL: plan.backupURL
        )
    }

    private func readExisting() throws -> Data? {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else {
            return nil
        }
        do {
            return try Data(contentsOf: settingsURL)
        } catch {
            throw ZCodeHookFileError.readFailed
        }
    }

    private func createParentDirectory() throws {
        do {
            try FileManager.default.createDirectory(
                at: settingsURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw ZCodeHookFileError.writeFailed
        }
    }

    private func createBackup(
        _ data: Data?,
        prefix: String,
        now: Date
    ) throws -> URL {
        let isAbsent = data == nil
        let baseName = "\(prefix)-\(Int(now.timeIntervalSince1970))"
            + (isAbsent ? ".absent" : "")
        let directory = settingsURL.deletingLastPathComponent()
        let baseURL = directory.appendingPathComponent(baseName)
        var backupURL = baseURL
        var suffix = 1
        while FileManager.default.fileExists(atPath: backupURL.path) {
            let suffixedName = isAbsent
                ? "\(prefix)-\(Int(now.timeIntervalSince1970))-\(suffix).absent"
                : "\(baseName)-\(suffix)"
            backupURL = directory.appendingPathComponent(suffixedName)
            suffix += 1
        }

        let contents = data ?? absentMarker
        let created = FileManager.default.createFile(
            atPath: backupURL.path,
            contents: contents,
            attributes: [.posixPermissions: 0o600]
        )
        guard created else {
            throw ZCodeHookFileError.backupFailed
        }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: backupURL.path)
            let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
            guard try Data(contentsOf: backupURL) == contents,
                  permissions & 0o777 == 0o600 else {
                throw ZCodeHookFileError.backupFailed
            }
            return backupURL
        } catch let error as ZCodeHookFileError {
            throw error
        } catch {
            throw ZCodeHookFileError.backupFailed
        }
    }

    private func replaceSettings(with contents: Data, previous: Data?) throws {
        let previousPermissions = (try? FileManager.default.attributesOfItem(
            atPath: settingsURL.path
        )[.posixPermissions] as? NSNumber)?.intValue ?? 0o600
        do {
            try replacementWriter(contents, settingsURL)
            try FileManager.default.setAttributes(
                [.posixPermissions: previousPermissions & 0o777],
                ofItemAtPath: settingsURL.path
            )
            guard try Data(contentsOf: settingsURL) == contents else {
                throw ZCodeHookFileError.writeFailed
            }
        } catch {
            if let previous {
                try? previous.write(to: settingsURL, options: .atomic)
                try? FileManager.default.setAttributes(
                    [.posixPermissions: previousPermissions & 0o777],
                    ofItemAtPath: settingsURL.path
                )
            } else {
                try? FileManager.default.removeItem(at: settingsURL)
            }
            throw ZCodeHookFileError.writeFailed
        }
    }

    private func latestBackupURL() -> URL? {
        let directory = settingsURL.deletingLastPathComponent()
        let prefix = "\(backupPrefix)-"
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [
                .contentModificationDateKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        return files
            .filter { url in
                guard url.lastPathComponent.hasPrefix(prefix),
                      let values = try? url.resourceValues(
                        forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
                      ) else {
                    return false
                }
                return values.isRegularFile == true && values.isSymbolicLink != true
            }
            .max { lhs, rhs in
                let lhsDate = try? lhs.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate
                let rhsDate = try? rhs.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate
                if lhsDate == rhsDate {
                    return lhs.lastPathComponent < rhs.lastPathComponent
                }
                return (lhsDate ?? .distantPast) < (rhsDate ?? .distantPast)
            }
    }

    private func isManagedBackupURL(_ url: URL) -> Bool {
        guard url.deletingLastPathComponent().standardizedFileURL
                == settingsURL.deletingLastPathComponent().standardizedFileURL,
              url.lastPathComponent.hasPrefix("\(backupPrefix)-"),
              let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
              ),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let attributes = try? FileManager.default.attributesOfItem(
                atPath: url.path
              ),
              let permissions = attributes[.posixPermissions] as? NSNumber else {
            return false
        }
        return permissions.intValue & 0o777 == 0o600
    }

    private func fingerprint(_ data: Data?) -> String {
        var value = Data(data == nil ? "absent:".utf8 : "present:".utf8)
        if let data {
            value.append(data)
        }
        return SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined()
    }
}
