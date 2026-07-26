import AgentGridCore
import SwiftUI

struct BridgeMenuView: View {
    let model: BridgeModel

    private var focusedTask: TaskSnapshot? {
        model.tasks.first { $0.id == model.focusedTaskID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                PixelCoreView(
                    lifecycle: focusedTask?.lifecycle ?? .idle,
                    activity: focusedTask?.activity,
                    compact: true
                )
                .frame(width: 62, height: 62)

                VStack(alignment: .leading, spacing: 5) {
                    Text(focusedTask?.projectName ?? "AGENTGRID")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(model.phoneCount) 台手机已连接")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                statusCell("HOOK", value: model.hookInstalled ? "READY" : "OFF")
                statusCell("LINK", value: model.phoneCount > 0 ? "LIVE" : "WAIT")
                statusCell("TASK", value: "\(model.tasks.count)")
            }

            Divider()

            if model.hookInstalled {
                Button("修复 Codex Hook") {
                    model.installHooks()
                }
            } else {
                Button("安装 Codex Hook") {
                    model.installHooks()
                }
            }

            SettingsLink {
                Label("AgentGrid 设置", systemImage: "slider.horizontal.3")
            }

            Divider()

            Button("退出 AgentGrid") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(18)
        .frame(width: 310)
        .background(Color(red: 0.035, green: 0.043, blue: 0.063))
        .preferredColorScheme(.dark)
    }

    private var statusText: String {
        guard let task = focusedTask else { return model.serviceStatus }
        return "\(task.lifecycle.rawValue) · \(task.activity?.rawValue ?? "等待")"
    }

    private func statusCell(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.monospacedDigit().weight(.bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(red: 0.065, green: 0.078, blue: 0.105))
        .clipShape(.rect(cornerRadius: 4))
    }
}

struct BridgeSettingsView: View {
    let model: BridgeModel

    var body: some View {
        TabView {
            pairingView
                .tabItem {
                    Label("连接", systemImage: "iphone.gen3.radiowaves.left.and.right")
                }
            hookView
                .tabItem {
                    Label("Codex", systemImage: "terminal")
                }
            simulatorView
                .tabItem {
                    Label("模拟器", systemImage: "square.grid.3x3.fill")
                }
            diagnosticsView
                .tabItem {
                    Label("诊断", systemImage: "stethoscope")
                }
        }
        .scenePadding()
        .frame(width: 560, height: 460)
        .preferredColorScheme(.dark)
    }

    private var pairingView: some View {
        VStack(spacing: 20) {
            QRCodeView(text: model.pairingText)
                .frame(width: 230, height: 230)
                .accessibilityLabel("AgentGrid 手机配对二维码")
            Text("在手机端扫描二维码")
                .font(.title3.weight(.semibold))
            Text("\(model.phoneCount) 台手机已连接 · \(model.serviceStatus)")
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }

    private var hookView: some View {
        Form {
            Section("Codex 生命周期 Hook") {
                LabeledContent("状态", value: model.hookInstalled ? "已安装" : "未安装")
                HStack {
                    Button("安装或修复") { model.installHooks() }
                        .buttonStyle(.borderedProminent)
                    Button("卸载") { model.uninstallHooks() }
                        .disabled(!model.hookInstalled)
                }
            }
            Section {
                Text("安装时会保留现有 Hook，并在改写前生成带时间戳的备份。Bridge 不在线时 Hook 自动放行。")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var simulatorView: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("状态模拟器")
                .font(.title2.weight(.bold))
            Text("无需启动 Codex 即可检查手机上的动画、声音和多任务排序。")
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [.init(.adaptive(minimum: 145))], spacing: 12) {
                ForEach(AgentLifecycle.allCases, id: \.self) { lifecycle in
                    Button(lifecycle.rawValue) {
                        model.simulate(lifecycle)
                    }
                    .buttonStyle(.bordered)
                }
            }
            Spacer()
        }
        .padding(24)
    }

    private var diagnosticsView: some View {
        VStack(alignment: .leading, spacing: 14) {
            LabeledContent("服务", value: model.serviceStatus)
            LabeledContent("手机", value: "\(model.phoneCount)")
            LabeledContent("任务", value: "\(model.tasks.count)")
            Divider()
            Text("近期事件")
                .font(.headline)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(model.recentEvents.enumerated()), id: \.offset) { _, event in
                        Text(event)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            if let error = model.lastError {
                Text(error)
                    .foregroundStyle(Color(red: 1.0, green: 0.38, blue: 0.44))
            }
        }
        .padding(24)
    }
}
