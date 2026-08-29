# Issue #7 首次贯通 GLM Coding Plan 额度

日期：2026-08-29

范围：GitHub Issue #7，仅实现 GLM Coding Plan Key 的安全配置、Gate 0 额度查询、Bridge 刷新与快照发送，以及 Android 顶部 GLM 双窗口紧凑额度块。没有开始 Issue #8 的详细错误降级、陈旧数据、详情页或完整恢复策略。

## 用户可见结果

- macOS Bridge 设置新增始终可发现的 `GLM` 标签，提供安全输入、保存并验证、手动刷新和删除 Key 入口。
- 已保存的完整 Key 不会回显；界面只显示未配置、已配置、验证成功或验证失败。
- Bridge 在启动、手机新连接、手动刷新和每 10 分钟轮询时异步刷新；重叠刷新合并为一个在途请求。
- 有可信额度时，Bridge 通过现有 `usageProviders` 发送一个 `id=glm`、`displayName=GLM` 的裁剪快照；未配置 Key 时不查询，也不发送空 GLM provider。
- Android 在现有 `GENERAL`、`SPARK` 后增加一个同高的 `GLM` 紧凑块，块内显示 5 小时与每周窗口；缺少 GLM 数据时不占位。
- Codex General、Spark、历史用量、任务监控、Hook、配对和手机审批继续使用原路径。

## Gate 0 契约实现

- 仅查询 `quota/limit`，鉴权采用 Gate 0 已验证的 `Authorization` 裸值格式。
- HTTP 成功后继续检查 JSON `success`、`code` 和 `data`；HTTP 200 + 业务 401 视为无效凭据。
- 只把 `CREDIT_LIMIT` 中 `unit=3, number=5` 与 `unit=6, number=1` 识别为 5 小时和每周窗口。
- 上游 `percentage` 作为已使用比例，Android 使用 `clamp(100 - percentage, 0...100)` 后的可用比例。
- 上游 `remaining` 原样投影为 `remainingAmount`，没有用总量和当前值重算。
- `level` 缺失时保持为空，存在时按不透明原值传递；面向用户的套餐名固定回退为 `GLM Coding Plan`。
- 缺失、非数值或超出范围的 percentage 会使本次数据不可用，不会显示为 0% 或 100%。

## 安全与存储

- 生产 Key 存储只使用 macOS 系统钥匙串，非敏感标识为：
  - service：`com.agentpager.bridge.glm-coding-plan`
  - account：`coding-plan-key`
- 候选 Key 先通过 provider 验证，成功后才写入钥匙串；无效候选不会覆盖旧 Key。
- Bridge 没有扫描 shell、浏览器、ZCode 配置、OAuth 或其他凭据来源。
- GLM 默认使用独立临时网络会话，禁用 Cookie 发送、Cookie 存储和 URL 缓存，不复用共享会话状态。
- Key、请求头值、Cookie、原始响应、账号信息和错误正文不进入 Android 协议、普通日志、任务持久化或仓库文档。

## TDD 与自动化测试

本次按公共接缝执行红绿循环：GLM provider adapter、Key/刷新协调器和 Android 顶部额度选择。新增测试先分别因目标类型、候选保存入口和 provider 合并参数不存在而失败，再补最小实现转绿。

已验证：

- `scripts/android-doctor.sh`：通过；JDK 17、Gradle 8.13、Android SDK 与 `medium_phone` 可用。
- `swift --version`：Apple Swift 6.4（swiftlang-6.4.0.33.1，Target `arm64-apple-macosx27.0.0`）。
- `cd macos && swift test`：本次后续复验共 158 项通过、失败 0 项，其中 `AgentGridCoreTests` 154 项、独立的 `AgentGridBridgeTests` 4 项。
- Android `testDebugUnitTest lintDebug assembleDebug`：通过。
- `protocol/fixtures` 与 `docs/contracts` 下全部 JSON 经 `jq empty` 解析通过。
- `git diff --check`：通过。
- Issue #7 源码与 Debug APK 的高风险凭据模式扫描：未发现真实 Key、Bearer Token 或 JWT 形态内容。
- 暂存区保持为空；开场已有的用户修改和未跟踪文件仍保持未暂存状态。

测试覆盖 Gate 0 成功响应、两个 `CREDIT_LIMIT` 窗口、百分比方向、服务器 remaining、level 缺失/透明传递、套餐名回退、业务层 401、非法 percentage、未配置不查询、候选验证保护、删除与刷新竞态、四类刷新触发、10 分钟调度与 single-flight、禁用 Cookie/缓存、Key 经生产 `BridgeModel` 状态回调后仍不进入日志、共享快照与任务持久化、生产 `BridgeModel` 的启动/手机/手动接线，以及从 `BridgeModel` 发起的阻塞查询不影响真实 Hook/WebSocket。Android 覆盖固定顺序、只有 GLM、没有 GLM和旧快照兼容。

