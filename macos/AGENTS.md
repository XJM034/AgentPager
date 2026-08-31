# macOS 子项目说明

本目录是 AgentPager 的原生 macOS Bridge，使用 Swift、SwiftUI、Swift Package Manager 和 Network.framework。它负责菜单栏界面、Codex/Claude Code/ZCode Hook、本地任务状态、局域网配对与 WebSocket 通信，以及可选 GLM 额度查询。

## 构建事实

- Swift 工具版本下限：`6.2`，以 `Package.swift` 文件头为准。
- 最低系统：macOS 14，以 `Package.swift` 与 `AppInfo.plist` 为准。
- Swift Package 产品：`AgentGridCore`、`AgentGridBridge`、`AgentGridHooks`。
- App Bundle ID：`com.agentpager.bridge`。
- 本机当前 Xcode、Swift、SDK 与 Simulator 基线记录在 [../docs/updates/2026-08-25-macos-development-environment.md](../docs/updates/2026-08-25-macos-development-environment.md)；每次开发仍需从命令输出重新核实，不从旧记录推断。

## 修改边界

涉及 ZCode Hook、手机审批或 GLM 凭据、查询、刷新与降级时，先读 [现行功能与验收边界](../docs/zcode-glm-integration.md)。

- `Sources/AgentGridCore/`：任务模型、Hook、协议、配对、持久化、服务器及 GLM 额度适配与协调逻辑。
- `Sources/AgentGridBridge/`：菜单栏 App、运行协调、界面与视觉效果。
- `Sources/AgentGridHooks/`：Codex、Claude Code 与 ZCode 调用的 Hook 命令行入口。
- `Tests/AgentGridCoreTests/`：核心逻辑测试。
- `Tests/AgentGridBridgeTests/`：Bridge 生产接线与呈现状态测试。
- `AppInfo.plist`：Bundle、最低系统和本地网络声明。
- 打包入口位于仓库根目录的 `scripts/package-macos.sh` 与 `scripts/package-dmg.sh`。

协议、签名字段、配对或控制消息变化不是 macOS 单端改动；必须同时核对 `protocol/`、Android 和 Windows 实现。安装或卸载 Hook 必须保留用户已有配置，并保留可恢复备份。

## 环境与测试

先核实当前默认工具链：

```bash
xcode-select -p
xcodebuild -version
swift --version
xcrun --sdk macosx --show-sdk-version
xcodebuild -checkFirstLaunchStatus
```

不要把临时 Swift 工具链路径写成项目默认。只有在复现兼容性问题时才显式调用指定工具链，并在结果中说明。

逻辑修改至少运行：

```bash
cd macos
swift test
```

可按测试套件缩小反馈范围，例如：

```bash
swift test --filter CodexRolloutReaderTests
```

日志轮询、持久化、WebSocket 或长会话相关改动除单元测试外，还要观察真实进程的 CPU、内存和 macOS 诊断报告。

## 打包、签名与安装

从仓库根目录运行：

```bash
scripts/package-macos.sh
```

该命令默认生成当前架构的 `dist/AgentPager Bridge.app`；设置 `AGENTPAGER_UNIVERSAL=1` 才构建通用二进制。`scripts/package-dmg.sh` 生成 DMG。`AGENTPAGER_VERSION_NAME` 与 `AGENTPAGER_VERSION_CODE` 可覆盖本地包版本。

打包脚本会优先使用本机 Apple Development 身份，否则使用临时签名。它只更新 `dist/` 产物，不会自动替换 `/Applications/AgentPager Bridge.app`。若同一个 `dist` App 正在运行，脚本会先正常结束它并在打包后恢复运行。

安装本地定制版前必须：

1. 明确目标 App、版本、架构和签名身份。
2. 备份 `/Applications` 中的现有 App，并给备份标注版本与日期。
3. 正常退出旧进程，再复制新 App。
4. 使用 `codesign --verify --deep --strict` 核对签名，并比较安装前后的二进制哈希。
5. 启动后验证进程、端口、Hook、手机连接和关键功能。

未经用户明确要求，不配置 Developer ID 正式签名、不提交 Apple 公证、不发布 DMG，也不替换用户当前安装的 App。

## 运行验收

- Hook 监听端口：49361；配对与 WebSocket 入口：49362。
- Bridge 运行后可在仓库根目录执行 `node scripts/e2e-local.mjs`，验证合成任务的状态同步、反向审批、结束收敛和关闭帧存活。
- 端到端脚本不能证明菜单栏视觉、真实 Agent Hook、GLM 真实额度、局域网发现或 Redmi 实机连接；这些必须按改动范围现场验收。
- 当前安装的 iOS 27 模拟器属于本机 Apple 开发环境，但本仓库没有 iOS App 目标，不能替代 macOS Bridge 或 Android 真机验证。

## 守则状态与文档更新

- 普通分支目前没有自动 macOS CI；发布工作流只在手动触发或 Tag 推送时运行。
- Swift 单元测试不覆盖菜单栏 UI、签名/公证服务、真实 Hook 信任、局域网手机连接和长期性能。
- 稳定流程更新到 [../docs/macos-development.md](../docs/macos-development.md)；单次工具链、安装、故障或验收结果写入 `../docs/updates/YYYY-MM-DD-*.md`。
- 当 Package 结构、最低系统、Xcode/Swift 要求、Hook/协议、签名、公证、安装或验证流程变化时，重新运行 `$claude-agents-bootstrap`。
