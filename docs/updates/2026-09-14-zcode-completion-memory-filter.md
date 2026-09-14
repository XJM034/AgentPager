# ZCode 完成反馈与 Codex memories 隐藏（Build 17）

## 用户反馈与修正

用户实测 Build 16 后反馈：ZCode 任务完成时提示音之后立即消失，缺少 Codex 的绿色完成提示；同时要求不显示 Codex memories 后台任务。本次修正上一轮“所有 idle 立即隐藏”的过度筛选。

- Bridge 的 ZCode Stop 仍是非终态 idle。Android 将最近 90 秒的 idle 投影为本轮完成，显示绿色动画和“本轮已完成”，完成时间取原始 updatedAt；不把会话永久结束，不改变协议与审批。
- 完成反馈保留 90 秒后隐藏，不再让旧空闲会话占屏。重复快照不延长时限；同 Session 再次运行即时恢复运行行。任务列表先取同 ID 最新快照再投影。
- 新增投影刷新时间，独立于看板切换时间。其他任务运行、用户切换看板时也能到期清理，避免完成任务继续挂屏。
- Codex Desktop / CLI 来源、项目名 memories、prompt 或标题以 Memory Writing Agent: 开头（允许 Markdown 标题）的任务隐藏，不占焦点、不自动展开、不播放其运行或完成提示。普通 memories 项目工作保留。
- Codex 子代理隐藏、默认全屏、主任务审批与完成反馈保持。没有停止 Codex 记忆功能，没有修改 Mac Bridge、Hook 安装或协议。

## 自动化与预览

- 分支 alexx_custom；保留本任务已有代码及用户原有文档未提交改动，未推送或发布。
- android-doctor 通过；JDK 17、SDK 36、medium_phone 与 Redmi 在线。
- android 目录运行 `AGENTPAGER_VERSION_CODE=17 JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home" ./gradlew testDebugUnitTest lintDebug assembleDebug` 通过。
- 共 85 项 JVM 测试，0 失败；其中 17 项任务投影测试。新增覆盖本轮完成保留/到期、同会话恢复、重复快照、混合运行任务、手动看板覆盖、完成提示音只触发一次及 memories 过滤/误删保护。
- Compose Preview 实际渲染并查看图片，ZCode 完成行显示绿色“本轮已完成”；旧 idle 和 starting 隐藏。
- `git diff --check` 通过。稳定构建、权限、存储和发布流程未改变；现行功能说明已同步。

## 安装与现场验证

- 核实 origin 为个人 Fork，分支 alexx_custom；Redmi Note 7 / Android 10 / API 29。
- 新包 `com.agentgrid.mobile.custom` / AgentPager Custom / 0.3.0-custom，versionCode 17，minSdk 29 / targetSdk 36；Android Debug 签名验证通过，与原 Build 16 一致。
- 旧 Build 16 APK 已保留在忽略目录 dist；Android CLI 覆盖安装 Build 17 于 Redmi 与 medium_phone 模拟器，均成功启动。保留配对与设置，Redmi 继续显示真实额度和 Codex 主任务。
- 通过已安装 AgentPagerHooks 的 `--source zcode`，仅为独立合成会话发送 UserPromptSubmit / Stop；不执行真实模型请求、不操作业务文件或真实权限请求。
- 实际查看 Redmi 截图：合成会话运行时显示思考，Stop 后保留绿色完成行；同一会话再次 UserPromptSubmit 后恢复运行。真实 memories 后台任务不再显示。
- 完成提示音的单次触发已由状态跟踪测试验证；本次没有录音或人工听音证据。
- 第二轮 Stop 后等待超过 90 秒，实际查看 Redmi 截图：ZCode 完成行已收起，Codex 主任务仍运行；完成展示不会再立即消失，也不会被其它任务持续刷新而永久保留。

## 产物与边界

Build 17 APK 为 `dist/AgentPager-Custom-build17.apk`，截图在 `dist/qa/2026-09-14-zcode-completion/`，均不提交。

手机音量/系统音效、真实 ZCode 应用执行全流程和权限往返仍由用户实际复验；合成 Hook 真机显示验证不等于这些场景已全部通过。

## 后续显示微调（Build 18）

用户要求删除 ZCode 会话右侧对应 Codex Terminal 的灰色重复“ZCode”标签。`agentOriginLabel` 对 ZCode 返回空值，任务行与预览仅在有来源副标签时渲染；彩色 ZCode 标签、Codex Terminal / ChatGPT.app 以及其它来源保持。

使用 versionCode 18 重新运行 `testDebugUnitTest lintDebug assembleDebug`，全部通过；更新既有标签测试预期，未增加无关测试。环境检查、签名验证通过。保留 Build 17 APK 后，覆盖安装于 Redmi 与 medium_phone，均启动成功；Redmi 核实为 Build 18。已实际查看 Compose Preview 与合成 ZCode Hook 的 Redmi 截图，确认仅一个彩色 ZCode 标签、绿色完成反馈仍正常，真实 Codex 的 Terminal 标签保留。

本次仅显示微调，无新增权限、协议或安装配置变动；未重新执行 90 秒留存或真实审批全流程。APK 为 `dist/AgentPager-Custom-build18.apk`，预览与真机图片在 `dist/qa/2026-09-14-zcode-single-badge/`，不提交这些产物。现行说明已同步，未推送或发布。
