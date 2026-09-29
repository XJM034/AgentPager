# Codex memories_v2 后台任务隐藏

## 原因与修改

用户反馈手机再次显示记忆整理任务，计时约 3 小时 50 分钟。本机 Bridge 持久记录显示项目名为 `memories_v2`，标题为 `Consolidate the supplied rollout s`，提示词为新版整理指令。旧过滤同时要求 `memories` 与 `Memory Writing Agent:`，因此漏过。

Android 任务投影补齐新版项目名和提示词前缀，并兼容 Bridge 截断标题及缺少 userPrompt 的快照。仍限制 Codex 来源与记忆项目，不隐藏普通同名项目工作。运行、完成和遗留运行快照均通过同一过滤，不参与焦点、展开和提示音。

只修改 Android 投影及回归测试；未改协议、macOS、Codex 记忆文件或真实任务状态。检查代码确认 Bridge 启动时已有恢复任务核对，运行中也有日志消失后的结束处理。本轮未复现该真实会话的结束过程，不能断言计时对应真实持续执行，也不按超时强行结束普通任务。

## 验证

- 分支 `alexx_custom`；原有 Entire 和其他文档改动保留。
- Entire 仅运行项目只读预检，当前 Session 与转录身份匹配、active、1 个临时 checkpoint；编辑后 files_touched 已包含本次两个代码文件。未形成新提交，因此未验证提交 checkpoint 关联；未运行维护或修复命令。
- `scripts/android-doctor.sh` 通过；当前无连接的 adb 设备。
- Android：`JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home" ./gradlew testDebugUnitTest lintDebug assembleDebug`；101 项测试、0 失败、0 错误，Lint 和 Debug 构建通过。
- 回归包含 Codex 两种来源、新旧记忆格式、截断标题、缺失提示词、四小时运行记录、完成状态、焦点/展开/声音，以及普通同名项目和其他来源的误删保护。
- 未安装、未提交、未推送；手机现场效果未验证。本次默认构建包为验证产物（versionCode 1），安装前需按设备当前版本设置递增版本号并重新打包。

现行说明已同步至 `docs/zcode-glm-integration.md`；平台开发流程、权限与架构没有变化。

## Redmi 安装跟进

用户连接安卓后授权继续安装。核实唯一设备 Redmi Note 7、既有版本 Build 28，目标仍为 `com.agentgrid.mobile.custom`。备份旧 APK 后，以 `AGENTPAGER_VERSION_CODE=29` 重跑单元测试、Lint 和 Debug 构建，全部通过。新旧 APK 的 Android Debug 证书 SHA-256 相同；新包 minSdk 29 / targetSdk 36。

Android CLI 覆盖安装、启动成功；设备包信息确认 Build 29，进程存活。未卸载、未清空应用数据。旧包、新包及现场截图保存在忽略目录 `dist/qa/2026-09-29-memory-v2/`。

安装前实际截图确认 `memories_v2` 卡片计时 4:15:05，底部提示 Bridge 离线重连。安装后实际查看额度页和任务页截图，App 正常显示，但 Bridge 仍离线、任务列表为空。因此本轮确认安装与启动成功，不能把空列表当作收到真实任务后过滤成功的现场证据；在线同步后的过滤仍待验收。UI layout 因 MIUI 缺少 theme_compatibility.xml 失败，按 Android CLI 技能改用截图验收。未启动或修改 Mac Bridge，未提交或推送。

## 重连后现场检查

用户随后打开 Bridge 并确认连接。只读检查确认 Bridge 监听 49362；实际查看 Redmi 的 `reconnected.png`，离线提示消失，当前 AgentPager 会话显示最新“已连上”提示词和本轮工具活动，另一个普通会话显示完成状态，Codex 额度也已同步。页面未显示 `memories` / `memories_v2` 卡片。

同时读取 Bridge 持久记录确认两条旧 memory 已由既有恢复逻辑转为 `interrupted`，不再是遗留 running。故在线同步与旧卡片不再展示已有现场证据；新版 memory 仍运行时的隐藏由前述回归测试证明，本次没有重新触发真实记忆整理任务。用户无需再操作；未提交或推送。
