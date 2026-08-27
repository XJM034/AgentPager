# Android Agent 开发环境

本文说明如何在本仓库使用 Codex 或 Claude Code 定制 Android App，并区分 UI 预览、模拟器验证和 Redmi 真机验收。

## 服务与工具状态

| 能力 | 当前配置 | 用途 |
| --- | --- | --- |
| Android Studio | 已安装 Apple Silicon 版 | Compose Preview、调试、设备管理 |
| Android CLI | 已安装，并由 `~/.androidrc` 指向项目现用 SDK | Agent 安装、启动、布局读取、截图、SDK/AVD 管理 |
| Android SDK | API 36、Build Tools 35/36、Platform Tools | 编译和设备控制 |
| JDK | Homebrew OpenJDK 17 | 运行本仓库 Gradle；不使用当前 Studio 自带的 JBR 25 |
| 模拟器引擎 | 已安装 Emulator 37.1.11 | 完整 App 验证 |
| 模拟器系统镜像 / AVD | API 36 Google Play ARM64，`medium_phone` | Android 16、1080 × 2400 的日常验证设备 |
| Redmi 真机 | 曾验证，当前是否在线以 `adb devices -l` 为准 | 亮度、MIUI、硬件与长期常亮验收 |
| AgentPager Bridge | macOS 0.3.0，本机运行 | 局域网配对、状态同步和反向控制 |
| GitHub | `origin` 为个人 Fork，`upstream` 为原作者仓库 | 保存定制和同步上游 |

不需要 Firebase、云数据库、云后端、Google Play 或付费云真机。正式签名只在公开分发或发布时配置。

## 一次性环境检查

在仓库根目录运行：

```bash
scripts/android-doctor.sh
```

该脚本核实 Android Studio、Android CLI、SDK、JDK、Gradle、虚拟设备和当前 adb 设备。它不会安装 App，也不会修改手机。当前包含 `medium_phone` 的完整检查返回成功；如果以后 AVD 缺失，脚本会以状态码 `2` 退出并明确提示“模拟器仍待配置”。

本机 Android CLI 配置位于 `~/.androidrc`：

```text
--sdk=/opt/homebrew/share/android-commandlinetools
--no-metrics
```

项目自己的 SDK 路径位于被 Git 忽略的 `android/local.properties`，不要把绝对路径提交到仓库。

## 三档查看效果

### 1. Compose Preview

用于文字、颜色、间距、滑块、卡片和局部布局。当前亮度设置面板已有 `BrightnessSettingsPreview`。

Android Studio 打开 `android/` 后，在对应 Kotlin 文件的 Split 或 Design 视图刷新 Preview。Preview 不证明网络、权限、硬件或 MIUI 行为。

### 2. Android 模拟器

已配置 `medium_phone`：Google Play API 36 ARM64 系统镜像，对应 Android 16，模拟分辨率为 1080 × 2400。2026-08-25 已完成启动、APK 安装、进程、布局、截图、日志和空闲亮度验证。

启动虚拟设备：

```bash
android emulator start medium_phone
```

不再使用时停止虚拟设备：

```bash
android emulator stop medium_phone
```

构建、安装并启动定制版：

```bash
scripts/install-android.sh
```

如果真机和模拟器同时在线，先选择目标：

```bash
export ANDROID_SERIAL=emulator-5554
scripts/install-android.sh
```

Agent 优先读取 UI 布局，必要时再截图：

```bash
android layout --device="$ANDROID_SERIAL" --pretty
android screen capture --device="$ANDROID_SERIAL" -o /tmp/agentpager-screen.png
adb -s "$ANDROID_SERIAL" logcat -d -v threadtime
```

截图必须实际查看，不能只根据文件生成成功判断 UI 正常。

### 运行后的快速迭代

这套流程不要求每改一个按钮都手工导出 APK 再传到手机：

