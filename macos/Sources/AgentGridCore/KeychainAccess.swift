import Foundation
import Security

/// Serializes this process's legacy keychain calls. The UI policy is process-wide;
/// pairing and GLM must share this gate so a silent read cannot suppress pairing UI.
enum KeychainAccess {
    private static let lock = NSRecursiveLock()

    static func serialized<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }

    static func withoutInteraction<T>(_ operation: () throws -> T) throws -> T {
        try serialized {
            // Per-query kSecUseAuthenticationUI does not reliably cover legacy file keychains.
            // Scope the legacy API to this synchronous call; never hold it over an await.
            var previous: DarwinBoolean = false
            try check(SecKeychainGetUserInteractionAllowed(&previous))
            try check(SecKeychainSetUserInteractionAllowed(false))
            let result = Result(catching: operation)
            try check(SecKeychainSetUserInteractionAllowed(previous.boolValue))
            return try result.get()
        }
    }

    private static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw GLMKeychainError(status: status) }
    }
}
