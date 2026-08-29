# ZCode 会话监控接入调研

> 历史调研记录：本文保存实现前判断，其中 `Stop → succeeded` 已被后续真实验证否定。
> 当前产品契约是非终态 `Stop → idle`，以
> [Issue #4 实施记录](2026-08-28-issue-4-zcode-session-monitoring.md)和
> [Issue #5 稳定化记录](2026-08-29-issue-5-zcode-hook-hardening-and-recovery.md)为准。

> 查询日期：2026-08-28
> 调研范围：让 AgentPager 像监控 Codex、Claude Code 一样，显示当前 ZCode 编码会话，并评估手机端批准、拒绝、回答和中断能力。
> 本轮只读调研，不安装 Hook、不修改 ZCode 配置、不运行 GLM 模型请求，也不修改 AgentPager 功能代码。

## 结论

可以先做，但不能一次承诺与 Codex、Claude Code 完全等价。

对用户当前在 ZCode 桌面 App 中发起的会话，推荐使用 **ZCode 官方 Hook 作为 MVP 主链路**：

```text
ZCode Desktop 原生会话
        ↓ 官方同步 Hook（stdin JSON / stdout JSON）
macOS AgentPager Bridge
        ↓ 现有局域网签名协议
Android AgentPager
```

这条路径能够可靠覆盖：

- 会话 ID、项目目录、用户 prompt；
- 开始、执行工具、工具成功/失败、准备结束；
- 当前工具和经过清洗的步骤摘要；
- 等待权限、从手机批准或拒绝权限。

第一版暂时不能承诺：

- 精确区分“正常完成”和“用户中断”；
- AskUserQuestion / Plan 审批等“等待回答”；
- 独立子代理 ID、每个子代理的开始/结束和用量；
- Hook 内直接得到精确 Token 用量；
- 从手机中断或重试一个由 ZCode Desktop 持有的会话。

ZCode 安装包还提供更丰富的 `app-server` stdio 协议，可读会话状态、消息、事件、Token、子代理，并可接收权限和用户输入。但当前没有发现把新的 `app-server` 进程“附着”到 ZCode Desktop 已经持有的实时 stdio 会话的官方机制。因此它适合未来由 AgentPager 自己启动并托管 ZCode 会话，不适合代替 Hook 监控用户现有的桌面会话。

### 可行性分级

| 目标 | 可行性 | 当前判断 |
| --- | --- | --- |
| 显示 ZCode 会话正在运行、当前工具、完成 | 高 | 官方 Hook 直接覆盖，仍需用本机真实新会话验证载荷 |
| 手机批准或拒绝 ZCode 工具权限 | 中高 | `PermissionRequest` Hook 支持返回 allow/deny；超时、Bridge 离线和本地弹窗并发需实测 |
| 显示 ZCode 标题和精确 Token | 中 | `app-server` 有 `session/list`、`session/usage`，但属于版本敏感的辅助通道 |
| 显示独立子代理生命周期 | 低（Hook）/高（自托管） | Hook 没有 SubagentStart/Stop；自托管 `app-server` 有子会话模型 |
| 手机回答 ZCode 问题或 Plan 审批 | 低（Hook）/高（自托管） | Hook 没有对应事件；`app-server` 有 `interaction/requestUserInput` |
| 手机中断现有 ZCode Desktop 会话 | 低 | Hook 没有反向 stop；`session/stop` 只对对应 `app-server` 持有的会话有明确语义 |

## 1. “ZCode” 的准确身份

本调研中的产品是智谱/Z.AI 官方 **ZCode**，不是 GitHub 上其他同名开源项目。官方中文产品页将它定义为“新一代氛围编程工具”，支持多智能体协作、Goal 长程任务和 Bot 控制；中文站套餐入口指向 BigModel.cn。查询日官网提供 ZCode 3.9.2 下载。[ZCode 官方中文页](https://zcode.z.ai/cn)

本机只读核实：

- App：`/Applications/ZCode.app`
- Bundle ID：`dev.zcode.app`
- App 版本：`3.9.2 (6069)`
- 内置 CLI：`zcode 0.16.5`
- 本机内置 CLI 文件 SHA-256：`780683d8f9c003c2e1b629214de7987c9a533cdc486ce0fa3e5f3f4d39ece184`

可复核的一手安装包文件：

- [ZCode Info.plist](</Applications/ZCode.app/Contents/Info.plist>)
- [内置 zcode.cjs](</Applications/ZCode.app/Contents/Resources/glm/zcode.cjs>)
- [内置 diagnosing-hooks 指南](</Applications/ZCode.app/Contents/Resources/glm/packages/zcode-guide-plugin/skills/diagnosing-hooks/SKILL.md>)

### GLM 接口协议不等于会话协议

BigModel 官方文档把 ZCode、Claude Code 等列为不同的 Coding Agent；GLM Coding Plan 提供的是 Anthropic Message 和 OpenAI Chat Completion 两种**模型调用端点**。[BigModel 接入工具](https://docs.bigmodel.cn/cn/guide/develop/others)

官方架构说明也明确把“模型”和 Agent 上层的上下文、工具调度、会话、Hook、子代理分开：大多数 Coding Agent 会在语言模型上再提供 Agent 运行框架。[Coding Agent 工作原理](https://docs.bigmodel.cn/cn/coding-plan/learning-resources/how-coding-agent-works)

因此：

- ZCode 调用 GLM 时兼容 Anthropic/OpenAI 协议，只说明“怎样请求模型”；
- 它不表示 ZCode 会话本身是 Claude Code 会话，也不自动继承 Claude Code Hook、日志或审批协议；
- ZCode 的会话采集必须对接 ZCode 自己的 Hook 或 `app-server`。

## 2. 官方 Hook：现有桌面会话的推荐主链路

### 2.1 官方确认的七个事件

查询日的官方插件开发文档与本机 3.9.2 内置指南都只支持以下七个事件：

1. `SessionStart`
2. `UserPromptSubmit`
3. `PreToolUse`
4. `PermissionRequest`
5. `PostToolUse`
6. `PostToolUseFailure`
7. `Stop`

官方文档给出的顺序是：新会话 → 用户提交 → 模型请求工具 → 必要时权限询问 → 工具成功/失败 → 模型准备停止。[ZCode 官方 Hook 开发指南，固定提交](https://github.com/zai-org/zcode-plugins/blob/e2d4b3ebecc795e8ba545283ce0e28e96493959c/docs/PLUGIN_DEVELOPMENT_CN.md#4-hooks-%E5%BC%80%E5%8F%91%E6%8C%87%E5%8D%97)

本机内置官方指南明确写明 `Notification`、`SubagentStop` 和 `PreCompact` 不受支持。由于也没有 `SessionEnd`、`SubagentStart`，不能直接照搬 Claude Code 的完整事件归约。

### 2.2 配置位置

官方支持三个来源：

- 用户级：`~/.zcode/cli/config.json`
- 工作区级：`<workspace>/.zcode/config.json` 或 `zcode.json`
- 插件：`hooks/hooks.json`

配置文件 Hook 默认关闭，必须设置 `hooks.enabled: true`；插件 Hook 随插件启用自动生效。新 Session 启动时会捕获一份 Hook 配置快照，变更配置后需要新建 Session 验证。[官方插件开发教程](https://github.com/zai-org/zcode-plugins/blob/e2d4b3ebecc795e8ba545283ce0e28e96493959c/docs/PLUGIN_DEVELOPMENT_CN.md)

AgentPager 是个人跨项目工具，实施时优先建议用户级配置，但必须像现有 Codex/Claude Code 安装器一样：

- 保留所有既有字段和第三方 Hook；
- 只追加或更新 AgentPager 自己管理的条目；
- 修改前创建可恢复备份；
- 卸载时只删除 AgentPager 条目；
- 新建 ZCode Session 做加载验证。

### 2.3 Hook 能得到什么

ZCode 会向 Hook stdin 写入一行 JSON。官方公开示例包含：

- `session_id`
- `transcript_path`
- `cwd`
- `permission_mode`
- `hook_event_name`
- `tool_name`
- `tool_input`
- `tool_use_id`

事件专有字段包括：

- `SessionStart`：`source`，可选 `agent_type`、`model`
- `UserPromptSubmit`：`prompt`
- `PreToolUse`：工具名、工具输入、调用 ID
- `PermissionRequest`：工具和权限建议
- `PostToolUse`：结构化工具响应
- `PostToolUseFailure`：错误与是否中断
- `Stop`：`stop_hook_active`、最后一条助手消息

`transcript_path` 是 Hook 执行期可读的**临时 JSONL**，Hook 结束后 ZCode 会清理临时目录。官方明确要求插件长期数据写到 `ZCODE_PLUGIN_DATA`，因此 AgentPager 不能像 Codex rollout 一样长期跟踪这个路径。[官方 stdin 契约](https://github.com/zai-org/zcode-plugins/blob/e2d4b3ebecc795e8ba545283ce0e28e96493959c/docs/PLUGIN_DEVELOPMENT_CN.md#45-stdin-%E8%BE%93%E5%85%A5%E5%A5%91%E7%BA%A6)

### 2.4 手机批准/拒绝为什么可做

`PermissionRequest` Hook 是同步本地子进程协议。Hook 可通过 stdout 返回：

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "allow"
    }
  }
}
```

把 `behavior` 改为 `deny` 即拒绝；允许时还能更新工具输入或权限规则，但 AgentPager MVP 不应开放这些高风险能力。[官方 PermissionRequest 返回契约](https://github.com/zai-org/zcode-plugins/blob/e2d4b3ebecc795e8ba545283ce0e28e96493959c/docs/PLUGIN_DEVELOPMENT_CN.md#permissionrequest%E8%87%AA%E5%8A%A8%E5%85%81%E8%AE%B8%E6%88%96%E6%8B%92%E7%BB%9D%E6%9D%83%E9%99%90%E8%AF%A2%E9%97%AE)

推荐流程：

```text
ZCode PermissionRequest
        ↓ Hook 保持等待
Bridge 创建 PendingRequest
        ↓ 局域网签名消息
Android 显示“批准 / 拒绝”
        ↓
Bridge 返回 allow / deny JSON
        ↓
ZCode 继续或拒绝工具
```

边界：

- Bridge 不在线时 Hook 应快速无输出退出，让 ZCode 回到自己的本地审批体验，不能卡死会话；
- 第一次实现只允许“本次允许”和“本次拒绝”，不远程写永久权限规则；
- 必须用 `session_id + tool_use_id` 标识请求，不能只按 Session ID 保存，以免同一会话并发权限请求互相覆盖；
- Hook 超时、手机断线、ZCode 本地弹窗与手机回答同时发生时的先到先得行为，需要真实会话验证后才能定超时值。

### 2.5 Hook MVP 状态映射

| ZCode 事件 | AgentPager 状态 | 可展示内容 | 可靠性边界 |
| --- | --- | --- | --- |
| `SessionStart` | `starting` / `running` | 项目、模型、来源 | 没有独立 SessionEnd |
| `UserPromptSubmit` | `running + thinking` | 用户 prompt、由首条 prompt 生成的临时标题 | 不是 ZCode 官方标题 |
| `PreToolUse` | `running + activity` | 工具名、清洗后的命令/路径/查询摘要 | 不能发送完整敏感输入 |
| `PermissionRequest` | `waitingApproval` | 工具与脱敏摘要，批准/拒绝按钮 | 需同步 Hook 等待 |
| `PostToolUse` | `running + thinking` | 当前工具完成 | 不传完整工具输出 |
| `PostToolUseFailure` | `running` 或保守标记异常步骤 | 错误类别的简短摘要 | 单次工具失败不等于 Session 失败 |
| `Stop` | `succeeded` | 完成提示、结束时间 | 尚不能可靠区分用户中断 |

## 3. 支持/不支持矩阵

| AgentPager 希望获得的能力 | 官方 Hook | 独立 `app-server` | MVP 结论 |
| --- | --- | --- | --- |
| Session ID | 支持 | 支持 | 支持 |
| 项目目录/项目名 | `cwd` 支持 | workspace 支持 | 支持 |
| 用户 prompt | 支持 | messages/events 支持 | 支持，但仅传必要摘要 |
| ZCode 官方标题 | 不直接提供 | `session/list` 提供 | 第一版用 prompt 派生，后续可补 |
| 当前步骤/工具 | Pre/PostToolUse 支持 | 事件流支持 | 支持 |
| running | 支持 | 支持 | 支持 |
| waiting approval | 支持 | 支持 | 支持 |
| completed | `Stop` 支持 | 支持 | 支持 |
| interrupted | 不精确 | 支持 turn/session 事件 | 现有桌面会话暂不承诺 |
| waiting answer | 没有专门事件 | `interaction/requestUserInput` | 现有桌面会话暂不支持 |
| 精确 Token | 不提供 | `session/usage` 支持 | 可作为后续版本敏感增强 |
| 独立子代理 | 无 Start/Stop，仅可看到 `Agent` 工具 | `session/subagents` 支持 | MVP 只显示主会话“正在协作” |
| 手机批准/拒绝 | `PermissionRequest` 可返回 | 反向 interaction 可返回 | Hook MVP 可做，需实机验证 |
| 手机回答问题/Plan | 无对应 Hook | 反向 user input 支持 | 仅自托管路线可做 |
| 手机中断 | 无反向控制 | `session/stop` | 仅自托管路线可做 |
| 手机重试 | 无反向控制 | 可通过 send/goal 等组合实现 | 不纳入 MVP |

## 4. `app-server`：能力很强，但不是现有桌面会话的主链路

### 4.1 本机官方安装包确认的能力

本机内置 CLI 帮助把它称为 `ZCode Protocol stdio app server`。其 NDJSON stdio 方法包含：

- `session/create`、`session/resume`、`session/list`
- `session/read`、`session/messages`、`session/events`
- `session/subscribe`、`session/send`、`session/stop`
- `session/subagents`、`session/usage`
- `interaction/requestPermission`
- `interaction/requestUserInput`

安装包内 schema 显示，会话状态枚举为 `idle / running / waiting / paused / completed / error`；快照还包含当前 turn、待审批、活动工具、背景任务、目标和 Token 计数。权限请求可返回 allow/deny/escalate/modify，用户输入可返回 accept/decline/cancel。

这些属于对当前 3.9.2 安装包源码的**源码推断**，还不是承诺长期兼容的独立公开 SDK。事实来源是本机固定哈希的 [zcode.cjs](</Applications/ZCode.app/Contents/Resources/glm/zcode.cjs>)。

### 4.2 本轮只读协议探针结果

未调用模型、未消费 Coding Plan 额度，只启动短生命周期 `app-server` 并发送只读 NDJSON 请求：

- `session/list` 可列出持久化会话；返回 Session ID、workspace、title、mode、kind、status、创建/更新时间；
- `session/usage` 对未激活会话也能返回输入、输出、推理、缓存 Token 和模型请求数；
- `session/subagents` 可返回 running、ended、childSessionIds；
- 新启动的 `app-server` 对未在该进程激活的 Session 执行 `session/read/messages/events` 时返回 `Session is not active`。

最后一条很关键：`app-server` 是一个需要自己持有 Session runtime 的 stdio 进程。查询日没有找到官方提供的 socket、HTTP、WebSocket 或“attach to desktop host”入口，可以让 AgentPager 接管 ZCode Desktop 当前进程的实时事件流。

因此不能把“协议里存在 `session/subscribe`”直接写成“可以监听用户当前 ZCode Desktop 会话”。如果由 AgentPager 自己启动 `app-server`、创建或 resume 会话，它才可以完整拥有订阅、审批、回答和 stop 流程；这已经是新的 ZCode 执行入口，而不仅是监控功能。

### 4.3 后续可接受的辅助用途

在版本匹配和失败降级前提下，可考虑：

- `Stop` 后用 `session/usage` 补充精确 Token；
- 用 `session/list` 按 Hook 的 Session ID 补充官方标题；
- 接口不兼容时仅隐藏增强字段，不能把 Session 误报为 0 Token、完成或离线。

不建议第一版让 Bridge 长期 resume ZCode Desktop 会话，只为读取实时状态。它可能引入双进程持有、锁竞争、状态漂移或改变更新时间，超出“只监控”的产品边界。

## 5. SQLite、JSONL 和进程/窗口观察

### 5.1 本地确实有数据，但属于私有实现

本机 3.9.2 当前存在：

- `~/.zcode/v2/tasks-index.sqlite`
- `~/.zcode/cli/db/db.sqlite`
- `~/.zcode/cli/log/zcode-YYYY-MM-DD.jsonl`
- `~/.zcode/cli/rollout/model-io-*.jsonl`

只读 schema 观察显示数据库包含 session、message、part、permission、turn/model/tool usage、session input、session target、session/subagent link 等表。它在技术上能提供标题、消息、Token、子代理与工具状态。

但是官方当前只把 Hook 与 `app-server` 暴露为执行协议，没有公开承诺这些数据库表、列、迁移和日志事件是稳定第三方 API。因此直接读库只能算**私有格式回退**，不能作为长期主链路。

### 5.2 隐私风险

本机 rollout JSONL 的结构含完整模型请求、messages、tool names、response text、usage 和 headers；数据库也保存 prompt、message 和工具使用详情。即使只读，也有把源代码、命令、内部路径或认证请求头误传到手机的风险。

MVP 必须坚持：

- 不读取或传输完整 rollout；
- 不把完整 prompt、工具输入、工具输出落到 AgentPager 持久快照；
- 复用 `ToolStepSanitizer` 清洗命令、路径和包装标记；
- Android 只接收项目名、短标题、状态、活动类型、必要审批摘要；
- 日志或 schema 变化时显示“暂不可用”，不能猜字段。

### 5.3 进程与窗口只能做存活探针

检查 `ZCode`、`zcode-host-local-*`、`zcode-cli` 进程只能证明 App/宿主仍在运行，无法映射：

- 当前哪个 Session 正在工作；
- 是 running、waiting approval 还是 waiting answer；
- 工具、Token、子代理和结束原因；
- 如何把批准结果准确送回对应请求。

Accessibility、OCR 或窗口标题观察还会受到焦点、语言、UI 改版和多窗口影响，只能用于诊断 App 是否启动，不能作为会话事实来源。

## 6. 与 AgentPager 现有架构的对照

当前 Bridge 已有适合扩展的主干，但 ZCode 不能被伪装成 Claude Code：

- [HookEnvelope.swift](../../macos/Sources/AgentGridCore/HookEnvelope.swift) 的 `HookSource` 目前只有 `codex`、`claude`；
- [HookBridgeServer.swift](../../macos/Sources/AgentGridCore/HookBridgeServer.swift) 只解码 Codex/Claude，并按来源生成权限 stdout；
- [TaskCatalog.swift](../../macos/Sources/AgentGridCore/TaskCatalog.swift) 只接受 Codex Hook、Claude Hook 和 Codex rollout；
- [Domain.swift](../../macos/Sources/AgentGridCore/Domain.swift) 的来源只有 `codexDesktop / codexCLI / claudeCode`；
- [Android Models.kt](../../android/app/src/main/java/com/agentgrid/mobile/domain/Models.kt) 和 [AgentGridScreen.kt](../../android/app/src/main/java/com/agentgrid/mobile/ui/AgentGridScreen.kt) 同样没有 ZCode 来源和徽标；
- Codex 的 [CodexRolloutObservation.swift](../../macos/Sources/AgentGridCore/CodexRolloutObservation.swift) 会长期观察 `~/.codex/sessions`，但 ZCode Hook transcript 是临时文件，不能照搬。

### 推荐的最小实现边界

后续如果用户批准开发，建议分成三个小阶段：

#### 阶段 A：只显示状态

- 新增 `HookSource.zcode` 和 `AgentSource.zcode`；
- 单独定义 `ZCodeHookPayload`、`ZCodeEventReducer`；
- 新增备份优先、只管理自身条目的 `ZCodeHookConfiguration`；
- 映射七个事件，Android 增加 ZCode 徽标和来源文案；
- Bridge 离线时 Hook 快速返回，不影响 ZCode 本地工作；
- 不读取 SQLite、rollout，也不做反向控制。

#### 阶段 B：手机批准/拒绝

- 用 `session_id + tool_use_id` 建立 PendingRequest；
- 只支持本次 allow/deny；
- 明确超时、重复回答、断线、ZCode 本地回答的收敛规则；
- 复用现有签名、序列号、nonce 和重放防护；
- 用真实 ZCode Desktop 新 Session + Android 真机做端到端验收。

#### 阶段 C：版本敏感增强

- 对确认兼容的 CLI 版本调用 `session/list`、`session/usage`；
- 补标题和 Token；
- 失败时降级到 Hook 基础卡片；
- 是否开展 AgentPager 自托管 `app-server` 会话作为独立产品功能，另行立项和确认。

不建议把 app-server、自读 SQLite、子代理完整建模和手机回答一次塞进 MVP；它们有不同的稳定性和权限边界，拆开才能验证每一层的真实效果。

## 7. 开发前必须做的最小真实验证

本轮没有改 ZCode 配置，所以以下仍是“待实机验证”，不能由源码推断替代：

1. 备份 `~/.zcode/cli/config.json`，只添加一个临时、只写脱敏字段的 user Hook。
2. 新建 ZCode Desktop Session，分别触发七个事件。
3. 核对真实 payload 的字段、工具命名、Session ID 稳定性和 Stop 行为。
4. 在非 yolo 模式触发一次无破坏权限请求，验证本地 UI 与 Hook 的先后关系。
5. 分别验证手机 allow、deny、超时、Bridge 未启动、手机断线。
6. 触发一次 Agent/子代理工具，确认 Hook 只能观察父工具还是还带子会话信息。
7. 用同一 Session ID 只读查询 `session/list`、`session/usage`，确认与桌面会话一致。
8. 删除临时 Hook，恢复备份，并核对用户原有 Hook 与插件均未变化。

这一步会修改用户的 ZCode Hook 配置并产生真实会话，必须单独取得确认后再执行。

## 8. 开放问题

- 用户准备监控的是 ZCode Desktop 原生 Agent，还是也希望未来从 AgentPager 新建并控制 ZCode 会话？本调研默认前者。
- `Stop` 在用户主动中断、模型错误和正常结束时的真实差异是什么？
- ZCode Desktop 3.9.2 的 `PermissionRequest` 是否允许 Hook 长时间等待，而不先由本地 UI 抢答？
- `AskUserQuestion`、Plan 审批是否会经过现有七个 Hook 中任一事件，还是只存在于 app-server interaction？
- `Agent` 工具 Hook 是否携带可稳定关联的 child Session ID？官方 Hook 文档没有承诺。
- `session/list` / `session/usage` 是否会在后续 CLI 版本保持兼容？目前未找到独立公开版本承诺。
- 中国 BigModel 账号登录的 ZCode 与国际 Z.AI 账号在本地 Session/Hook 协议上是否完全一致？本机 3.9.2 需要真实新会话确认。

## 9. 一手来源

- [ZCode 官方中文产品页](https://zcode.z.ai/cn)
- [BigModel：接入工具与模型协议](https://docs.bigmodel.cn/cn/guide/develop/others)
- [BigModel：Coding Agent 工作原理](https://docs.bigmodel.cn/cn/coding-plan/learning-resources/how-coding-agent-works)
- [ZCode 官方插件市场](https://github.com/zai-org/zcode-plugins)
- [ZCode 官方插件开发教程，固定提交 e2d4b3e](https://github.com/zai-org/zcode-plugins/blob/e2d4b3ebecc795e8ba545283ce0e28e96493959c/docs/PLUGIN_DEVELOPMENT_CN.md)
- [本机 3.9.2 内置 diagnosing-hooks 指南](</Applications/ZCode.app/Contents/Resources/glm/packages/zcode-guide-plugin/skills/diagnosing-hooks/SKILL.md>)
- [本机 3.9.2 内置 zcode.cjs](</Applications/ZCode.app/Contents/Resources/glm/zcode.cjs>)

说明：GitHub Issue、第三方逆向项目和博客没有作为本调研关键结论的事实来源。`app-server`、SQLite 和日志部分只采用当前官方安装包与本机只读探针，并明确标为源码推断或私有格式，不把它们描述成官方长期兼容承诺。