1. 单个 Compose 组件优先用 Preview，完全不需要启动设备。
2. App 已在模拟器或真机运行后，纯 Compose UI/UX 小改可以在 Android Studio 启用 Live Edit；该功能仍在持续开发，遇到不稳定时回退到普通运行。
3. 兼容的代码或资源变化可以用 Apply Changes 增量推送；Manifest、依赖、启动结构等变化仍应重新运行 App。
4. Agent 做完较大修改时运行 `scripts/install-android.sh`，由脚本自动构建、安装和启动，不需要用户手动寻找 APK。

Live Edit 是全局 Android Studio 设置，本轮没有强行改变用户偏好；需要时可在 `Android Studio → Settings → Editor → Live Edit` 选择手动或自动模式并实际验证。

### 3. Redmi 真机

真机开启“开发者选项 → USB 调试”和 MIUI 的 USB 安装权限，连接后运行：

```bash
adb devices -l
export ANDROID_SERIAL=<实际序列号>
scripts/install-android.sh
```

重点验收亮度、常亮、振动、相机、通知、开机启动、后台限制和局域网连接。修改亮度后可结合 Android 窗口状态检查实际 `screenBrightness`，但最终仍要肉眼确认屏幕效果。

## 标准 Agent 工作流

1. 核实 Git 分支、未提交改动、SDK 和目标设备。
2. 只修改请求范围，保留官方版和定制版共存。
3. UI 组件补 Preview；业务逻辑补单元测试。
4. 运行：

   ```bash
   cd android
   JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home" \
     ./gradlew testDebugUnitTest lintDebug assembleDebug
   ```

5. 在模拟器安装、启动，先读布局，再按需截图和查日志。
6. 涉及硬件或 MIUI 时连接 Redmi 复验。
7. 报告已验证、代码推断和环境限制，不把 APK 构建成功等同于运行正确。

## Bridge 端到端验证

本机 Bridge 已安装时，可让现有脚本验证 Hook 状态同步和反向审批。脚本会产生本地测试任务，不访问云端：

```bash
AGENTPAGER_HOOK_EXECUTABLE="/Applications/AgentPager Bridge.app/Contents/MacOS/AgentPagerHooks" \
  node scripts/e2e-local.mjs
```

真实手机或模拟器的配对信息属于凭据，不要复制进文档、Issue 或提交记录。

## Git 与上游更新

```bash
git fetch upstream
git merge upstream/main
git push
```

合并冲突时 Git 会停止。先保留自定义亮度、包名隔离和文档守则，再逐项吸收上游变化。未经用户确认不要推送、打 Tag 或运行发布工作流。

现有 `.github/workflows/release.yml` 只在手动触发或 Tag 推送时构建发布产物；当前没有普通分支 Push/PR 的 Android CI，因此本地验证命令仍是必需项。

## Skills 路由

Google Android CLI 是规范来源，项目内有两个由官方 CLI 安装的副本：

- Codex：`.agents/skills/android-cli/`
- Claude Code：`.claude/skills/android-cli/`

两份应保持一致，不手工修改。更新命令：

```bash
android skills add --agent=codex,claude-code --project=. android-cli
```

更新后检查两份 `SKILL.md` 一致，并在新会话验证加载。项目副本不等于全局安装。

## 已知边界

- 当前没有 `androidTest` 设备自动化测试。
- 模拟器无法证明 Redmi 的亮度和 MIUI 行为。
- 普通分支没有自动 CI。
- 正式签名 Secrets、Google Play 和公开发布流程不属于当前个人 Debug 定制范围。

## 参考

- [安装 Android Studio](https://developer.android.com/studio/install)
- [创建和管理虚拟设备](https://developer.android.com/studio/run/managing-avds)
- [Compose Preview](https://developer.android.com/develop/ui/compose/tooling/previews)
- [Compose Live Edit](https://developer.android.com/develop/ui/compose/tooling/iterative-development)
- [运行 App 与 Apply Changes](https://developer.android.com/studio/run/)
- [Android CLI](https://developer.android.com/tools/agents/android-cli)
- [Logcat 命令行工具](https://developer.android.com/tools/logcat)

当 SDK/JDK、包名、权限、协议、测试入口、设备策略或文档结构变化时，更新本文并重新运行 `$claude-agents-bootstrap`。
