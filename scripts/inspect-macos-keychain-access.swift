// Read-only diagnostics for AgentPager's two keychain items. Never request secret data.
// Usage: swift -suppress-warnings scripts/inspect-macos-keychain-access.swift [--expect-stable]
import Foundation
import Security

let appURL = URL(fileURLWithPath: "/Applications/AgentPager Bridge.app")
var code: SecStaticCode?
let codeStatus = SecStaticCodeCreateWithPath(appURL as CFURL, [], &code)
var report: [String: Any] = ["codeStatus": codeStatus]
var stablePartition = false
if codeStatus == errSecSuccess, let code {
    var info: CFDictionary?
    let infoStatus = SecCodeCopySigningInformation(
        code, SecCSFlags(rawValue: kSecCSSigningInformation), &info
    )
    report["signingInfoStatus"] = infoStatus
    if let info = info as? [String: Any] {
        report["identifier"] = info[kSecCodeInfoIdentifier as String]
        let team = info[kSecCodeInfoTeamIdentifier as String] as? String
        report["teamIdentifier"] = team
        if let hash = info[kSecCodeInfoUnique as String] as? Data {
            report["cdhash"] = hash.map { String(format: "%02x", $0) }.joined()
        }
        var requirement: SecRequirement?
        let requirementStatus = SecRequirementCreateWithString(
            "anchor apple generic" as CFString, [], &requirement
        )
        let appleSigned = requirementStatus == errSecSuccess && requirement != nil
            && SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess
        report["appleSigned"] = appleSigned
        stablePartition = appleSigned && team?.isEmpty == false
    }
}
report["stablePartitionSigning"] = stablePartition

var previous: DarwinBoolean = false
let getPolicy = SecKeychainGetUserInteractionAllowed(&previous)
let setPolicy = getPolicy == errSecSuccess
    ? SecKeychainSetUserInteractionAllowed(false) : getPolicy
report["silentPolicyStatus"] = setPolicy
var items: [[String: Any]] = []
if setPolicy == errSecSuccess {
    defer { _ = SecKeychainSetUserInteractionAllowed(previous.boolValue) }
    for (name, service, account) in [
        ("GLM", "com.agentpager.bridge.glm-coding-plan", "coding-plan-key"),
        ("Pairing", "com.agentgrid.bridge", "pairing-secret"),
    ] {
        var item: SecKeychainItem?
        let status = service.withCString { serviceBytes in
            account.withCString { accountBytes in
                SecKeychainFindGenericPassword(
                    nil, UInt32(service.utf8.count), serviceBytes,
                    UInt32(account.utf8.count), accountBytes,
                    nil, nil, &item
                )
            }
        }
        var row: [String: Any] = ["item": name, "lookupStatus": status]
        if status == errSecSuccess, let item {
            var access: SecAccess?
            let accessStatus = SecKeychainItemCopyAccess(item, &access)
            row["accessStatus"] = accessStatus
            if accessStatus == errSecSuccess, let access {
                var list: CFArray?
                row["aclListStatus"] = SecAccessCopyACLList(access, &list)
                var partitions: [String] = []
                var foundPartitionACL = false
                for acl in list as? [SecACL] ?? [] {
                    let authorizations = SecACLCopyAuthorizations(acl) as? [String] ?? []
                    guard authorizations.contains(kSecACLAuthorizationPartitionID as String) else {
                        continue
                    }
                    foundPartitionACL = true
                    var applications: CFArray?
                    var description: CFString?
                    var selector = SecKeychainPromptSelector()
                    let contentsStatus = SecACLCopyContents(
                        acl, &applications, &description, &selector
                    )
                    row["partitionContentsStatus"] = contentsStatus
                    guard contentsStatus == errSecSuccess, let hex = description as String?,
                          hex.utf8.count.isMultiple(of: 2) else { continue }
                    let chars = Array(hex.utf8)
                    var bytes: [UInt8] = []
                    for index in stride(from: 0, to: chars.count, by: 2) {
                        guard let byte = UInt8(String(decoding: chars[index ..< index + 2], as: UTF8.self), radix: 16) else {
                            bytes.removeAll()
                            break
                        }
                        bytes.append(byte)
                    }
                    if let plist = try? PropertyListSerialization.propertyList(
                        from: Data(bytes), format: nil
                    ) as? [String: Any] {
                        partitions = plist["Partitions"] as? [String] ?? []
                    }
                }
                row["hasPartitionACL"] = foundPartitionACL
                row["partitions"] = partitions
            }
        }
        items.append(row)
    }
}
report["items"] = items
let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: data, as: UTF8.self))
if CommandLine.arguments.contains("--expect-stable"), !stablePartition {
    fputs("This signature cannot provide a stable Apple team partition across builds.\n", stderr)
    exit(1)
}
