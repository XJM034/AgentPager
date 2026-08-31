# Android 首页额度标题与紧凑布局

## 目标与范围

用户提供的横屏照片中，`GENERAL / SPARK` 与 `GLM` 被画成同级区块，缺少 Codex 平台标题。本次按 Product Design 的视觉层级与截图对照方法，在既有 Kotlin / Compose 原生界面内调整，没有新建网页或替换设计系统。

- 平台层级改为 `CODEX / GLM`，均使用原 GLM 的青蓝色；Codex 内部仍区分 General 与 Spark。
- General 仅在首页简写为 `GEN`；保留 `SPARK` 全称，详情与辅助朗读仍保留 `GENERAL`。
- 周期短标签统一为 `5h / 7d`。用户补充确认截图中 General 仅有周额度，因此默认预览只保留 `7d`；实际显示继续读取 Bridge 返回的窗口，既不人为添加窗口，也不硬编码禁止未来真实返回的其他窗口。
- 缩短内边距与窗口占用，平台区块可横滑；右侧状态切换和设置按钮固定。任务列表按顶栏的实际高度预留空间，避免多任务时重叠。
- GLM 陈旧或异常状态继续显示文字提醒。未提供额度的分区不占位。

修改限于 `AgentGridScreen.kt`、`UsagePresentation.kt` 及本次功能说明。额度计算、Bridge、协议、Key、存储、权限、macOS、Windows 和详情页数据路径均未修改。布局可容纳后续分区，但不代表已经接入其他 Agent。

## 本地验证

- 分支：`alexx_custom`，开始时工作区干净；未创建分支、提交、推送或关闭 Issue。
- `scripts/android-doctor.sh`：通过。JDK 17、Gradle 8.13、SDK 36，虚拟设备 `medium_phone`。
- 最终代码运行 `JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home" ./gradlew testDebugUnitTest lintDebug assembleDebug`：成功；78 项 JVM 测试，0 失败、0 错误；Lint 0 error、34 warning，包含依赖版本提示及已有 Compose/平台建议，不代表零警告。
- Debug 产物：`com.agentgrid.mobile.custom`，`AgentPager Custom`，版本 `0.3.0-custom` / code 1，min SDK 29、target SDK 36；Android Debug 签名校验通过。仅安装到 `medium_phone`（`emulator-5554`），保留其已有数据，不安装 Redmi。
- Compose Preview 已补齐平台分组、360dp 窄屏、大字体、GLM 陈旧、仅 GLM、仅 Codex、无额度和五条任务首页场景。初轮 Studio 渲染检查了分组、字体与异常提示；后续发现 IDE 缓存旧 helper 数据，因此旧截图不作为最终 General 窗口与避让效果的证据。
- 最终 APK 在模拟器通过现有 `androidx.compose.ui.tooling.PreviewActivity` 直接运行 `AgentGridScreenKt.QuotaTaskTerminalPreview`，使用合成额度与任务，不启动配对流程，不接触真实 Bridge 或凭据。
- 最终模拟器布局读数确认 `CODEX，GENERAL，WEEK 剩余 95%`，无 General 5h；Spark 与 GLM 各两个窗口。横屏截图确认平台标题同级，五条任务列表首条与顶栏不重叠。
- 窄屏实际横滑后 GLM 周额度 `99%` 可见；状态按钮与设置按钮坐标不变。保留完整辅助朗读名称。
- 模拟器设置按钮可打开、关闭设置面板；没有操作亮度、配对或提示音设置。测试后退出预览，恢复原旋转设置并停止本次启动的模拟器。

## 验证边界与下一步

- 本次数字均为合成测试数据，不是账号当前额度；未访问真实 GLM 服务、Key 或完整响应。
- 原生预览与模拟器组件运行不能代替真实配对主页、真实额度刷新、Redmi 屏幕观感或长期运行验收。
- 真实 Redmi 安装与现场确认仍需用户授权；本次未修改真实手机或已安装的 macOS Bridge。
- 现行说明已同步到 `docs/zcode-glm-integration.md`；没有变更开发工具链、协议、安全边界或长期流程，因此不修改根规则、领域文档或平台开发说明。

## 后续反馈：压缩顶栏高度

用户反馈首版平台标题单独一行侵占任务区的垂直空间，进一步调整：

- 平台标题、内部额度组、周期与百分比改为同一行排列，仍用青蓝平台名与原颜色区分层级；GLM 异常文字也同行显示，不删除提示。
- 额度块上下内边距由 3dp 收到 2dp；顶栏顶部留白由 10dp 收到 6dp；任务区额外避让由 8dp 收到 2dp。
- 数字与标签字号不变，右侧按钮仍为 28dp，不通过缩小文字或点击区域换取高度；大字体可自然撑高，不固定裁切。
- General 的真实窗口逻辑、仅周额度的默认预览、横向滚动、固定按钮与所有数据路径不变。

