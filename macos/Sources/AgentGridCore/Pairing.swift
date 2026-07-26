import Foundation
import Security

public struct PairingPayload: Codable, Equatable, Sendable {
    public var version: Int
    public var serviceID: String
    public var host: String
    public var port: UInt16
    public var secret: String

    public init(
        version: Int = 1,
        serviceID: String,
        host: String,
        port: UInt16,
        secret: String
    ) {
        self.version = version
        self.serviceID = serviceID
        self.host = host
        self.port = port
        self.secret = secret
    }
}

public enum PairingSecretStore {
    private static let service = "com.agentgrid.bridge"
    private static let account = "pairing-secret"

    public static func loadOrCreate() throws -> Data {
        if let value = load() {
            return value
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw CocoaError(.fileWriteUnknown)
        }
        let data = Data(bytes)
        try save(data)
        return data
    }

    public static func load() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    public static func save(_ data: Data) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var item = base
        item[kSecValueData as String] = data
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

public enum LocalNetworkAddress {
    public static func preferredIPv4() -> String {
        var addresses: [String] = []
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else {
            return "127.0.0.1"
        }
        defer { freeifaddrs(pointer) }

        for cursor in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = cursor.pointee
            guard interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }
            let name = String(cString: interface.ifa_name)
            guard name == "en0" || name == "en1" else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(
                interface.ifa_addr,
                socklen_t(interface.ifa_addr.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            let end = host.firstIndex(of: 0) ?? host.endIndex
            addresses.append(String(decoding: host[..<end].map(UInt8.init(bitPattern:)), as: UTF8.self))
        }
        return addresses.first ?? "127.0.0.1"
    }
}
