import AgentGridCore
import Foundation
import Observation

protocol GLMQuotaCoordinating: Sendable {
    func start() async
    func refresh() async
    func waitUntilIdle() async
    func saveCandidate(_ candidate: String) async -> Bool
    func deleteKey() async -> Bool
}

extension GLMQuotaCoordinator: GLMQuotaCoordinating {}

@MainActor
@Observable
final class BridgeModel {
    private(set) var tasks: [TaskSnapshot] = []
    private(set) var usage: UsageSnapshot?
    private(set) var focusedTaskID: String?
    private(set) var phoneCount = 0
    private(set) var serviceStatus = "正在启动"
    private(set) var hookInstalled = false
    private(set) var claudeHookInstalled = false
    private(set) var zcodeHookInstalled = false
    private(set) var zcodeHookManaged = false
    private(set) var glmCredentialStatus = GLMCredentialStatus.unconfigured
    private(set) var glmValidationStatus = GLMValidationStatus.idle
    private(set) var glmProvider: UsageProviderSnapshot?
    private(set) var glmOperationInProgress = false
    private(set) var pendingZCodeRestorePlan: ZCodeHookRestorePlan?
    private(set) var lastError: String?
    private(set) var pairingText = ""
    private(set) var recentEvents: [String] = []

    private var catalog = PersistentTaskCatalog()
    private var controlAuthorizer = SignedTaskControlAuthorizer()
    private var pairingSecret = Data()
    private let hookConfiguration = CodexHookConfiguration()
    private let claudeHookConfiguration = ClaudeHookConfiguration()
    private let zcodeHookConfiguration = ZCodeHookConfiguration()
    private let usageLoader = CodexUsageLoader()
    @ObservationIgnored
    private let glmCoordinatorFactory: @MainActor @Sendable (
        @escaping @Sendable (GLMQuotaState) async -> Void
    ) -> any GLMQuotaCoordinating
    @ObservationIgnored
    private let snapshotObserver: (@MainActor @Sendable (String) -> Void)?
    @ObservationIgnored
    private lazy var glmQuotaCoordinator = glmCoordinatorFactory { [weak self] state in
        await MainActor.run {
            self?.applyGLMState(state)
        }
    }
    private var rolloutObservation = CodexRolloutObservation()
    private var hookServer: HookBridgeServer?
    private var webSocketServer: WebSocketServer?
    private var refreshTask: Task<Void, Never>?
    private var usageLoadTask: Task<Void, Never>?
    private var rolloutTask: Task<Void, Never>?
    private var hasStarted = false

