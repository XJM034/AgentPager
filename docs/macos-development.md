# macOS AgentPager Bridge 开发环境

本文说明如何在本仓库维护 macOS AgentPager Bridge，并区分 Swift 逻辑测试、本地 App 打包、安装替换、真实 Hook 与手机端验收。当前机器的日期化工具链证据见 [2026-08-25 macOS 开发环境更新](updates/2026-08-25-macos-development-environment.md)。

处理 ZCode 会话、手机审批或 GLM 额度时，先读 [现行功能与验收边界](zcode-glm-integration.md)，按其中的实现与测试入口定位；本文维护构建、安装及运行流程。

## 项目结构

macOS 端是一个 Swift Package，而不是独立的 `.xcodeproj`：

| 位置 | 作用 |
| --- | --- |
| `macos/Package.swift` | Swift 工具版本、最低系统、产品与 Target 的事实来源 |
| `macos/Sources/AgentGridCore/` | Hook、任务状态、协议、配对、持久化、本地服务器和 GLM 额度适配与协调 |
| `macos/Sources/AgentGridBridge/` | SwiftUI 菜单栏 App、界面和运行协调 |
| `macos/Sources/AgentGridHooks/` | Codex/Claude Code/ZCode 调用的 Hook 命令行程序 |
| `macos/Tests/AgentGridCoreTests/` | 核心逻辑测试 |
| `macos/Tests/AgentGridBridgeTests/` | Bridge 生产接线与呈现状态测试 |
| `macos/AppInfo.plist` | App Bundle、最低系统、本地网络权限和图标声明 |
| `scripts/package-macos.sh` | 构建并签名本地 App |
| `scripts/package-dmg.sh` | 在本地 App 基础上生成 DMG |

当前 Package 声明 Swift tools 6.2、最低 macOS 14，包含 `AgentGridCore`、`AgentGridBridge` 和 `AgentGridHooks` 三个产品，以及 `AgentGridCoreTests`、`AgentGridBridgeTests` 两个测试 Target。以后如代码或清单发生变化，以 `Package.swift` 和实际命令输出为准。

## 1. 每次开发先核实工具链

```bash
xcode-select -p
xcodebuild -version
swift --version
xcrun --sdk macosx --show-sdk-path
xcrun --sdk macosx --show-sdk-version
xcodebuild -checkFirstLaunchStatus
```

`xcode-select` 决定普通 `swift`、`xcrun` 和 `xcodebuild` 默认使用哪个 Xcode。Xcode beta 与 Swift beta 会继续变化，因此稳定文档只保存核实命令，具体版本写入 `docs/updates/`。

本机仍保留 Swift.org 用户级 Swift 6.2.4 工具链作为显式兼容性工具，但当前默认命令来自 `Xcode-beta.app`。只有需要复现工具链差异时才直接调用用户级工具链路径，不能把它混写成系统默认。

## 2. 逻辑开发与测试

完整 Swift 测试：

```bash
cd macos
swift test
```

只运行相关套件：

```bash
cd macos
swift test --filter CodexRolloutReaderTests
```

提交结论时同时记录实际 Swift 版本、测试数和失败数。测试通过只证明 Swift 核心逻辑，不能证明菜单栏 UI、真实 Hook 信任、手机连接或长时间资源占用。

## 3. 本地 App 与 DMG

从仓库根目录构建当前机器架构的 App：

```bash
scripts/package-macos.sh
```

构建通用二进制：

```bash
AGENTPAGER_UNIVERSAL=1 scripts/package-macos.sh
```

生成 DMG：

```bash
scripts/package-dmg.sh
```

本地覆盖版本号：

```bash
AGENTPAGER_VERSION_NAME=0.3.0 \
AGENTPAGER_VERSION_CODE=5 \
scripts/package-macos.sh
```

产物位于 `dist/`，已被 Git 忽略。签名选择顺序如下：

1. 显式 `AGENTPAGER_CODESIGN_IDENTITY`（兼容旧名 `AGENTGRID_CODESIGN_IDENTITY`）。
2. 本机 `~/Library/Application Support/AgentPager/signing-identity.sha1` 中固定的证书 SHA-1 标识。
3. 本机 Apple Development 身份。
4. 没有身份时使用临时签名；显式 `-` 也属于临时签名，不得报告为稳定签名。

固定标识文件只保存 40 位十六进制证书指纹，不保存私钥，且不进入仓库。配置无效或所选身份无法签名时停止，不静默降级。脚本不创建证书、不导入私钥、不写系统信任，也不自动创建该配置文件；首次启用需要用户批准。

保持同一 Bundle ID 和签名身份，通常可沿用钥匙串的应用授权；临时签名的代码指纹会随构建变化，不能保证跨版本复用。本地自签证书、Apple Development 都不等于 Developer ID 正式分发签名或 Apple 公证，不适用于对外发布结论。签名身份变更必须重新验收配对与 GLM 读取权限。

打包完成后至少检查：

```bash
codesign --verify --deep --strict "dist/AgentPager Bridge.app"
file "dist/AgentPager Bridge.app/Contents/MacOS/AgentPagerBridge"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "dist/AgentPager Bridge.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  "dist/AgentPager Bridge.app/Contents/Info.plist"
```