## GitHub Issue 核对

经用户明确授权，只读刷新 `origin/alexx_custom` 并读取 GitHub Issue #7：

- 本地 `HEAD` 与 `origin/alexx_custom` 均为开场基线 `91446e82c6f7c678fa85c05a52e2539cd648ce75`，领先/落后为 `0/0`。
- Issue #7 标题为“[GLM/ZCode 6/9] 首次贯通 GLM Coding Plan 额度”，状态为 `OPEN`，标签为 `ready-for-agent`，没有评论。
- 当前正文继续要求安全 Key 输入/保存/验证、Gate 0 adapter、四类低频触发与 single-flight、GLM 双窗口、固定顶栏顺序、缺 Key 无占位、敏感信息隔离和 Codex 回归；没有新增范围。
- 当前正文记录 `Blocked by #3`；本次没有改写依赖、标签或 Issue 状态。

## 真实 Key 与接口验证

未执行。本次没有读取或写入真实 Coding Plan Key，没有访问真实钥匙串项，没有调用真实 GLM 额度接口，也没有输出原始响应。

## Redmi UI 验证

未执行。环境体检检测到 Redmi Note 7 已连接，但没有安装 APK、启动应用或操作设备。新增了以下 Compose Preview 并通过 Android 编译：

- GENERAL + SPARK + GLM；
- 只有 GLM；
- 没有 GLM；
- 窄屏三提供方布局。

Preview 和自动化构建不能替代 Redmi 真机对顶栏顺序、同高、单行、首条任务无遮挡和实际可读性的验收。

## 根据代码推断

- GLM 网络调用位于独立 provider adapter，Bridge UI、WebSocket 和 Android 不包含上游 URL、鉴权或 JSON 解析逻辑。
- URLSession、Key 存储和轮询调度均可注入；测试没有使用真实十分钟 sleep。
- GLM 刷新由独立异步任务执行，Bridge 触发入口立即返回；Hook、WebSocket、配对和审批路径没有等待 GLM 网络结果。
- 协议字段未变化，因此没有修改共享协议文档、fixtures 或 Windows；Windows 继续只保持 Issue #3 已有解析兼容，不查询 GLM。

这些结论来自代码结构和自动化测试，不等同于真实菜单栏、局域网连接或设备运行证据。

## 用户批准的豁免

无。本次没有请求或沿用真实接口、真实 Key、钥匙串、安装或 Redmi 验收豁免；Issue #2 的历史 OAuth 豁免不适用于 Issue #7。

用户只批准了刷新个人 fork 的远端分支引用和读取 Issue #7 当前状态；该授权没有扩展到真实 GLM 查询、钥匙串、安装、推送、评论或关闭 Issue。

## Standards 与 Spec 审查

首轮双轴审查发现：

- Standards：实施记录尚未同步联网核对结果；刷新原因枚举没有参与行为；Android provider 身份、标题和配色存在分散字符串判断。
- Spec：删除 Key 与自动刷新存在竞态；Key 隔离及 GLM 不阻塞 Hook/WebSocket 的自动化证据不足；第二轮指出早期隔离与触发测试没有经过生产 `BridgeModel` 接线。
- 本地补充发现：共享 URLSession 可能在传输层自动携带 Cookie。

上述问题已分别通过更新记录、无参 single-flight 刷新入口、集中 `QuotaKind/QuotaAccent` 映射、删除等待在途刷新、经过生产 `BridgeModel` 的共享快照/任务持久化与触发接线测试、从 `BridgeModel` 发起查询时的真实 Hook/WebSocket 非阻塞测试，以及禁用 Cookie/缓存的独立临时会话修复。Bridge 接线测试最终迁入独立 `AgentGridBridgeTests` 目标，`AgentGridCoreTests` 恢复只依赖 Core，修复了第二轮 Standards 指出的测试分层偏差。

最终 fixed-point 双轴复审结果：Standards 发现 0 项，Spec 发现 0 项。本次后续复验为 154 项 Core 测试加 4 项 Bridge 测试，失败 0 项。

## 未验证项

- 真实 Coding Plan Key 的保存、验证、刷新和删除。
- 真实额度接口与官方页面同时间的 5 小时、每周、已用方向和可用比例对照。
- 最终 App Bundle 的打包、签名、安装、菜单栏设置交互与回滚。
- Android Custom APK 在 Redmi 上的安装、保留数据、顶栏布局和局域网快照联调。
- medium_phone 或 Redmi 的真实渲染截图；当前只有 Compose Preview 源码与编译证据。
- 10 分钟轮询下真实 Bridge 进程的 CPU、内存与 macOS 诊断报告观察；单元测试不能替代长期运行测量。
