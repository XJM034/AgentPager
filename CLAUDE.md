# AgentPager 定制仓库

本仓库用于在原作者 AgentPager 基础上长期维护个人 Android App 与 macOS AgentPager Bridge 定制版；两端都是常规维护范围。Windows、协议和站点除非用户明确要求或改动涉及跨平台契约，否则保持不变。

## 每次会话先做

1. 运行 `git status --short --branch`，确认当前分支和未提交改动。
2. 阅读 [docs/README.md](docs/README.md)；处理 Android 时继续阅读 [android/AGENTS.md](android/AGENTS.md)，处理 macOS 时继续阅读 [macos/AGENTS.md](macos/AGENTS.md)。
3. 延续旧任务时，读取 `handoff/` 中最新的 `*-handoff.md`；交接仅补充上下文，重要结论仍要从代码和运行结果核实。
4. 合并、安装、推送或发布前，重新核实分支、远程仓库，以及目标平台的包名或 Bundle、SDK、签名、版本和运行设备。

## 事实来源与范围

- 上游产品说明和使用方式：`README.md`。
- Android 构建事实：`android/app/build.gradle.kts`、`android/gradle/libs.versions.toml` 和 `android/app/src/main/AndroidManifest.xml`。
- macOS 构建事实：`macos/Package.swift`、`macos/AppInfo.plist`、`scripts/package-macos.sh` 和 `scripts/package-dmg.sh`。
- Android 开发、预览、模拟器和真机流程：[docs/android-development.md](docs/android-development.md)。
- macOS 工具链、测试、打包、安装和运行验证：[docs/macos-development.md](docs/macos-development.md)。
- 定制内容与已验证结果：`docs/updates/` 中最新的日期化记录。
- Android 与 macOS 可分别直接维护；跨平台协议变化必须同时核对 `protocol/`、Android、macOS 和 Windows 实现。

## 稳定守则

- 保留官方版与定制版共存：Debug 定制版必须继续使用 `.custom` application ID 后缀和 `AgentPager Custom` 名称。
- macOS 本地打包只生成 `dist/AgentPager Bridge.app`，不等于已经安装；替换 `/Applications` 中的 App 前先备份旧版本，并核对版本、签名和二进制哈希。
- 不要把本机 SDK 路径、签名文件、证书、APK、AAB、DMG、密钥或配对凭据提交到 Git。
- AgentPager 当前通过可信局域网内的本地 Bridge 和 WebSocket 工作；不要擅自增加云后端、遥测或外部数据上传。
- 安装或卸载 Codex、Claude Code Hook 时必须保留用户已有配置，并保持可恢复备份。
- 涉及相机、振动、通知、常亮、亮度、启动和 MIUI 后台行为时，模拟器结果不能代替 Redmi 真机验收。
- 未经用户明确要求，不推送、发版、创建 Release、配置正式签名、提交 Apple 公证或提交上游 PR。
- 保留 GPL-3.0、NOTICE 和第三方许可；公开分发定制 APK 或 macOS App/DMG 前按 GPL-3.0 提供对应源码并明确修改。

## 守则状态与缺口

- 已由文件规则约束：本机 SDK 配置、Swift/Gradle 构建目录、APK/AAB、Android JKS/keystore 和整个 `dist/` 目录已列入 `.gitignore`。
- 已由代码和测试部分约束：Hook 配置保留与备份、协议签名、状态归约和 macOS 打包签名流程有对应实现或测试。
- 依赖 Agent 自觉执行：范围控制、真机复验、安装前备份、禁止擅自推送或发布目前没有 Hook 强制拦截，执行前仍要读本文件。
- 当前验证缺口：普通分支没有自动 Android/macOS CI，没有 Android `androidTest` 设备测试；Swift 单元测试不能代替菜单栏 UI、真实 Hook、局域网手机连接和长期性能验收。

## 验证入口

- 环境体检：`scripts/android-doctor.sh`
- Android 逻辑、静态检查和构建：
  `cd android && JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home" ./gradlew testDebugUnitTest lintDebug assembleDebug`
- 安装并启动定制版：`scripts/install-android.sh`
- UI：先用 Compose Preview；完整 App 用 `medium_phone` 模拟器；硬件和厂商行为用 Redmi。
- macOS 环境核实：`xcode-select -p && xcodebuild -version && swift --version && xcrun --sdk macosx --show-sdk-version`
- macOS 逻辑与构建：`cd macos && swift test`
- macOS 本地 App/DMG：`scripts/package-macos.sh`、`scripts/package-dmg.sh`；打包后仍需单独完成签名核对、安装和运行验收。
- Bridge 运行时：启动后可运行 `node scripts/e2e-local.mjs` 验证状态同步、反向审批和结束收敛；真实菜单栏、Hook 信任、手机连接与性能仍需现场检查。
- 完成代码修改后必须报告：已运行的检查、运行目标、实际结果、未验证项。

## Skills

- Android CLI Skill 的规范来源是 Google Android CLI 官方目录。
- Codex 项目副本：`.agents/skills/android-cli/`。
- Claude Code 项目副本：`.claude/skills/android-cli/`。
- 两份文件由官方 CLI 生成且当前内容一致；不要手工分叉。更新时运行：
  `android skills add --agent=codex,claude-code --project=. android-cli`
- Skill 是否被新会话加载，需要用新会话实际验证；文件存在不等于当前会话已经重新加载。
- `$claude-agents-bootstrap` 的规范来源是本项目之外受管理的 `xjm034-skill` Skill 源仓库，本仓库不保存它的项目副本；调用时使用当前会话实际加载的运行时副本，不要把源文件存在误当成已经加载。

## 文档、交接与更新

- 新的稳定 Android/macOS 开发规则分别写入 `docs/android-development.md` 与 `docs/macos-development.md`；单次环境或功能变更写入 `docs/updates/YYYY-MM-DD-*.md`。
- 本仓库当前没有长期活动队列；不要把已完成事项堆成永久待办。需要队列时，必须同时定义完成证据和归档位置。
- 大任务结束或需换 Agent 时使用 `$handoff`，默认写入 `handoff/`。
- 当 AI 说明与代码不符，或平台维护范围、构建工具链、权限、协议、存储、签名、公证、发布、安全、文档结构或验证流程发生变化时，重新运行 `$claude-agents-bootstrap`。

## 压缩上下文时保留

保留当前分支与未提交文件、目标平台、关键修改、包名或 Bundle、工具链、签名与安装目标、验证设备、验证结果、开放风险和后续步骤；不要保留长日志，改为记录可重复命令和结果摘要。
