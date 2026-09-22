import AgentGridCore
import CryptoKit
import Foundation

/// Explicit development launch only: separate ports/files/pairing, no account or Hook access.
@MainActor
enum PaseoDevelopment {
    private struct Ports: Decodable {
        let hookPort: UInt16
        let phonePort: UInt16
    }

    static func model() throws -> BridgeModel {
        guard let path = ProcessInfo.processInfo.environment["AGENTPAGER_PASEO_CONFIG"],
              let ingress = PaseoIngressConfiguration.fromEnvironment() else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let ports = try JSONDecoder().decode(Ports.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        guard Set([ports.hookPort, ports.phonePort, ingress.port]).count == 3,
              [ports.hookPort, ports.phonePort, ingress.port].allSatisfy({ $0 > 1024 && $0 != 49_361 && $0 != 49_362 }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let secret = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        return BridgeModel(runtimeConfiguration: BridgeRuntimeConfiguration(
            hookPort: ports.hookPort, webSocketPort: ports.phonePort,
            pairingSecretLoader: { secret },
            taskPersistence: TaskSnapshotPersistence(fileURL: directory.appendingPathComponent("development-tasks.json")),
            observesLocalEnvironment: false, startsBackgroundMaintenance: false,
            usageLoader: { nil }, paseoIngress: ingress
        ), glmCoordinatorFactory: { _ in DisabledDevelopmentQuota() })
    }
}

private struct DisabledDevelopmentQuota: GLMQuotaCoordinating {
    func start() async {}
    func refresh() async {}
    func waitUntilIdle() async {}
    func saveCandidate(_ candidate: String) async -> Bool { false }
    func authorizeStoredKey() async -> Bool { false }
    func deleteKey() async -> Bool { false }
}
