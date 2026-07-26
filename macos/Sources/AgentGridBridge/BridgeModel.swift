import AgentGridCore
import Foundation
import Observation

@MainActor
@Observable
final class BridgeModel {
    private(set) var tasks: [TaskSnapshot] = []
    private(set) var usage: UsageSnapshot?
    private(set) var focusedTaskID: String?
    private(set) var phoneCount = 0
    private(set) var serviceStatus = "正在启动"
    private(set) var hookInstalled = false
    private(set) var lastError: String?
    private(set) var pairingText = ""
    private(set) var recentEvents: [String] = []

    private var store = TaskStore()
    private var replayGuard = ReplayGuard()
    private var pairingSecret = Data()
    private let persistence = TaskSnapshotPersistence()
    private var rolloutReader = CodexRolloutReader()
    private let sessionTitleReader = CodexSessionTitleReader()
    private var sessionTitleSynchronizer = CodexSessionTitleSynchronizer()
    private var hookServer: HookBridgeServer?
    private var webSocketServer: WebSocketServer?
    private var refreshTask: Task<Void, Never>?
    private var rolloutTask: Task<Void, Never>?
    private var hasStarted = false
    private var pendingRequests: [String: PendingRequest] = [:]

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        store = TaskStore(tasks: persistence.load())
        store.purge()
        publishStore()

