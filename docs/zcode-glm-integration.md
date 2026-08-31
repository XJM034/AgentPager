# ZCode / GLM 现行功能与验收边界

本文是个人定制版的功能阅读入口，不是新的开发队列或接口兼容承诺。
处理 ZCode 会话、手机审批、GLM 顶栏/详情、额度来源或相关验收时先读本文。
代码与协议定义当前实现；用户明确批准的需求定义目标；日期化记录说明当时验证了什么。
发生冲突时先说明差异，不把旧调研或已关闭的子 Issue 当成原始目标全部完成的证明。

## 三项能力分别判断

| 能力 | 当前实现 | 不能据此推断 |
| --- | --- | --- |
| ZCode 会话监控与手机批准/拒绝 | 已实现；由 ZCode Hook 接入，不依赖 GLM Key | 不代表所有 ZCode 控制能力均已支持 |
| GLM 独立 Key 额度连接 | 已实现；用户在 Mac Bridge 主动保存 Key，Bridge 查询并向 Android 发送裁剪快照 | 不代表复用了 ZCode 登录态，或接口具有官方长期兼容承诺 |
| 无重复 Key 的 GLM 额度接入 | 尚未实现；2026-08-29 的 #12 Gate 未找到满足条件的官方接缝 | Gate 未通过不等于独立 Key 查询代码不存在或一定不可用 |

用户后来反馈“GLM 额度检测可用”，见
[2026-08-31 补录](updates/2026-08-31-zcode-glm-documentation-sync.md)。
该反馈应保留为用户实测证据，不补造测试版本、数值、鉴权方式或完整验收结论。

## ZCode 会话与权限

- 七类 Hook 为 SessionStart、UserPromptSubmit、PreToolUse、PostToolUse、PermissionRequest、PostToolUseFailure、Stop。
- `Stop → idle` 是非终态，不设置完成时间或完成未读提醒；同 Session 后续输入可回到 `running`。
- 工具失败保持 `running`，不把单次工具失败解释为整个会话失败。
- 标题由首个 prompt 映射为固定安全类别；完整 prompt、命令、工具输入输出、完整路径或原始错误不进入手机快照。
- 手机只裁决本次权限请求。请求身份、签名、并发、重复答复和超时语义以
  [共享协议](../protocol/README.md)为准；Bridge/手机不可用时回到 ZCode 本地审批，不自动批准。
- Hook 安装、修复、卸载与恢复保留第三方配置，使用受权限保护的备份及指纹检查；恢复需正式双确认。

## GLM 数据来源与展示

现行链路：Mac Bridge 设置中的“配置 → ZCode → GLM 额度连接（可选）” → 系统钥匙串中的独立 Key →
BigModel 额度查询 → `UsageProviderSnapshot` → Android。Android 不保存或接收 GLM Key。

- 无 Key：不发起 GLM 额度请求、不发送空 GLM provider；顶栏不显示 GLM 块，详情页显示“未启用”。
- 有 Key：Bridge 启动、手机新连接、手动刷新及正常每 10 分钟轮询可触发查询；同一时间只运行一个请求，失败按协调器规则退避。
- 钥匙串访问与上游 Key 鉴权分开表达。普通刷新只尝试静默读取；权限不足或钥匙串锁定时，设置显示“需要钥匙串授权”，不自动发起交互授权。每 10 分钟静默重试，解锁或权限恢复后可继续更新。
- 旧 Key 需要授权时，输入新 Key 后的验证失败仍单独显示为“新 Key 错误”，不会被旧授权提示遮住；“授权读取”入口继续保留。只隐藏与钥匙串授权提示重复的通用错误。新 Key 验证并保存成功后，两类错误一并清除；验证失败不覆盖原 Key。
- “授权读取”是用户主动入口；系统授权后先复查静默读取，再立即查询额度。系统中的“始终允许”可保留该应用的访问权限；仅“允许”可能不足以支持后台持续读取，复查失败时不能报告可用。授权没有十分钟的有效期。
- 无法读取 Key 时不继续使用内存缓存的 Key；已有额度保留为陈旧数据，最后成功时间不前移；没有成功数据时显示不可用。Android 沿用现有 `stale_unavailable` / `unavailable` 状态，不新增协议字段。
- 授权能否跨 App 更新复用取决于签名身份。临时签名每次构建可能变化；稳定签名的本机启用与真实账号持续刷新必须另行验收，不能以测试通过或不弹窗替代。见 [钥匙串修复记录](updates/2026-08-31-glm-keychain-authorization.md)。
- 有可信窗口时：顶栏按 `GENERAL → SPARK → GLM` 展示，GLM 包含 5 小时与每周剩余比例；详情可切换 `CODEX / GLM`。
- 刷新失败、鉴权失败、套餐过期和额度耗尽分别表达；只有允许保留旧窗口的状态才显示最后可信值，并明确其陈旧/错误状态。缺失数据不伪造成 0% 或 100%。
- `percentage` 是上游已用比例；`remainingAmount` 保留上游独立 `remaining`，不能用总额减已用量重算。`level` 是不透明可选字段，套餐名默认“GLM Coding Plan”。完整字段与时间语义见共享协议。