本次在上一轮未提交修改上继续迭代，没有覆盖或提交其他内容。

复验结果：

- 再次运行 `testDebugUnitTest lintDebug assembleDebug` 成功；78 项测试，0 失败、0 错误，Lint 0 error。
- 在同一 `medium_phone` 安装最终 Debug APK 并运行合成首页预览；横屏截图确认标题与额度同行，General 仍只有 `7d`，首条任务没有被遮挡。
- 默认字号下，含顶部留白的控制条高度约由 47dp 收到 34dp；加上任务区额外间距，总预留约由 55dp 收到 36dp，减少约 35%。按钮大小和数字字号未缩小。
- 此次追加的大字体与窄屏复验因预览启动后回到未配对主页而未完成，不把上一版的相关截图当作本版实测；未执行配对或改动真实 Bridge。结束时恢复模拟器字体和旋转设置并停止模拟器。
- 新版截图是合成数据的模拟器组件预览，不是 Redmi 实测；仍未安装真实手机、提交或推送代码。

## 用户确认与本地提交

用户已确认压缩后的方案，并授权将本次代码与文档暂存、形成本地提交。本记录与两个 Android UI 文件及现行功能说明一并纳入该提交；不包含推送、发布或 Redmi 安装。上述窄屏、大字体和真实手机的验证缺口继续保留，用户对方案的认可不等于设备复验。

## 后续授权：Redmi 真机安装与首页检查

2026-08-31 用户另行授权安装到 USB 连接的 Redmi Note 7（Android 10 / API 29）。本次安装包含提交 `f907ce1` 的最终 UI；分支仍为 `alexx_custom`，未改动 Android 源码，也未提交或推送本次记录及工作区中另行进行的 Entire 配置修复。

- 安装前运行 `scripts/android-doctor.sh` 通过；确认手机定制版为 Build 13，官方版为 Build 4。旧定制 APK 已备份在本地 `.git/android-install/20260831-redmi-build14/`，不进入 Git；这是安装包备份，不是应用数据备份。
- 使用现有环境变量 `AGENTPAGER_VERSION_CODE=14`，以 JDK 17 运行 `testDebugUnitTest lintDebug assembleDebug` 成功。78 项 JVM 测试全部通过，Lint 0 error、34 warning。没有修改源码中的默认版本号。
- 新包为 `AgentPager Custom`，`com.agentgrid.mobile.custom`，`0.3.0-custom` / Build 14，min SDK 29、target SDK 36；签名证书与手机旧版一致。通过 Android CLI 指定 USB 设备并携带 `-r` 覆盖安装，未卸载、清除数据或操作配对凭据。
- 安装后读取手机 APK，其 SHA-256 与本次构建一致：`4c8db37db09ddee63f081ce0454ad73d6369472ba3c93ce60e4c94fc0584f4de`。定制版 UID 和首次安装时间不变；官方版版本与更新时间不变。
- 主 Activity 已位于前台，进程正常；检查时当前进程没有 `AndroidRuntime` 的 `FATAL EXCEPTION`。原有配对可用，实际首页显示来自 Bridge 的任务与额度，不是合成预览。
- 已人工查看真机横屏截图：青蓝 `CODEX / GLM` 标题与额度同行，General 简写为 `GEN` 且本次真实数据仅显示 `7d`，Spark 和 GLM 各显示 `5h / 7d`；固定按钮和任务内容可见，顶栏没有遮挡首条任务。
- `android layout` 因 MIUI 缺少 `theme_compatibility.xml` 未能取得布局树，未反复重试；本次 UI 结论来自实际截图，不能声称完成布局树检查。未修改字体、旋转或系统设置，也未复验大字体、窄屏、长期额度刷新及硬件行为。

截图保存在本机 Codex 可视化目录的 `redmi-build14-installed.png`，不纳入 Git，以免把真实任务内容带入仓库。此前“未安装 Redmi”的描述属于前一阶段；本节记录后续已授权的真机安装结果。

## 真机用户反馈与推送授权

安装后用户反馈“没啥问题”，确认当前 Redmi 首页效果，并授权暂存、提交及推送。本反馈作为本机 Build 14 的用户验收记录；不扩展为大字体、窄屏、长时间刷新或硬件行为的验证。安卓源码继续使用已验证的 `f907ce1`，不为补录反馈重写原提交。
