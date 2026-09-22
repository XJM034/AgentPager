# Codex 实时额度同步与 Spark 移除

## 问题与结论

用户反馈 Codex 已恢复 100%，Android 仍显示 16%，并要求取消 Spark 监控。
本次只处理 macOS Bridge 的 Codex 额度来源、刷新和 Android 额度展示；不修改 GLM 查询、Hook、配对、协议字段、Windows 或站点。

现场核实：本地旧 Session 日志在 2026-09-20 01:23 UTC 仍记录已用 84%，对应剩余 16%；03:24 UTC 后的新日志才记录已用 0%。旧 Bridge 从日志尾部取额度，每 10 分钟刷新一次，无法独立获得空闲期间的账号重置结果。Codex 工具与本机 CLI 的只读查询当时均返回剩余 100%。

## 实现

- 新增 `CodexAccountUsageLoader`，使用本机 Codex CLI 的 `app-server --listen stdio://`，完成初始化后仅调用 `account/rateLimits/read`。本机验证 CLI 为 0.149.1。
- 优先读取 `rateLimitsByLimitId.codex`，兼容旧 `rateLimits` 响应；把已用比例换算为剩余比例，只发送真实存在的窗口及重置时间。其他额度桶不参与展示。
- 查询限时 10 秒，响应限制 1 MiB，结束后回收专用子进程；不发起模型任务，不记录完整响应，不读取或转发凭据，不兑换额度重置。
- Bridge 启动、手机连接、手动刷新和每 60 秒读取当前额度；查询失败、未登录或缺少 CLI 时返回空额度，不回退到历史日志，不猜测重置后的比例。需 CLI 登录的是希望监控的账号。
- 保留原有历史日志解析的显式调用能力，但移除 Spark 额度读取；默认运行路径不再扫描日志获取余额。
- Android 顶栏、详情和预览移除 Spark；同时过滤旧 Bridge / 旧快照中的 `spark`、`codex_bengalfox` 标识，只有 Spark 时也不回退显示。像素动画内部名为 spark 的局部变量与此功能无关，保持原样。
- GLM 与原任务维护周期保持每 10 分钟；协议结构和数据单位不变，无跨平台协议迁移。

