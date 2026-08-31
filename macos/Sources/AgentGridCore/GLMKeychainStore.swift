import Foundation
import Security

public final class GLMKeychainStore: GLMKeyStore, @unchecked Sendable {
    public static let defaultService = "com.agentpager.bridge.glm-coding-plan"
    public static let defaultAccount = "coding-plan-key"

    private let service: String
    private let account: String
    private let keychain: SecKeychain?

    public init(
        service: String = GLMKeychainStore.defaultService,
        account: String = GLMKeychainStore.defaultAccount,
        keychain: SecKeychain? = nil
    ) {
        self.service = service
        self.account = account
        self.keychain = keychain
    }

    public func exists() throws -> Bool {
        let status = try KeychainAccess.withoutInteraction {
            findItem(nil)
        }
        if status == errSecItemNotFound {
            return false
        }
        try check(status)
        return true
    }

    public func load() throws -> String? {
        try KeychainAccess.withoutInteraction { try read(allowInteraction: false) }
    }

    public func authorizeAccess() throws {
        try KeychainAccess.serialized {
            // Let macOS offer its existing per-app consent choices. Never broaden the ACL ourselves.
            _ = try read(allowInteraction: true)
            try verifyPersistentAccess()
        }
    }

    private func read(allowInteraction: Bool) throws -> String? {
        if !allowInteraction { try requireUnlockedKeychain() }
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationUI as String] = allowInteraction
            ? kSecUseAuthenticationUIAllow : kSecUseAuthenticationUIFail
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        try check(status)
        guard let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw GLMKeychainError(status: errSecDecode)
        }
        return key
    }

    private func requireUnlockedKeychain() throws {
        var item: SecKeychainItem?
        let status = findItem(&item)
        if status == errSecItemNotFound { return }
        try check(status)
        guard let item else { throw GLMKeychainError(status: errSecDecode) }
        var owningKeychain: SecKeychain?
        try check(SecKeychainItemCopyKeychain(item, &owningKeychain))
        guard let owningKeychain else { throw GLMKeychainError(status: errSecDecode) }
        var statusFlags: SecKeychainStatus = 0
        try check(SecKeychainGetStatus(owningKeychain, &statusFlags))
        // On legacy keychains an already-open database can retain unlock UI credentials.
        // Check its lock state before requesting any secret data, even with UI disabled.
        guard statusFlags & UInt32(kSecUnlockStateStatus) != 0 else {
            throw GLMKeyAccessError.authorizationRequired
        }
    }

    private func findItem(_ item: UnsafeMutablePointer<SecKeychainItem?>?) -> OSStatus {
        // Metadata lookup only: do not request password length or data here.
        service.withCString { serviceBytes in
            account.withCString { accountBytes in
                SecKeychainFindGenericPassword(
                    keychain, UInt32(service.utf8.count), serviceBytes,
                    UInt32(account.utf8.count), accountBytes, nil, nil, item
                )
            }
        }
    }

    public func save(_ key: String) throws {
        try KeychainAccess.serialized {
            try write(key)
            try verifyPersistentAccess()
        }
    }

    private func write(_ key: String) throws {
        let data = Data(key.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            try check(updateStatus)
            return
        }

        var item = baseQuery
        item.removeValue(forKey: kSecMatchSearchList as String)
        if let keychain { item[kSecUseKeychain as String] = keychain }
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        try check(addStatus)
    }

    public func delete() throws {
        try KeychainAccess.serialized {
            let status = SecItemDelete(baseQuery as CFDictionary)
            if status != errSecItemNotFound { try check(status) }
        }
    }

    private func verifyPersistentAccess() throws {
        do {
            _ = try load()
        } catch GLMKeyAccessError.authorizationRequired {
            throw GLMKeyAccessError.authorizationNotPersistent
        }
    }

    private func check(_ status: OSStatus) throws {
        switch status {
        case errSecSuccess: return
        case errSecInteractionNotAllowed, errSecInteractionRequired, errSecAuthFailed, errSecUserCanceled:
            throw GLMKeyAccessError.authorizationRequired
        default:
            throw GLMKeychainError(status: status)
        }
    }

    private var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let keychain { query[kSecMatchSearchList as String] = [keychain] }
        return query
    }
}

public struct GLMKeychainError: Error, Equatable, Sendable {
    public var status: OSStatus

    public init(status: OSStatus) {
        self.status = status
    }
}
