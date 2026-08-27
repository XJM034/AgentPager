# 2026-08-25 Android Agent 开发环境更新

## 结果

本轮已完成 Android 基础开发环境、项目级 Agent 说明、官方 Android CLI Skills、环境检查脚本和 Compose 亮度预览。项目可在 Android Studio 打开，Gradle 已固定使用 JDK 17，单元测试、Lint 和 Debug APK 构建通过。

模拟器最终已完成：清理不完整安装标记并重新下载后，API 36 ARM64 系统镜像安装成功，`medium_phone` 已创建、启动并完成 AgentPager Custom 的安装与运行验收。

## 延续的定制状态

- 分支：`custom/brightness`
- 当前提交：`91e4f02`
- 个人 Fork：`origin` → `XJM034/AgentPager`
- 原作者仓库：`upstream` → `afetmin/AgentPager`
- Debug 定制包：`com.agentgrid.mobile.custom`
- App 名称：`AgentPager Custom`
- 任务亮度和空闲亮度默认值：均为 `100%`
- 官方版和定制版继续使用不同包名，可在手机上共存。

## 新增和调整

### 本机工具

- 安装 Android Studio Quail 3（2026.1.3 Patch 1）。
- 安装并初始化 Google Android CLI `1.0.15985488`。
- `~/.androidrc` 指向现有 SDK `/opt/homebrew/share/android-commandlinetools`，并关闭 CLI metrics。
- 安装 Homebrew OpenJDK 17.0.19；Android Studio 和脚本使用 `/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home`。
- 安装 Android Emulator 37.1.11。
- 安装 API 36 默认 ARM64 和 Google Play ARM64 系统镜像，并创建 `medium_phone` AVD。
- AgentPager Bridge 0.3.0 已安装在本机。

### 仓库能力

- 新增根目录和 Android 子目录的 `AGENTS.md` / `CLAUDE.md`，为 Codex 与 Claude Code 提供同一套范围、构建和验证规则。
- 通过 Google Android CLI 安装项目级 `android-cli` Skill：`.agents/skills/android-cli/` 与 `.claude/skills/android-cli/`。
- 新增 `scripts/android-doctor.sh`，区分“基础工具完成”和“模拟器完成”。
- 更新 `scripts/install-android.sh`，在指定设备上构建、标准安装、启动并等待定制包进程就绪；多设备时要求设置 `ANDROID_SERIAL`。
- 为亮度设置面板新增 `BrightnessSettingsPreview`，可独立查看任务亮度和空闲亮度。
- 在 Manifest 中声明相机硬件为非必需，消除 ChromeOS 兼容性 Lint 错误；相机权限和扫码功能未被移除。
- 新增稳定开发文档和日期化更新入口。

## 已验证

### 构建检查

使用 JDK 17 运行：

```bash
cd android
JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home" \
  ./gradlew testDebugUnitTest lintDebug assembleDebug
```

结果：`BUILD SUCCESSFUL`，55 个任务完成；JVM 单元测试、Android Lint 和 Debug APK 构建均通过。

### Android Studio 与 UI 预览

- Android Studio 已信任并打开本仓库的 `android/` 工程，没有自动信任整个父目录。
- 修正 Gradle JDK 后，Android Studio 使用 JDK 17 完成项目同步。
- Android CLI 检测到 Studio 项目状态为 `READY`。
- `BrightnessSettingsPreview` 已实际渲染并查看，任务亮度和空闲亮度都显示为 `100%`。
- 已把 Compose Preview、Live Edit、Apply Changes 和重新运行的分工写入稳定文档；Live Edit 作为全局用户偏好未被强行开启。

### 当前设备状态

- `android emulator list` 包含 `medium_phone`，启动后序列号为 `emulator-5554`。
- 模拟器运行 Android 16，物理尺寸报告为 1080 × 2400。
- AgentPager Custom 已标准安装并启动，进程名为 `com.agentgrid.mobile.custom`；布局读取和截图均显示配对首页。
- 相机权限已授予，日志中没有该包的 FATAL EXCEPTION 或 ANR。
- 显示服务报告 `adjustedBrightness=1.0`，亮度原因来自 AgentPager 主页面的窗口覆盖，证明未配对/空闲页面应用了 100% 窗口亮度。
- Redmi 本轮仍未连接，因此没有新增 MIUI 真机验收结论。

## 模拟器失败与恢复记录

- Google APIs API 36 ARM64 和 AOSP API 36 ARM64 系统镜像都出现 ZIP 读取失败。
- Android CLI 一度把只有 `.installer` 标记的空目录误列为已安装；该目录被移入 `/tmp` 备份，没有删除项目文件或手机数据。
- 重新下载 API 36 默认 ARM64 镜像后安装成功；`android emulator create medium_phone` 随后成功安装 Google Play ARM64 镜像并创建 AVD。
- 首次安装时进程启动慢于脚本检查，已增加最长 10 秒的进程就绪等待，消除误报。
- 差量安装在本环境返回明显较慢，自动脚本改用更稳定的标准安装；手工调试仍可按需使用 Android Studio 的 Live Edit 或 Apply Changes。

## 范围与发布状态

- 没有新增 Firebase、云数据库、云后端、Google Play 或付费服务。
- 没有配置正式签名或 Release Secrets。
- 没有推送、发版、创建 Release 或向上游提交 PR。
- 本轮文档和脚本属于当前工作区未提交修改，后续提交前仍需再次审查差异。