Codex 的现行路径不同：[CodexUsageLoader](../macos/Sources/AgentGridCore/CodexUsageLoader.swift)
读取本地 Session JSONL 中已有的 `rate_limits`。ZCode 的本地 Token 统计不能代替套餐余额。
[无重复 Key Gate 记录](updates/2026-08-29-issue-12-no-duplicate-key-glm-quota-gate.md)
是指定版本和日期下的接入调查，不是对所有未来版本的结论，也不撤销现有独立 Key 实现的事实。

安全边界：只通过用户明确选择的 Bridge 配置入口管理 GLM Key；不扫描或复制 ZCode 的
OAuth、Cookie、provider 或私有缓存，不调用私有 Electron RPC。
真实凭据、配置写入、安装和恢复仍须单独授权；阅读本文不构成授权。
既有调研记录中的辅助查询政策、公开分发前官方确认与上游兼容风险仍未被“测试可用”消除。

## 实现与测试入口

| 范围 | 实现入口 | 自动化入口 |
| --- | --- | --- |
| ZCode 事件与状态 | [ZCodeHooks.swift](../macos/Sources/AgentGridCore/ZCodeHooks.swift)、[ZCodeReducer.swift](../macos/Sources/AgentGridCore/ZCodeReducer.swift) | [ZCodeHookTests](../macos/Tests/AgentGridCoreTests/ZCodeHookTests.swift)、[ZCodeReducerTests](../macos/Tests/AgentGridCoreTests/ZCodeReducerTests.swift) |
| Hook 配置与恢复 | [ZCodeHookConfiguration.swift](../macos/Sources/AgentGridCore/ZCodeHookConfiguration.swift) | [ZCodeHookConfigurationTests](../macos/Tests/AgentGridCoreTests/ZCodeHookConfigurationTests.swift) |
| 手机权限往返 | [HookBridgeServer.swift](../macos/Sources/AgentGridCore/HookBridgeServer.swift)、[TaskCatalog.swift](../macos/Sources/AgentGridCore/TaskCatalog.swift) | [ZCodeBridgeIntegrationTests](../macos/Tests/AgentGridCoreTests/ZCodeBridgeIntegrationTests.swift) |
| GLM 查询、凭据与刷新 | [GLMQuotaProvider.swift](../macos/Sources/AgentGridCore/GLMQuotaProvider.swift)、[GLMKeychainStore.swift](../macos/Sources/AgentGridCore/GLMKeychainStore.swift)、[GLMQuotaCoordinator.swift](../macos/Sources/AgentGridCore/GLMQuotaCoordinator.swift) | [GLMQuotaProviderTests](../macos/Tests/AgentGridCoreTests/GLMQuotaProviderTests.swift)、[GLMQuotaCoordinatorTests](../macos/Tests/AgentGridCoreTests/GLMQuotaCoordinatorTests.swift) |
| Bridge 生产接线 | [BridgeModel.swift](../macos/Sources/AgentGridBridge/BridgeModel.swift) | [BridgeModelGLMTests](../macos/Tests/AgentGridBridgeTests/BridgeModelGLMTests.swift)、[LocalBridgeEndToEndTests](../macos/Tests/AgentGridBridgeTests/LocalBridgeEndToEndTests.swift) |
| GLM 钥匙串授权 | [KeychainAccess.swift](../macos/Sources/AgentGridCore/KeychainAccess.swift)、[GLMKeychainStore.swift](../macos/Sources/AgentGridCore/GLMKeychainStore.swift) | [GLMKeyAccessTests](../macos/Tests/AgentGridCoreTests/GLMKeyAccessTests.swift)、[GLMKeychainStoreTests](../macos/Tests/AgentGridCoreTests/GLMKeychainStoreTests.swift) |
| Android 任务与额度 | [AgentGridScreen.kt](../android/app/src/main/java/com/agentgrid/mobile/ui/AgentGridScreen.kt)、[UsagePresentation.kt](../android/app/src/main/java/com/agentgrid/mobile/ui/UsagePresentation.kt)、[UsageDashboard.kt](../android/app/src/main/java/com/agentgrid/mobile/ui/UsageDashboard.kt) | [ZCodeTaskPresentationTest](../android/app/src/test/java/com/agentgrid/mobile/ui/ZCodeTaskPresentationTest.kt)、[UsagePresentationTest](../android/app/src/test/java/com/agentgrid/mobile/ui/UsagePresentationTest.kt)、[PhoneSessionTest](../android/app/src/test/java/com/agentgrid/mobile/network/PhoneSessionTest.kt) |

