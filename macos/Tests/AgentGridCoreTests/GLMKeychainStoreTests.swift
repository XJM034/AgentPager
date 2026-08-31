import Foundation
import Security
import Testing
@testable import AgentGridCore

@Suite(.serialized)
struct GLMKeychainStoreTests {
    @Test("真实隔离钥匙串可重复读取，锁定时静默失败，解锁后恢复且不改变交互策略")
    func isolatedKeychainReadsRespectLockAndRestoreInteractionPolicy() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentpager-keychain-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let password = "synthetic-test-only-password"
        var keychain: SecKeychain?
        let createStatus = password.withCString {
            SecKeychainCreate(
                directory.appendingPathComponent("test.keychain").path,
                UInt32(password.utf8.count), $0, false, nil, &keychain
            )
        }
        #expect(createStatus == errSecSuccess)
        let isolated = try #require(keychain)
        defer { #expect(SecKeychainDelete(isolated) == errSecSuccess) }

        let store = GLMKeychainStore(service: "agentpager-test", account: "synthetic", keychain: isolated)
        try store.save("synthetic-test-key")
        var before: DarwinBoolean = false
        #expect(SecKeychainGetUserInteractionAllowed(&before) == errSecSuccess)
        for _ in 0..<3 { #expect(try store.load() == "synthetic-test-key") }

        #expect(SecKeychainLock(isolated) == errSecSuccess)
        #expect(try store.exists())
        #expect(throws: GLMKeyAccessError.authorizationRequired) { try store.load() }
        var after: DarwinBoolean = false
        #expect(SecKeychainGetUserInteractionAllowed(&after) == errSecSuccess)
        #expect(after.boolValue == before.boolValue)

        let unlockStatus = password.withCString {
            SecKeychainUnlock(isolated, UInt32(password.utf8.count), $0, true)
        }
        #expect(unlockStatus == errSecSuccess)
        #expect(try store.load() == "synthetic-test-key")
        let reopened = GLMKeychainStore(service: "agentpager-test", account: "synthetic", keychain: isolated)
        #expect(try reopened.load() == "synthetic-test-key")
        try reopened.delete()
        #expect(try store.load() == nil)

        // Model an item trusted to a different executable (e.g. an older ad-hoc build).
        var otherApplication: SecTrustedApplication?
        #expect(SecTrustedApplicationCreateFromPath("/usr/bin/false", &otherApplication) == errSecSuccess)
        let other = try #require(otherApplication)
        var access: SecAccess?
        #expect(SecAccessCreate("AgentPager synthetic test" as CFString, [other] as CFArray, &access) == errSecSuccess)
        let restrictedAccess = try #require(access)
        let restricted: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "agentpager-test",
            kSecAttrAccount as String: "synthetic",
            kSecUseKeychain as String: isolated,
            kSecAttrAccess as String: restrictedAccess,
            kSecValueData as String: Data("synthetic-denied-key".utf8),
        ]
        #expect(SecItemAdd(restricted as CFDictionary, nil) == errSecSuccess)
        #expect(try store.exists())
        #expect(throws: GLMKeyAccessError.authorizationRequired) { try store.load() }
        #expect(SecKeychainGetUserInteractionAllowed(&after) == errSecSuccess)
        #expect(after.boolValue == before.boolValue)
    }
}
