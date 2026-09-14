# Android 会话显示收敛与默认全屏（2026-09-14）

> 后续用户反馈：Build 16 的 ZCode Stop 立即隐藏遗漏了完成反馈；已由 [Build 17 修正记录](2026-09-14-zcode-completion-memory-filter.md)替代该显示规则。全屏与子代理隐藏保持。

## 用户需求与实现

- ZCode 没有发消息或本轮已停止时，Android 不再持续显示“新请求”“验证请求”等会话行。
- Codex 子代理进度不再占用手机界面，保留主任务的进度与完成提醒。
- 在 `TaskDashboardProjector` 中先合并同 ID 的最新快照，再隐藏 ZCode `starting` / `idle` / `offline`；不占前五、焦点或自动展开。没有可显示任务时立即回到看板，再次运行会重新显示。
- 对 Codex Desktop / CLI 的手机展示副本清空子代理列表，自动展开与手动展开均使用该副本。主任务步骤、生命周期、审批、完成时间和未读状态保持原样；Claude Code 子代理规则保留。
- 更新两个 Compose Preview，输入包含空闲 ZCode 与活动子代理的合成快照。
- 用户追加默认全屏需求并提供 Redmi 照片。既有逻辑会持久化“退出专用模式”，导致后续窗口焦点恢复不再维持全屏；本次不再读取或写入该偏好，在 `onStart` / `onNewIntent` 恢复专用模式，在恢复窗口焦点时继续应用系统栏隐藏。进入全屏同时恢复常亮；保留边缘手势临时呼出系统栏和本次前台使用期间的“退出专用模式”。
- 通过 Android CLI 官方知识库核对 immersive mode 的系统栏 API；Context7 当时连接失败。沿用现有 AndroidX API，没有新增依赖或权限。

## 验证

- 分支 `alexx_custom`；开始时已有文档未提交修改，保持并在现行功能说明中追加本次规则。
- `scripts/android-doctor.sh` 通过：JDK 17、SDK 36、medium_phone 可用；未连接 Redmi。
- `JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home" ./gradlew testDebugUnitTest lintDebug assembleDebug`（android 目录）通过；82 项测试，0 失败，包含 14 项任务显示测试。
- 回归覆盖：空闲/未开始/离线隐藏，最新 idle 覆盖旧 running，远端焦点回退，停止返回看板与同会话恢复，ZCode 审批/回答展开，Codex 两种来源隐藏子代理且保留主任务审批和完成提醒，Claude 子代理仍可展开。
- Android Studio 实际渲染 `QuotaTaskTerminalPreview`、`ZCodeCoreSessionActivityPreview`，已查看图片：合成隐藏项不显示，运行中的 ZCode 仍显示。
- APK 核实为 `com.agentgrid.mobile.custom` / `AgentPager Custom` / `0.3.0-custom`（versionCode 1），minSdk 29 / targetSdk 36，Android Debug 签名验证通过。
- 使用 Android CLI 安装并启动于 `medium_phone` / `emulator-5554`，进程存活，未发现本次 App 崩溃记录。
- Build 15、Build 16 均重新运行同一组测试、Lint 和构建，全部通过。
- 用户连接 Redmi Note 7（Android 10 / API 29）后，备份 Build 14 APK 至忽略目录 `dist/backups/2026-09-14-redmi-build14/`，核对新旧 Android Debug 签名一致后依次覆盖安装 Build 15、Build 16，最终设备 versionCode 为 16，进程正常。
- 真机 Build 14 截图可见两条空闲 ZCode；Build 15 / 16 截图中它们已隐藏，真实 Bridge 主任务继续更新，额度可见，原配对和亮度设置保留。
- 真机 Build 16 启动和 Home 返回 App 后，实际查看截图，顶部状态栏隐藏且额度完整；窗口状态包含 `HIDE_NAVIGATION FULLSCREEN IMMERSIVE_STICKY` 与 `KEEP_SCREEN_ON`。
- MIUI 布局读取因主题配置文件缺失失败，采用 Android CLI 截图检查。模拟器布局读取也曾返回空根节点，使用实际 PreviewActivity 截图确认展开主任务不显示合成子代理。
- 图片证据保存在忽略目录 `dist/qa/2026-09-14-session-visibility/`；最终 APK 为 `dist/AgentPager-Custom-build16.apk`。不提交设备截图、APK 或配对数据。
- 按项目要求用 `claude-agents-bootstrap` 做有界说明核对，稳定启动规则补入 `docs/android-development.md`，无需新增根规则；根和 Android 两组 AGENTS/CLAUDE 镜像比较通过。
- `git diff --check` 通过。

## 边界与后续

- 修改 Android 显示、窗口启动行为与回归测试；无需更新 Mac Bridge，不改变协议、Hook、权限、GLM 凭据或数据来源，不影响子代理实际执行。
- 手机按 Bridge 报告的状态筛选；若源端漏报 Stop、仍报告 running，本次不会凭超时猜测任务已结束。
- 已完成真实 Redmi 安装、现有局域网连接、主任务实时更新与全屏启动/返回检查；未重新发起 ZCode 运行/Stop/再发消息全流程、审批往返、真实子代理生命周期或长期运行。“退出专用模式”后再次打开的分支已从代码核对，本轮未完成单独真机操作验收；重启手机和 MIUI 后台行为仍未验证。
- 未推送、发布或替换已安装的 macOS App。等待用户对日常真实会话与全屏显示的使用反馈。
