import AgentGridCore
import SwiftUI

struct BridgeMenuView: View {
    let model: BridgeModel

    private var focusedTask: TaskSnapshot? {
        model.tasks.first { $0.id == model.focusedTaskID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                PixelCoreView(
                    lifecycle: focusedTask?.lifecycle ?? .idle,
                    activity: focusedTask?.activity,
                    changedAt: focusedTask?.updatedAt ?? .now
                )
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 5) {
                    Text(focusedTask?.title ?? "AGENTGRID BRIDGE")
                        .font(.pixel(15, weight: .bold))
                        .foregroundStyle(PixelTheme.text)
                        .lineLimit(1)
                    Text(statusText)
                        .font(.pixel(11))
                        .foregroundStyle(statusColor)
                    Text(connectionSummary)
                        .font(.pixel(10))
                        .foregroundStyle(PixelTheme.muted)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 7) {
                StatusCell(
                    label: "HOOK",
                    value: model.hookInstalled ? "READY" : "OFF",
                    active: model.hookInstalled
                )
                StatusCell(
                    label: "LINK",
                    value: model.phoneCount > 0 ? "LIVE" : "WAIT",
                    active: model.phoneCount > 0
                )
                StatusCell(
                    label: "TASK",
                    value: "\(model.tasks.count)",
                    active: !model.tasks.isEmpty
                )
            }

            PixelDivider()

            Button(model.hookInstalled ? "修复 CODEX HOOK" : "安装 CODEX HOOK") {
                model.installHooks()
            }
            .buttonStyle(PixelButtonStyle(accent: PixelTheme.cyan))

            SettingsLink {
                Text("打开 AGENTGRID 设置")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(PixelButtonStyle(accent: PixelTheme.violet))

            PixelDivider()

            Button("退出 AGENTGRID") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(PixelButtonStyle(accent: PixelTheme.muted))
        }
        .padding(17)
        .frame(width: 330)
        .background(PixelTheme.background)
        .preferredColorScheme(.dark)
        .font(.pixel(12))
    }

    private var statusText: String {
        guard let task = focusedTask else { return model.serviceStatus }
        let activity = task.activity.map(activityText) ?? "等待"
        return "\(lifecycleText(task.lifecycle)) · \(activity)"
    }

    private var statusColor: Color {
        guard let task = focusedTask else { return PixelTheme.cyan }
        return Color(pixelHex: PixelPalette.hex(
            lifecycle: task.lifecycle,
            activity: task.activity
        ))
    }

    private var connectionSummary: String {
        let subagentCount = focusedTask?.subagents.count ?? 0
        guard subagentCount > 0 else {
            return "\(model.phoneCount) 台手机连接"
        }
        return "\(model.phoneCount) 台手机 · \(subagentCount) 个子代理"
    }
}

struct BridgeSettingsView: View {
    private enum Tab: String, CaseIterable {
        case pairing = "连接"
        case hook = "Codex"
        case simulator = "模拟器"
        case diagnostics = "诊断"
    }

