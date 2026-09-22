import CryptoKit
import Foundation
import Network

/// Opt-in development ingress; its secret is independent of phone pairing.
public struct PaseoIngressConfiguration: Codable, Sendable {
    public let port: UInt16
    public let token: String

    public init(port: UInt16, token: String) {
        self.port = port
        self.token = token
    }

    public static func fromEnvironment() -> Self? {
        guard let path = ProcessInfo.processInfo.environment["AGENTPAGER_PASEO_CONFIG"],
              let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
              let data = FileManager.default.contents(atPath: path),
              let config = try? JSONDecoder().decode(Self.self, from: data),
              config.isValid else { return nil }
        return config
    }

    var isValid: Bool {
        port > 1024 && token.count == 64 && token.allSatisfy { $0.isHexDigit && $0.isASCII }
    }
}

/// Only summary fields cross this boundary. No prompt, path, model credentials or tool payload.
public struct PaseoDiscovery: Decodable, Sendable {
    let hostID: String
    let agentID: String
    let provider: String
    let projectName: String
    let titleCategory: String
    let status: String
    let archived: Bool
    let connectionID: String?
    let revision: UInt64?
    let activity: AgentActivity?

    public var taskID: String {
        let identity = Data("\(hostID.utf8.count):\(hostID)\(agentID)".utf8)
        return "paseo:omp:" + SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
    }

    func task(now: Date) -> TaskSnapshot? {
        guard provider == "omp", !archived,
              !hostID.isEmpty, hostID.utf8.count <= 128,
              !agentID.isEmpty, agentID.utf8.count <= 128 else { return nil }
        let lifecycle: AgentLifecycle
        switch status {
        case "idle": lifecycle = .idle
        case "starting", "initializing": lifecycle = .starting
        case "running": lifecycle = .running
        case "succeeded": lifecycle = .succeeded
        default: lifecycle = .offline
        }
        let project = projectName.isEmpty || projectName.contains("/") || projectName.contains("\\")
            || projectName.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            ? "omp" : String(projectName.prefix(48))
        let prompt = ["development": "implement", "change": "fix", "verification": "test",
                      "reading": "read", "search": "search", "analysis": "analyze",
                      "request": "request"][titleCategory]
        var task = TaskSnapshot(id: taskID, source: .omp, projectName: project,
                                lifecycle: lifecycle, startedAt: now, updatedAt: now)
        task.title = ZCodeEventReducer.safeTitle(projectName: project, prompt: prompt)
        return task
    }
}

public final class PaseoIngressServer: @unchecked Sendable {
    private struct Request: Decodable {
        let token: String
    }
    private let configuration: PaseoIngressConfiguration
    private let handler: @Sendable (PaseoDiscovery) -> Void
    private let queue = DispatchQueue(label: "com.agentpager.paseo-ingress")
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]

    public init(configuration: PaseoIngressConfiguration,
                handler: @escaping @Sendable (PaseoDiscovery) -> Void) {
        self.configuration = configuration
        self.handler = handler
    }

    public func start() throws {
        guard configuration.isValid else { throw CocoaError(.fileReadCorruptFile) }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: configuration.port)!)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        self.listener = listener
        listener.start(queue: queue)
    }

    public func stop() {
        queue.sync {
            listener?.cancel()
            listener = nil
            connections.values.forEach { $0.cancel() }
            connections.removeAll()
        }
    }

    private func accept(_ connection: NWConnection) {
        guard connections.count < 16 else { connection.cancel(); return }
        let id = UUID()
        connections[id] = connection
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in self?.finish(id) }
        receive(id, buffer: Data())
    }

    private func finish(_ id: UUID) {
        connections.removeValue(forKey: id)?.cancel()
    }

    private func receive(_ id: UUID, buffer: Data) {
        guard let connection = connections[id] else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, complete, error in
            guard let self, self.connections[id] != nil else { return }
            let buffer = buffer + (data ?? Data())
            guard buffer.count <= 4096, error == nil else { self.finish(id); return }
            if let newline = buffer.firstIndex(of: 10) {
                let payload = Data(buffer.prefix(upTo: newline))
                let decoder = JSONDecoder()
                let authorized = (try? decoder.decode(Request.self, from: payload)).map {
                    SHA256.hash(data: Data($0.token.utf8)) == SHA256.hash(data: Data(self.configuration.token.utf8))
                } ?? false
                guard authorized, let discovery = try? decoder.decode(PaseoDiscovery.self, from: payload) else {
                    self.finish(id); return
                }
                self.handler(discovery)
                connection.send(content: Data("ok\n".utf8), completion: .contentProcessed { [weak self] _ in
                    self?.finish(id)
                })
            } else if complete { self.finish(id) }
            else { self.receive(id, buffer: buffer) }
        }
    }
}