        do {
            pairingSecret = try PairingSecretStore.loadOrCreate()
            let payload = PairingPayload(
                serviceID: "agentgrid-\(Host.current().localizedName ?? "mac")",
                host: LocalNetworkAddress.preferredIPv4(),
                port: 49_362,
                secret: pairingSecret.base64EncodedString()
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let pairingPayloadText =
                String(data: try encoder.encode(payload), encoding: .utf8) ?? ""
            pairingText = pairingPayloadText

            let hookServer = HookBridgeServer { [weak self] hook in
                Task { @MainActor in
                    self?.handle(hook)
                }
            }
            try hookServer.start()
            self.hookServer = hookServer

            let webSocketServer = WebSocketServer(
                messageHandler: { [weak self] text in
                    Task { @MainActor in
                        self?.handleControl(text)
                    }
                },
                countHandler: { [weak self] count in
                    Task { @MainActor in
                        self?.phoneCount = count
                        self?.broadcastSnapshot()
                    }
                },
                localHTTPHandler: { path in
                    path == "/pairing" ? pairingPayloadText : nil
                }
            )
            try webSocketServer.start()
            self.webSocketServer = webSocketServer
            serviceStatus = "局域网服务运行中"
        } catch {
            serviceStatus = "服务启动失败"
            lastError = error.localizedDescription
        }

        refreshHookStatus()
        refreshUsage()
        discoverRolloutSessions()
        handleRolloutSignals()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self else { return }
                self.refreshUsage()
                self.store.purge()
                self.publishStore()
            }
        }
        rolloutTask = Task { [weak self] in
            var nextDiscovery = Date.distantPast
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(750))
                guard let self else { return }
                if Date.now >= nextDiscovery {
                    self.discoverRolloutSessions()
                    nextDiscovery = Date.now.addingTimeInterval(3)
                    if self.refreshCodexTitles() {
                        self.publishStore()
                    }
                }
                if self.rolloutReader.hasTrackedFiles {
                    self.handleRolloutSignals()
                }
                if self.store.purgeTerminalSubagents() {
                    self.publishStore()
                }
            }
        }
    }

    func installHooks() {
        do {
            let hooksURL = codexHooksURL
            let existing = try? Data(contentsOf: hooksURL)
            let mutation = try CodexHookInstaller.install(
                existingData: existing,
                command: hookExecutableURL.path
            )
            guard mutation.changed, let contents = mutation.contents else {
                refreshHookStatus()
                return
            }

            try FileManager.default.createDirectory(
                at: hooksURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if let existing {
                let backup = hooksURL
                    .deletingLastPathComponent()
                    .appendingPathComponent("hooks.json.agentgrid-backup-\(Int(Date().timeIntervalSince1970))")
                try existing.write(to: backup, options: .atomic)
            }
            try contents.write(to: hooksURL, options: .atomic)
            addEvent("Codex Hook 已安装")
            refreshHookStatus()
        } catch {
            lastError = "安装 Hook 失败：\(error.localizedDescription)"
        }
    }

    func uninstallHooks() {
        do {
            let existing = try? Data(contentsOf: codexHooksURL)
            let mutation = try CodexHookInstaller.uninstall(existingData: existing)
            guard mutation.changed else {
                refreshHookStatus()
                return
            }
            if let contents = mutation.contents {
                try contents.write(to: codexHooksURL, options: .atomic)
            } else if FileManager.default.fileExists(atPath: codexHooksURL.path) {
                try FileManager.default.removeItem(at: codexHooksURL)
            }
            addEvent("AgentGrid Hook 已移除")
            refreshHookStatus()
        } catch {
            lastError = "卸载 Hook 失败：\(error.localizedDescription)"
        }
    }

    func simulate(_ lifecycle: AgentLifecycle) {
        let now = Date()
        let task = TaskSnapshot(
            id: "agentgrid-simulator",
            source: .codexDesktop,
            projectName: "AgentGrid 模拟器",
            title: "AgentGrid · 像素任务列表联调",
            userPrompt: "检查任务行、逐像素 Bloom 和状态动效",
            latestStep: lifecycle == .running ? "apply_patch android/AgentGridScreen.kt" : nil,
            tokenUsage: TokenUsage(input: 12_480, cachedInput: 9_200, output: 2_180, total: 14_660),
            subagents: [
                SubagentSnapshot(
                    id: "simulator-protocol",
                    path: "/root/protocol_v2",
                    lifecycle: lifecycle == .interrupted ? .interrupted : .running,
                    activity: .editing,
                    latestStep: "apply_patch protocol/README.md",
                    tokenUsage: TokenUsage(input: 3_200, output: 680, total: 3_880),
                    startedAt: now.addingTimeInterval(-31),
                    updatedAt: now
                ),
                SubagentSnapshot(
                    id: "simulator-animation",
                    path: "/root/pixel_motion",
                    lifecycle: .succeeded,
                    activity: nil,
                    latestStep: "swift test PixelMotionTests",
                    tokenUsage: TokenUsage(input: 2_440, output: 390, total: 2_830),
                    startedAt: now.addingTimeInterval(-27),
                    updatedAt: now.addingTimeInterval(-4)
                ),
            ],
            lifecycle: lifecycle,
            activity: lifecycle == .running ? .editing : nil,
            startedAt: now.addingTimeInterval(-42),
            updatedAt: now,
            completedAt: [.succeeded, .interrupted].contains(lifecycle) ? now : nil,
            isUnread: lifecycle == .succeeded,
            capabilities: lifecycle == .waitingApproval ? [.approve, .deny] : []
        )
        store.upsert(task)
        addEvent("模拟状态：\(lifecycle.rawValue)")
        publishStore(focusedTaskIDOverride: task.id)
    }

    func clearError() {
        lastError = nil
    }

    private func handle(_ hook: CodexHookPayload) {
        rolloutReader.track(
            filePath: hook.transcriptPath,
            sessionID: hook.sessionID,
            cwd: hook.cwd
        )
        let existing = store.tasks.first { $0.id == hook.sessionID }
        let task = CodexEventReducer.task(from: hook, existing: existing)
        if hook.hookEventName == .permissionRequest {
            pendingRequests[hook.sessionID] = PendingRequest(
                taskID: hook.sessionID,
                kind: .approval,
                summary: hook.toolInput?.summary
            )
        } else if hook.hookEventName == .stop {
            pendingRequests.removeValue(forKey: hook.sessionID)
        }
        store.upsert(task)
        addEvent("\(task.projectName) · \(task.lifecycle.rawValue)")
        publishStore()
    }

    private func discoverRolloutSessions(now: Date = .now) {
        let sessionsRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
        rolloutReader.discoverSessions(
            in: sessionsRoot,
            modifiedAfter: now.addingTimeInterval(-10 * 60)
        )
    }

    private func handleRolloutSignals() {
        let signals = rolloutReader.poll()
        guard !signals.isEmpty else {
            return
        }

        for signal in signals {
            var task = store.tasks.first { $0.id == signal.sessionID }
                ?? TaskSnapshot(
                    id: signal.sessionID,
                    source: .codexCLI,
                    projectName: URL(fileURLWithPath: signal.cwd).lastPathComponent,
                    lifecycle: signal.lifecycle ?? .running,
                    startedAt: signal.timestamp,
                    updatedAt: signal.timestamp
                )
            if let subagentID = signal.subagentID {
                applySubagentSignal(
                    signal,
                    subagentID: subagentID,
                    to: &task
                )
                store.upsert(task)
                continue
            }
            if let lifecycle = signal.lifecycle {
                task.lifecycle = lifecycle
            }
            if let activity = signal.activity {
                task.activity = activity
            }
            if let prompt = signal.userPrompt {
                task.userPrompt = prompt
                if task.title == task.projectName {
                    task.title = CodexEventReducer.title(
                        projectName: task.projectName,
                        prompt: prompt
                    )
                }
            }
            if let latestStep = signal.latestStep {
                task.latestStep = latestStep
            }
            if let tokenUsage = signal.tokenUsage {
                task.tokenUsage = tokenUsage
            }
            task.updatedAt = signal.timestamp
            task.completedAt = task.isTerminal ? signal.timestamp : nil
            task.isUnread = task.isTerminal

            switch signal.requestKind {
            case .approval:
                pendingRequests[task.id] = PendingRequest(
                    taskID: task.id,
                    kind: .approval,
                    summary: signal.summary
                )
                // PermissionRequest Hook 到达后会补上真实的批准和拒绝能力。
                task.capabilities = task.capabilities.intersection([.approve, .deny])
            case .question:
                pendingRequests[task.id] = PendingRequest(
                    taskID: task.id,
                    kind: .question,
                    summary: signal.summary
                )
                task.capabilities = []
            case nil:
                if signal.lifecycle == .running {
                    pendingRequests.removeValue(forKey: task.id)
                    task.capabilities = []
                }
            }
            store.upsert(task)
        }
        publishStore()
    }

    private func applySubagentSignal(
        _ signal: CodexRolloutSignal,
        subagentID: String,
        to task: inout TaskSnapshot
    ) {
        let path = signal.subagentPath ?? task.subagents
            .first(where: { $0.id == subagentID })?
            .path
            ?? "/root/subagent"
        var subagent = task.subagents.first { $0.id == subagentID }
            ?? SubagentSnapshot(
                id: subagentID,
                path: path,
                lifecycle: signal.lifecycle ?? .running,
                activity: signal.activity ?? .thinking,
                startedAt: signal.timestamp,
                updatedAt: signal.timestamp
            )

        if subagent.path != path {
            subagent.path = path
            subagent.displayName = SubagentSnapshot.name(from: path)
        }
        if let lifecycle = signal.lifecycle {
            subagent.lifecycle = lifecycle
        }
        if let activity = signal.activity {
            subagent.activity = activity
        }
        if let latestStep = signal.latestStep {
            subagent.latestStep = latestStep
        }
        if let tokenUsage = signal.tokenUsage {
            subagent.tokenUsage = tokenUsage
        }
        subagent.updatedAt = signal.timestamp

        task.subagents.removeAll { $0.id == subagentID }
        task.subagents.append(subagent)
        task.subagents.sort {
            if $0.isTerminal != $1.isTerminal {
                return !$0.isTerminal
            }
            return $0.startedAt < $1.startedAt
        }
        task.updatedAt = max(task.updatedAt, signal.timestamp)
        if task.lifecycle == .running {
            task.activity = task.subagents.contains { !$0.isTerminal }
                ? .delegating
                : .thinking
        }
    }

    private func handleControl(_ text: String) {
        guard let data = text.data(using: .utf8),
              var request = try? JSONDecoder().decode(SignedControlEnvelope.self, from: data) else {
            return
        }

        do {
            try replayGuard.validate(request, secret: pairingSecret)
        } catch {
            sendAck(requestID: request.messageId, result: .rejected, reason: "签名或序号无效")
            return
        }

        guard let index = store.tasks.firstIndex(where: { $0.id == request.payload.taskID }) else {
            sendAck(requestID: request.messageId, result: .stale, reason: "任务已结束或不存在")
            return
        }

        var task = store.tasks[index]
        switch request.payload.action {
        case .approve:
            guard task.capabilities.contains(.approve) else {
                sendAck(requestID: request.messageId, result: .unsupported, reason: "当前任务不能批准")
                return
            }
            hookServer?.resolve(sessionID: task.id, decision: .allow)
            pendingRequests.removeValue(forKey: task.id)
            task.lifecycle = .running
            task.activity = .thinking
            task.capabilities = []
        case .deny:
            guard task.capabilities.contains(.deny) else {
                sendAck(requestID: request.messageId, result: .unsupported, reason: "当前任务不能拒绝")
                return
            }
            hookServer?.resolve(sessionID: task.id, decision: .deny)
            pendingRequests.removeValue(forKey: task.id)
            task.lifecycle = .interrupted
            task.activity = nil
            task.completedAt = .now
            task.isUnread = true
            task.capabilities = []
        case .mute:
            task.isMuted.toggle()
        case .markRead:
            task.isUnread = false
        case .pin:
            task.isPinned.toggle()
        case .answer, .interrupt, .retry:
            sendAck(
                requestID: request.messageId,
                result: .unsupported,
                reason: "当前 Codex 通道暂未提供稳定能力"
            )
            return
        }

        request.signature = ""
        store.upsert(task)
        publishStore()
        sendAck(requestID: request.messageId, result: .accepted)
    }

    private func sendAck(requestID: UUID, result: ControlResult, reason: String? = nil) {
        let envelope = MessageEnvelope(
            type: "control.ack",
            payload: ControlAckPayload(requestID: requestID, result: result, reason: reason)
        )
        guard let text = encode(envelope) else { return }
        webSocketServer?.broadcast(text)
    }

    private func refreshUsage() {
        usage = CodexUsageLoader.load()
        broadcastSnapshot()
    }

    private func refreshHookStatus() {
        hookInstalled = CodexHookInstaller.isInstalled(
            data: try? Data(contentsOf: codexHooksURL)
        )
    }

    private func publishStore(focusedTaskIDOverride: String? = nil) {
        _ = refreshCodexTitles()
        tasks = store.tasks.sorted { $0.updatedAt > $1.updatedAt }
        focusedTaskID = focusedTaskIDOverride ?? store.focusedTask()?.id
        do {
            try persistence.save(tasks)
        } catch {
            lastError = "保存临时任务状态失败：\(error.localizedDescription)"
        }
        broadcastSnapshot()
    }

    private func refreshCodexTitles() -> Bool {
        guard sessionTitleSynchronizer.needsRefresh(for: store.tasks) else {
            return false
        }
        return sessionTitleSynchronizer.applyAvailableTitles(
            sessionTitleReader.loadTitles(),
            to: &store
        )
    }

    private func broadcastSnapshot() {
        let payload = StateSnapshotPayload(
            tasks: tasks,
            usage: usage,
            focusedTaskID: focusedTaskID,
            pendingRequests: Array(pendingRequests.values)
        )
        let envelope = MessageEnvelope(type: "state.snapshot", payload: payload)
        guard let text = encode(envelope) else { return }
        webSocketServer?.broadcast(text)
    }

    private func encode<T: Codable & Sendable>(_ value: T) -> String? {
        guard let data = try? ProtocolCodec.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func addEvent(_ text: String) {
        recentEvents.insert(text, at: 0)
        recentEvents = Array(recentEvents.prefix(20))
    }

    private var codexHooksURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/hooks.json")
    }

    private var hookExecutableURL: URL {
        let sibling = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/AgentGridHooks")
        if FileManager.default.isExecutableFile(atPath: sibling.path) {
            return sibling
        }

        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent()
            .appendingPathComponent("AgentGridHooks")
        return executable
    }
}