    init(
        glmCoordinatorFactory: @escaping @MainActor @Sendable (
            @escaping @Sendable (GLMQuotaState) async -> Void
        ) -> any GLMQuotaCoordinating = { stateHandler in
            GLMQuotaCoordinator(
                keyStore: GLMKeychainStore(),
                quotaFetcher: GLMQuotaProvider(),
                onStateChange: stateHandler
            )
        },
        snapshotObserver: (@MainActor @Sendable (String) -> Void)? = nil
    ) {
        self.glmCoordinatorFactory = glmCoordinatorFactory
        self.snapshotObserver = snapshotObserver
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        reconcileRestoredTasks()
        publishCatalog()

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

            let hookServer = HookBridgeServer(
                eventHandler: { [weak self] envelope in
                    Task { @MainActor in
                        self?.handle(envelope)
                    }
                },
                zcodeStateHandler: { [weak self] requestID, state in
                    Task { @MainActor in
                        self?.handleZCodePermissionState(requestID, state: state)
                    }
                }
            )
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
                        self?.updatePhoneCount(count)
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
        refreshClaudeHookStatus()
        refreshZCodeHookStatus()
        refreshUsage()
        startGLMQuotaMonitoring()
        handleRolloutObservation()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(600))
                guard let self else { return }
                self.refreshUsage()
                if let commit = self.catalog.maintain() {
                    self.applyCatalogCommit(commit)
                }
            }
        }
        rolloutTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(750))
                guard let self else { return }
                self.handleRolloutObservation()
                if let commit = self.catalog.maintain() {
                    self.applyCatalogCommit(commit)
                }
            }
        }
    }

    func installHooks() {
        do {
            let change = try hookConfiguration.install(
                command: hookExecutableURL.path
            )
            if change.changed {
                addEvent("Codex Hook 已安装")
            }
            refreshHookStatus()
        } catch {
            lastError = "安装 Hook 失败：\(error.localizedDescription)"
        }
    }

    func uninstallHooks() {
        do {
            let change = try hookConfiguration.uninstall()
            if change.changed {
                addEvent("AgentPager Codex Hook 已移除")
            }
            refreshHookStatus()
        } catch {
            lastError = "卸载 Hook 失败：\(error.localizedDescription)"
        }
    }

    func installClaudeHooks() {
        do {
            let command = ClaudeHookInstaller.hookCommand(for: hookExecutableURL.path)
            let change = try claudeHookConfiguration.install(command: command)
            if change.changed {
                addEvent("Claude Code Hook 已安装")
            }
            refreshClaudeHookStatus()
        } catch {
            lastError = "安装 Claude Code Hook 失败：\(error.localizedDescription)"
        }
    }

    func uninstallClaudeHooks() {
        do {
            let change = try claudeHookConfiguration.uninstall()
            if change.changed {
                addEvent("AgentPager Claude Code Hook 已移除")
            }
            refreshClaudeHookStatus()
        } catch {
            lastError = "卸载 Claude Code Hook 失败：\(error.localizedDescription)"
        }
    }

    func installZCodeHooks() {
        do {
            let change = try zcodeHookConfiguration.install(
                command: hookExecutableURL.path
            )
            switch change.status {
            case .installed:
                addEvent("ZCode Hook 已安装 · 备份已创建")
            case .repaired:
                addEvent("ZCode Hook 已修复 · 备份已创建")
            case .unchanged:
                addEvent("ZCode Hook 已是最新配置 · 无需备份")
            case .uninstalled, .alreadyUninstalled,
                 .restoreConfirmationRequired, .restored, .noBackup:
                break
            }
            pendingZCodeRestorePlan = nil
            lastError = nil
            refreshZCodeHookStatus()
        } catch {
            lastError = "安装 ZCode Hook 失败：\(error.localizedDescription)"
        }
    }

    func uninstallZCodeHooks() {
        do {
            let change = try zcodeHookConfiguration.uninstall()
            switch change.status {
            case .uninstalled:
                addEvent("ZCode Hook 已卸载 · 备份已创建")
            case .alreadyUninstalled:
                addEvent("ZCode Hook 已处于卸载状态 · 无需备份")
            case .installed, .repaired, .unchanged,
                 .restoreConfirmationRequired, .restored, .noBackup:
                break
            }
            pendingZCodeRestorePlan = nil
            lastError = nil
            refreshZCodeHookStatus()
        } catch {
            lastError = "卸载 ZCode Hook 失败：\(error.localizedDescription)"
        }
    }

    func prepareZCodeHookRestore() {
        do {
            let change = try zcodeHookConfiguration.prepareRestoreLatestBackup()
            pendingZCodeRestorePlan = change.restorePlan
            if change.status == .restoreConfirmationRequired {
                addEvent("ZCode Hook 恢复待确认 · 当前配置尚未改动")
            } else {
                addEvent("ZCode Hook 没有可恢复备份")
            }
            lastError = nil
        } catch {
            lastError = "检查 ZCode Hook 备份失败：\(error.localizedDescription)"
        }
    }

    func confirmZCodeHookRestore() {
        guard let pendingZCodeRestorePlan else { return }
        do {
            let change = try zcodeHookConfiguration.restoreLatestBackup(
                using: pendingZCodeRestorePlan
            )
            if change.status == .restored {
                addEvent("ZCode Hook 最近备份已恢复 · 恢复前配置已另行备份")
            } else {
                addEvent("ZCode Hook 当前配置与备份一致 · 无需恢复")
            }
            self.pendingZCodeRestorePlan = nil
            lastError = nil
            refreshZCodeHookStatus()
        } catch {
            self.pendingZCodeRestorePlan = nil
            lastError = "恢复 ZCode Hook 失败：\(error.localizedDescription)"
        }
    }

    func cancelZCodeHookRestore() {
        pendingZCodeRestorePlan = nil
        addEvent("ZCode Hook 恢复已取消 · 配置未改动")
    }

    func simulate(_ lifecycle: AgentLifecycle) {
        let now = Date()
        let task = TaskSnapshot(
            id: "agentgrid-simulator",
            source: .codexDesktop,
            projectName: "AgentPager 模拟器",
            title: "AgentPager · 像素任务列表联调",
            userPrompt: "检查任务行、逐像素 Bloom 和状态动效",
            latestStep: lifecycle == .running ? "apply_patch android/AgentPagerScreen.kt" : nil,
            tokenUsage: TokenUsage(input: 12_480, cachedInput: 9_200, output: 2_180, total: 14_660),
            subagents: [
                SubagentSnapshot(
                    id: "simulator-protocol",
                    path: "/root/protocol_v2",
                    lifecycle: lifecycle == .interrupted ? .interrupted : .running,
                    activity: .editing,
                    latestStep: "apply_patch protocol/fixtures/task-snapshot.json",
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
        let commit = catalog.accept(
            .synthetic(task),
            focusedTaskIDOverride: task.id
        )
        addEvent("模拟状态：\(lifecycle.rawValue)")
        if let commit {
            applyCatalogCommit(commit)
        }
    }

    func clearError() {
        lastError = nil
    }

    func saveGLMKey(_ candidate: String) {
        guard !glmOperationInProgress else { return }
        glmOperationInProgress = true
        Task { [weak self] in
            guard let self else { return }
            _ = await self.glmQuotaCoordinator.saveCandidate(candidate)
            self.glmOperationInProgress = false
        }
    }

    func startGLMQuotaMonitoring() {
        Task {
            await glmQuotaCoordinator.start()
        }
    }

    func updatePhoneCount(_ count: Int) {
        let phoneConnected = count > phoneCount
        phoneCount = count
        hookServer?.setPhoneConnected(count > 0)
        if phoneConnected {
            refreshUsage()
            Task {
                await glmQuotaCoordinator.refresh()
            }
        } else {
            broadcastSnapshot()
        }
    }

    func refreshGLMQuota() {
        guard !glmOperationInProgress else { return }
        glmOperationInProgress = true
        Task { [weak self] in
            guard let self else { return }
            await self.glmQuotaCoordinator.refresh()
            await self.glmQuotaCoordinator.waitUntilIdle()
            self.glmOperationInProgress = false
        }
    }

    func deleteGLMKey() {
        guard !glmOperationInProgress else { return }
        glmOperationInProgress = true
        Task { [weak self] in
            guard let self else { return }
            _ = await self.glmQuotaCoordinator.deleteKey()
            self.glmOperationInProgress = false
        }
    }

    var glmStatusText: String {
        switch glmValidationStatus {
        case .succeeded:
            "验证成功"
        case .failed:
            "验证失败"
        case .idle:
            glmCredentialStatus == .configured ? "已配置" : "未配置"
        }
    }

    private func handle(_ envelope: HookEnvelope) {
        let commit: TaskCatalogCommit?
        let diagnosticSummary: String
        let lifecycleSummary: String
        switch envelope {
        case let .codex(hook):
            rolloutObservation.include(hook)
            commit = catalog.accept(.hook(hook))
            let task = catalog.projection().tasks.first { $0.id == hook.sessionID }
            diagnosticSummary = task?.projectName ?? "Codex"
            lifecycleSummary = task?.lifecycle.rawValue ?? ""
        case let .claude(hook):
            commit = catalog.accept(.claudeHook(hook))
            let task = catalog.projection().tasks.first { $0.id == hook.sessionID }
            diagnosticSummary = task?.projectName ?? "Claude Code"
            lifecycleSummary = task?.lifecycle.rawValue ?? ""
        case let .zcode(hook, permissionState):
            commit = catalog.accept(
                .zcodeHook(
                    hook,
                    permissionState: permissionState
                )
            )
            let task = catalog.projection().tasks.first { $0.id == hook.sessionID }
            let lifecycle = task?.lifecycle ?? .idle
            diagnosticSummary = ZCodeDiagnosticEvent(
                hook: hook,
                lifecycle: lifecycle
            ).summary
            lifecycleSummary = ""
        }
        let eventSummary = lifecycleSummary.isEmpty
            ? diagnosticSummary
            : "\(diagnosticSummary) · \(lifecycleSummary)"
        addEvent(eventSummary)
        if let commit {
            applyCatalogCommit(commit)
        }
    }

    private func handleZCodePermissionState(
        _ requestID: String,
        state: ZCodePermissionRequestState
    ) {
        guard state != .pending,
              let commit = catalog.completeZCodePermissionRequest(
                  requestID,
                  state: state
              ) else {
            return
        }
        applyCatalogCommit(commit)
    }

    private func handleRolloutObservation() {
        let signals = rolloutObservation.observe()
        guard !signals.isEmpty else {
            return
        }

        if let commit = catalog.accept(.rollout(signals)) {
            applyCatalogCommit(commit)
        }
    }

    private func reconcileRestoredTasks() {
        let reconciliation = rolloutObservation.reconcile(
            sessionStartDates: catalog.restoredActiveTaskStartDates
        )
        if !reconciliation.signals.isEmpty {
            _ = catalog.accept(.rollout(reconciliation.signals))
        }
        _ = catalog.reconcileRestoredActiveTasks(
            verifiedActiveTaskIDs: reconciliation.activeSessionIDs
        )
    }

    private func handleControl(_ text: String) {
        guard let data = text.data(using: .utf8),
              let request = try? JSONDecoder().decode(SignedControlEnvelope.self, from: data) else {
            return
        }

        let control: AuthorizedTaskControl
        do {
            control = try controlAuthorizer.authorize(
                request,
                secret: pairingSecret
            )
        } catch {
            sendAck(requestID: request.messageId, result: .rejected, reason: "签名或序号无效")
            return
        }

        guard let hookServer else {
            sendAck(
                requestID: request.messageId,
                result: .rejected,
                reason: "Hook 通道尚未就绪"
            )
            return
        }
        let result = catalog.perform(
            control,
            permissionResolver: hookServer
        )
        if let commit = result.commit {
            applyCatalogCommit(commit)
        }
        sendAck(
            requestID: result.receipt.requestID,
            result: result.receipt.result,
            reason: result.receipt.reason
        )
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
        guard usageLoadTask == nil else { return }
        let usageLoader = usageLoader
        usageLoadTask = Task { [weak self] in
            let snapshot = await Task.detached(priority: .utility) {
                usageLoader.load()
            }.value
            guard let self else { return }
            self.usage = snapshot
            self.usageLoadTask = nil
            self.broadcastSnapshot()
        }
    }

    private func refreshHookStatus() {
        hookInstalled = hookConfiguration.isInstalled()
    }

    private func refreshClaudeHookStatus() {
        claudeHookInstalled = claudeHookConfiguration.isInstalled()
    }

    private func refreshZCodeHookStatus() {
        zcodeHookInstalled = zcodeHookConfiguration.isInstalled(
            command: hookExecutableURL.path
        )
        zcodeHookManaged = zcodeHookConfiguration.containsManagedHooks()
    }

    private func applyGLMState(_ state: GLMQuotaState) {
        glmCredentialStatus = state.credentialStatus
        glmValidationStatus = state.validationStatus
        glmProvider = state.provider
        switch state.validationStatus {
        case .succeeded:
            addEvent("GLM 额度已刷新")
        case .failed:
            addEvent("GLM 额度验证失败")
        case .idle:
            break
        }
        broadcastSnapshot()
    }

    private func publishCatalog(focusedTaskIDOverride: String? = nil) {
        applyCatalogCommit(
            catalog.synchronize(
                focusedTaskIDOverride: focusedTaskIDOverride
            )
        )
    }

    private func applyCatalogCommit(_ commit: TaskCatalogCommit) {
        tasks = commit.projection.tasks
        focusedTaskID = commit.projection.focusedTaskID
        if let persistenceError = commit.persistenceError {
            lastError = persistenceError
        }
        broadcastSnapshot()
    }

    private func broadcastSnapshot() {
        let payload = StateSnapshotPayload(
            tasks: tasks,
            usage: usage,
            usageProviders: glmProvider.map { [$0] },
            focusedTaskID: focusedTaskID,
            pendingRequests: catalog.projection().pendingRequests
        )
        let envelope = MessageEnvelope(type: "state.snapshot", payload: payload)
        guard let text = encode(envelope) else { return }
        snapshotObserver?(text)
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

    private var hookExecutableURL: URL {
        let executableDirectory = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS")
        let currentSibling = executableDirectory
            .appendingPathComponent("AgentPagerHooks")
        if FileManager.default.isExecutableFile(atPath: currentSibling.path) {
            return currentSibling
        }
        let legacySibling = executableDirectory
            .appendingPathComponent("AgentGridHooks")
        if FileManager.default.isExecutableFile(atPath: legacySibling.path) {
            return legacySibling
        }

        let commandDirectory = URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent()
        let currentExecutable = commandDirectory
            .appendingPathComponent("AgentPagerHooks")
        if FileManager.default.isExecutableFile(atPath: currentExecutable.path) {
            return currentExecutable
        }
        return commandDirectory.appendingPathComponent("AgentGridHooks")
    }
}