上述测试是已有可执行守则，不是每次阅读文档都会自动运行的检查。
修改逻辑后按 [macOS 开发流程](macos-development.md)运行 Swift 测试，按
[Android 开发流程](android-development.md)运行 JVM 测试、Lint 与构建；UI 先用 Compose Preview。
合成 provider、模拟器和本地 E2E 不替代真实服务与 Redmi 验收。
Windows 只保留协议解析与转发兼容；实际 Windows 验证仍按
[既有豁免记录](updates/2026-08-28-issue-3-cross-platform-protocol-compatibility.md)处理。

## 验收证据按来源读取

- 上游字段与豁免：[Gate 0 契约验证](updates/2026-08-28-zcode-glm-gate0-contract-validation.md)。
- ZCode 状态与配置：[Issue #4](updates/2026-08-28-issue-4-zcode-session-monitoring.md)、[Issue #5](updates/2026-08-29-issue-5-zcode-hook-hardening-and-recovery.md)。
- 真实手机权限往返：[Issue #6](updates/2026-08-29-issue-6-zcode-mobile-permission-relay.md)。
- GLM 独立 Key 路径与详情：[Issue #7](updates/2026-08-29-issue-7-glm-coding-plan-quota.md)、[可选连接收尾](updates/2026-08-29-issue-7-optional-glm-follow-up.md)、[Issue #8](updates/2026-08-29-issue-8-glm-quota-details.md)。
- 合成端到端和现场范围：[Issue #9](updates/2026-08-29-issue-9-cross-platform-integration-acceptance.md)、[Issue #10](updates/2026-08-29-issue-10-final-zcode-redmi-acceptance.md)。#10 当轮未验证真实 GLM Key 路径，该历史事实保留。
- 后续用户报告：[GLM 可用反馈及文档同步记录](updates/2026-08-31-zcode-glm-documentation-sync.md)。不能忽略此反馈，也不能把它提升为完整独立复验。
- Mac 重复授权修复：[固定签名与真实刷新验收](updates/2026-08-31-glm-keychain-authorization.md)。Build 15 的重启与两个真实十分钟周期通过。Build 16 已安装，初次升级未自动沿用真实 GLM 权限；用户选择“始终允许”后额度恢复，同版本重启后查询与通信测试通过，短时观察无再次授权弹窗。下次升级的授权复用、Build 16 两个十分钟周期及 Redmi 画面仍待验证；签名相同不能替代真实权限验收。

新验收应分别写明：代码/自动化、Agent 现场验证、用户反馈、未验证项。
涉及真实额度时需记录脱敏的构建版本、两个窗口及重置时间对照、手机展示和刷新结果，
不得保存 Key、原始响应、账号数据或未脱敏截图。变更后的最终构建未复验时应明确说明。

## 后续变更与任务状态

- 本文维护现行行为和阅读入口；稳定平台命令留在平台开发文档，单次结果写入 `updates/`，不覆盖旧验收的时点和范围。
- 原始无重复 Key 目标的变更需要用户明确确认；不能用“独立 Key 可用”或“无 Key 隐藏卡片”自动替代它。
- #12 的恢复条件与历史判断见 Gate 记录；继续任务前按 [Issue Tracker 规则](agents/issue-tracker.md)读取 GitHub 当前正文、评论与阻塞关系。本文不维护重复的活动队列，也不授权关闭 #12、#10 或 #1。
- 改动数据来源、Hook/权限、安全边界或验收口径时，同步本文、相关协议/测试与日期化记录；按根规则重新运行 `$claude-agents-bootstrap`。