## 4. 安装与回滚

`scripts/package-macos.sh` 不会安装 App。替换 `/Applications/AgentPager Bridge.app` 是独立操作，必须先取得用户对目标版本的确认，再执行：

1. 核实当前运行路径、版本、Build、签名和目标架构。
2. 正常退出旧 Bridge。
3. 把旧 App 复制到带版本与日期的备份目录。
4. 安装新 App 后再次验证签名，并比较构建产物与已安装二进制的 SHA-256。
5. 启动新 App，确认进程、端口、Hook、手机连接和关键功能。
6. 若出现新问题，正常退出后恢复备份，不覆盖唯一可恢复副本。

本仓库已有一次可恢复安装实例，见 [2026-08-25 Bridge CPU 修复](updates/2026-08-25-agentpager-bridge-cpu-fix.md)。该记录是历史证据，不替代当前安装前的重新核实。

## 5. 运行时验证

Bridge 正常启动后监听：

- `49361`：Codex/Claude Code/ZCode Hook 本地入口。
- `49362`：配对信息与 WebSocket 服务。

本地合成端到端验证：

```bash
node scripts/e2e-local.mjs
```

它会连接正在运行的 Bridge，注入合成 Hook 事件，并验证状态同步、反向审批、结束收敛和关闭帧后的存活。它不会替代以下现场检查：

- 菜单栏窗口、二维码、状态和错误提示是否正确。
- Codex Desktop 中 AgentPager Hook 是否已信任。
- Claude Code 原有 Hook 配置是否被保留。
- ZCode 新 Session 的 Hook、手机审批与配置恢复，以及 GLM 真实读数与手机展示；按现行功能说明区分合成测试、用户反馈和现场证据。
- Android 手机能否在局域网中配对、保持在线并正确显示任务。
- 日志轮询、长会话或持久化修改后的 CPU、内存和 macOS 诊断报告。

GLM 钥匙串改动还有专门的验收边界：

- `swift test` 中的 `GLMKeychainStoreTests` 只创建、锁定、解锁并删除随机路径的测试钥匙串，使用合成 Key；不锁定登录钥匙串，也不读取真实 GLM Key。它覆盖已锁定、权限不足、重新打开与静默读取。
- 现有 GLM 条目属于文件钥匙串，不能仅凭 `kSecUseAuthenticationUIFail` 或全局关闭 UI 推断静默。当前实现先查条目所属钥匙串的锁定状态，再在进程内共享锁保护下临时禁用交互，并恢复原策略。配对钥匙串操作共用该锁，避免 GLM 的策略影响配对；不改变配对数据或访问权限。
- 隔离测试不等于真实账号授权验收。安装最终签名版本后，用户在“配置 → ZCode → GLM 额度连接”主动授权，并在系统提示中选择“始终允许”；检查至少两个十分钟刷新周期和重启，确认最后成功时间前移、实际读数可更新且不反复要求密码。配对与 GLM 是两个条目，首次授权可能分别询问。
- 固定签名后仍需比较两个不同构建的 designated requirement（系统用于识别应用身份的规则），并验证新版可读旧版创建的合成条目；只比较 Bundle ID 或签名验证通过不够。

隔离签名验证可运行 `python3 scripts/test-macos-keychain-signing.py`（需要 OpenSSL 3 和当前 Swift 工具链）。它在临时目录生成一天有效的测试证书，导入临时钥匙串，编译生产 KeyStore 的测试调用端，验证两个不同签名构建的读取权限以及改签后的静默拒绝。结束时删除测试钥匙串和私钥文件，并核对用户搜索列表与默认钥匙串未改变；结果写入被忽略的 `dist/glm-signing-probe-result.json`。该脚本不启用正式本机签名，不导入登录钥匙串，也不修改系统信任。

## 6. iOS 27 模拟器的边界

本机已经安装 iOS 27 Simulator Runtime 和可用的 iPhone/iPad 模拟设备，但当前仓库没有 iOS App Target。它可供未来 iOS 开发使用，不能验证当前 macOS Bridge，也不能替代 Android 模拟器或 Redmi 真机验收。

## 7. CI、发布与安全边界

- `.github/workflows/release.yml` 的 macOS Job 会运行 `swift test`、构建通用 DMG，并在提供完整证书与 Apple 凭据时执行签名和公证。
- 该工作流只在手动触发或 `v*` Tag 推送时运行；普通分支没有自动 macOS CI。
- 未经用户明确要求，不推送 Tag、不创建 Release、不导入 Developer ID 证书、不提交 Apple 公证，也不替换 `/Applications` 中的 App。
- Hook 配置、配对密钥、证书、密码和公证凭据不得写入代码、文档、日志摘要或 Git。
- 协议、配对或控制消息变化必须同步检查 `protocol/`、Android、macOS 与 Windows。

## 8. 文档维护

- 稳定、反复使用的 macOS 流程更新到本文。
- 单次工具链版本、安装、故障、性能和验收证据写入 `docs/updates/YYYY-MM-DD-*.md`。
- Package 结构、最低系统、Xcode/Swift 要求、Hook/协议、签名、公证、安装或验证流程变化时，重新运行 `$claude-agents-bootstrap`。