    let model: BridgeModel
    @State private var selection: Tab = .pairing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) {
                            selection = tab
                        }
                    } label: {
                        VStack(spacing: 8) {
                            Text(tab.rawValue.uppercased())
                                .font(.pixel(12, weight: .bold))
                                .foregroundStyle(
                                    selection == tab ? PixelTheme.text : PixelTheme.muted
                                )
                            Rectangle()
                                .fill(selection == tab ? PixelTheme.cyan : .clear)
                                .frame(height: 2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(PixelTheme.surface)

            ZStack {
                switch selection {
                case .pairing:
                    pairingView.transition(.opacity)
                case .hook:
                    hookView.transition(.opacity)
                case .simulator:
                    simulatorView.transition(.opacity)
                case .diagnostics:
                    diagnosticsView.transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 650, minHeight: 480)
        .background(PixelTheme.background)
        .foregroundStyle(PixelTheme.text)
        .font(.pixel(12))
        .preferredColorScheme(.dark)
    }

    private var pairingView: some View {
        HStack(spacing: 34) {
            QRCodeView(text: model.pairingText)
                .padding(14)
                .background(.white)
                .frame(width: 258, height: 258)
                .accessibilityLabel("AgentGrid 手机配对二维码")

            VStack(alignment: .leading, spacing: 14) {
                SettingsTitle("扫描配对")
                Text("用 Android AgentGrid 扫描左侧二维码")
                    .foregroundStyle(PixelTheme.muted)
                PixelDivider()
                InfoRow(label: "PHONE", value: "\(model.phoneCount)")
                InfoRow(label: "SERVICE", value: model.serviceStatus)
                InfoRow(
                    label: "LINK",
                    value: model.phoneCount > 0 ? "CONNECTED" : "WAITING",
                    accent: model.phoneCount > 0 ? PixelTheme.green : PixelTheme.amber
                )
            }
            .frame(maxWidth: 270, alignment: .leading)
        }
        .padding(30)
    }

    private var hookView: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsTitle("Codex 生命周期 Hook")
            PixelPanel {
                VStack(alignment: .leading, spacing: 13) {
                    InfoRow(
                        label: "STATUS",
                        value: model.hookInstalled ? "已安装" : "未安装",
                        accent: model.hookInstalled ? PixelTheme.green : PixelTheme.amber
                    )
                    Text("实时采集开始、工具、批准、完成和 Token；安装会保留现有 Hook，并在改写前备份。")
                        .foregroundStyle(PixelTheme.muted)
                        .lineSpacing(4)
                    HStack(spacing: 10) {
                        Button("安装或修复") { model.installHooks() }
                            .buttonStyle(PixelButtonStyle(accent: PixelTheme.cyan))
                        Button("卸载") { model.uninstallHooks() }
                            .buttonStyle(PixelButtonStyle(accent: PixelTheme.red))
                            .disabled(!model.hookInstalled)
                    }
                }
            }
            Text("Bridge 不在线时 Hook 自动放行，不会阻塞 Codex。")
                .font(.pixel(10))
                .foregroundStyle(PixelTheme.muted)
            Spacer()
        }
        .padding(28)
    }

    private var simulatorView: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    SettingsTitle("状态模拟器")
                    Text("检查手机任务行、逐像素 Bloom、声音与优先级")
                        .foregroundStyle(PixelTheme.muted)
                }
                Spacer()
                if let focused = model.tasks.first(where: { $0.id == model.focusedTaskID }) {
                    PixelCoreView(
                        lifecycle: focused.lifecycle,
                        activity: focused.activity,
                        changedAt: focused.updatedAt
                    )
                    .frame(width: 72, height: 72)
                }
            }

            LazyVGrid(
                columns: [.init(.adaptive(minimum: 135), spacing: 10)],
                spacing: 10
            ) {
                ForEach(AgentLifecycle.allCases, id: \.self) { lifecycle in
                    Button(lifecycleText(lifecycle)) {
                        model.simulate(lifecycle)
                    }
                    .buttonStyle(PixelButtonStyle(
                        accent: Color(pixelHex: PixelPalette.hex(
                            lifecycle: lifecycle,
                            activity: lifecycle == .running ? .editing : nil
                        ))
                    ))
                }
            }
            Spacer()
        }
        .padding(28)
    }

    private var diagnosticsView: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsTitle("运行诊断")
            HStack(spacing: 10) {
                StatusCell(label: "SERVICE", value: model.serviceStatus, active: true)
                StatusCell(label: "PHONE", value: "\(model.phoneCount)", active: model.phoneCount > 0)
                StatusCell(label: "TASK", value: "\(model.tasks.count)", active: !model.tasks.isEmpty)
            }
            Text("近期事件")
                .font(.pixel(12, weight: .bold))
                .foregroundStyle(PixelTheme.cyan)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.recentEvents.enumerated()), id: \.offset) { _, event in
                        Text(event)
                            .font(.pixel(11))
                            .foregroundStyle(PixelTheme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                        PixelDivider()
                    }
                }
            }
            .background(PixelTheme.surface)
            if let error = model.lastError {
                Text(error)
                    .font(.pixel(11))
                    .foregroundStyle(PixelTheme.red)
            }
        }
        .padding(28)
    }
}

private struct StatusCell: View {
    let label: String
    let value: String
    let active: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.pixel(9, weight: .bold))
                .foregroundStyle(PixelTheme.muted)
            Text(value)
                .font(.pixel(12, weight: .bold))
                .foregroundStyle(active ? PixelTheme.cyan : PixelTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(PixelTheme.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(active ? PixelTheme.cyan : PixelTheme.divider)
                .frame(height: 2)
        }
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    var accent = PixelTheme.text

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.pixel(9, weight: .bold))
                .foregroundStyle(PixelTheme.muted)
                .frame(width: 68, alignment: .leading)
            Text(value)
                .font(.pixel(12, weight: .bold))
                .foregroundStyle(accent)
                .lineLimit(2)
        }
    }
}

private struct SettingsTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.pixel(19, weight: .bold))
            .foregroundStyle(PixelTheme.text)
    }
}

private struct PixelPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PixelTheme.surface)
            .overlay {
                Rectangle().stroke(PixelTheme.divider, lineWidth: 1)
            }
    }
}

private struct PixelDivider: View {
    var body: some View {
        Rectangle()
            .fill(PixelTheme.divider)
            .frame(height: 1)
    }
}

private struct PixelButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.pixel(11, weight: .bold))
            .foregroundStyle(configuration.isPressed ? PixelTheme.background : accent)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(configuration.isPressed ? accent : PixelTheme.surface)
            .overlay {
                Rectangle().stroke(accent.opacity(0.72), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}

private func lifecycleText(_ lifecycle: AgentLifecycle) -> String {
    switch lifecycle {
    case .offline: "离线"
    case .idle: "空闲"
    case .starting: "正在启动"
    case .running: "正在运行"
    case .waitingApproval: "等待批准"
    case .waitingAnswer: "等待回答"
    case .succeeded: "任务完成"
    case .failed: "任务失败"
    case .interrupted: "已中断"
    }
}

private func activityText(_ activity: AgentActivity) -> String {
    switch activity {
    case .thinking: "思考"
    case .reading: "读取"
    case .searching: "搜索"
    case .editing: "编辑"
    case .executing: "执行"
    case .testing: "测试"
    case .browsing: "浏览"
    case .delegating: "委派"
    }
}