接口依据：通过 Context7 查询的 [Codex 官方协议源码](https://github.com/openai/codex/blob/main/codex-rs/app-server-protocol/src/protocol/v2/account.rs)与 [stdio 客户端实现](https://github.com/openai/codex/blob/main/sdk/python/src/openai_codex/client.py)，并以本机只读调用核实。

## 验证

- `scripts/android-doctor.sh`：通过；JDK 17.0.19、Gradle 8.13、Android SDK 36。
- Xcode 27.0 / 27A5252f、Swift 6.4、macOS SDK 27.0；first-launch 检查通过。
- `cd macos && swift test`：188 项测试通过，包括握手、通知、子进程退出、超时、错误响应、100% 重置、旧响应兼容、Spark 过滤与 Bridge 本地 WebSocket 集成。
- 随后缩小解码范围为仅读取 codex 桶，`swift test --filter accountUsage`：5 项相关测试通过。
- `testDebugUnitTest lintDebug assembleDebug`：通过，86 项 JVM 单元测试，0 失败；最终用 `AGENTPAGER_VERSION_CODE=20` 再次 `assembleDebug` 成功。
- 编译并直接执行新 Swift loader：剩余 99%，随后用 Codex `get_usage_limits` 核实已用 1%，读数一致。排查过程中额度已从 100% 变为 99%，没有将余额写死为 100%。
- `AGENTPAGER_VERSION_CODE=20 scripts/package-macos.sh`：成功。Bundle `com.agentpager.bridge`、arm64、Build 20、Apple 团队签名；`codesign --verify --deep --strict` 通过。
- Android 产物：`com.agentgrid.mobile.custom`、`AgentPager Custom`、`0.3.0-custom`、versionCode 20；已在 `medium_phone` / `emulator-5554` 安装并启动。首次使用默认 versionCode 1 被已有 Build 18 拒绝，随后按正常升级提高到 20，未卸载或清除数据。
- 模拟器通过 Compose `PreviewActivity` 渲染 `AllQuotaProvidersPreview`；Android CLI 布局与截图确认顶栏只有 CODEX / GEN 与 GLM，没有 Spark。该预览使用固定的 95% 示例数据，不作为真实账号余额证据；Android Studio 未运行，未声称完成 IDE 内预览。

## 交付与边界

- Mac 产物：`dist/AgentPager Bridge.app`。Bridge 二进制 SHA-256：`f6f1ecd1ebdd4bc88e3a393b160d5389dc21d71d55c870b94dc472e76959ffbe`。
- Android 产物：`android/app/build/outputs/apk/debug/app-debug.apk`。SHA-256：`3f226425ccabad95cb9483f331a560aebb6f003a186d7d4247a9b29b3a432e8f`。
- 用户随后回复“安装吧”，授权安装；现已替换 `/Applications` 中的 Bridge 为 Build 20。安装产物与打包二进制哈希一致，签名验证通过。
- 用户确认安装后 Redmi Note 7 已连接，现已从 Build 18 升级到 Build 20；沿用原包名及签名，未清除应用数据。真实截图确认 Codex 为 99%，与同次 Codex 查询的已用 1% 一致，顶栏无 Spark，GLM 两个窗口仍显示。长期后台刷新和性能尚未完成验收。
- 现行说明已同步到 `docs/macos-development.md`、`docs/zcode-glm-integration.md` 与文档索引。未引入新的协议、权限或配置文件规则，无需修改根或平台 AGENTS。
- 修改位于 `alexx_custom`；本次未提交、未推送。保留会话开始前已有的文档修改和未跟踪文件。

## 安装后的现场验收

- 时间：2026-09-20 11:38–11:40（Asia/Shanghai）。
- 备份目录：`~/Library/Application Support/AgentPager/Backups/20260920-113830/`，含 `AgentPager Bridge-build19.app` 与 `AgentPager Custom-build18.apk`。Mac 备份已校验二进制哈希和签名；Android 升级前核对新旧 APK 签名一致。
- Mac 正常退出旧进程后安装并启动；进程运行路径为 `/Applications/AgentPager Bridge.app`，Hook 49361、WebSocket 49362 均正常监听。
- 使用已安装的 `AgentPagerHooks` 运行 `node scripts/e2e-local.mjs`：状态同步、反向审批、结束收敛和关闭帧存活全部通过。此处审批为合成用例，不代表真实业务请求。
- Redmi 上 `com.agentgrid.mobile.custom` versionCode 20、`0.3.0-custom` 已运行，原有连接自动恢复；屏幕显示当前任务及 CODEX / GEN 7d 剩余 99%，没有 Spark 额度块。
- MIUI 的布局导出工具因缺失 `theme_compatibility.xml` 失败，改用 Android CLI 截图并实际查看验证；没有修改系统主题配置。
- 未进行 Git 提交、推送或发布；当前验收不涵盖全天运行、多个后台刷新周期、重启后恢复或全部真实 Hook 信任状态。

## 安卓顶栏补充调整：Build 21

用户进一步要求移除顶栏 `GEN`。Android 的 CODEX 分区现直接显示周期和剩余比例，不再展示分组标签；额度窗口读取规则保持动态，不把“只有周额度”写成固定逻辑。

实时核实当前账号仅返回 `windowDurationMins: 10080`（7 天），`secondary: null`；当时剩余 99%。这只能证明当前账号未提供 5 小时窗口，不能推断所有账号均已取消。2026-09-20 查询的[官方说明](https://learn.chatgpt.com/docs/pricing#what-are-the-usage-limits-for-my-plan)仍列出按五小时计算的用量估算，并要求以账号实际额度为准。

`AGENTPAGER_VERSION_CODE=21` 下 `testDebugUnitTest lintDebug assembleDebug` 通过。Build 20 APK 已备份到同一备份目录，沿用此前安装授权升级 Redmi Note 7 至 Build 21；Mac 继续运行 Build 20。

Build 21 APK SHA-256：`b87ae3e1d25412bbd827faa7031aaf01d7391b704622887c8a34b6bdd13bb8a4`。

真机截图复验：顶栏显示 `CODEX 7d 99%`，`GEN` 已移除，GLM 仍显示两个窗口。
