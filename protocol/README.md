# AgentPager 共享状态协议

AgentPager 的 macOS、Android 与 Windows 实现使用同一份 JSON 状态语义。Issue #3 只做向后兼容的字段扩展，消息 `version` 继续为 `1`；旧客户端和旧 Bridge 仍可使用既有 `usage` 字段。

## 状态快照扩展

`state.snapshot.payload` 现支持：

- `tasks[].source = "zcode"`：表示 ZCode 会话来源。
- `usage`：原有 Codex 单额度快照，继续保留，不能改名或删除。
- `usageProviders`：可选的多提供方额度列表。字段缺失表示 Bridge 尚未发送新模型，不表示额度为零。
- `pendingRequests[].requestID`：可选的待审批请求标识。旧来源没有唯一工具请求标识时允许缺失。

批准或拒绝控制消息可在 `payload.pendingRequestID` 携带上述请求标识。该字段为可选字段；缺失时保持现有按任务处理的兼容路径。

## 多提供方额度

每个 `usageProviders[]` 元素包含：

- `id`：开放字符串，例如 `codex`、`glm`。客户端不得把未知值当成解码错误。
- `displayName`、`planName`、`capturedAt`、`status`：可选展示或采集信息。
- `planLevel`：可选且不透明的上游原值。不能根据 `lite`、额度总量或其他数值推断套餐名称；没有单独验证的显示名时，GLM 的产品层回退名为 `GLM Coding Plan`。
- `quotaGroups`：开放的额度组列表。组 `id` 是字符串，未知组应被保留或忽略展示，不能让整条快照失败。

额度窗口沿用 `usedPercentage` 与 `remainingPercentage`，并可携带：

- `quotaType`：开放字符串；Gate 0 当前观察值为 `CREDIT_LIMIT`。
- `limitAmount`、`usedAmount`、`remainingAmount`：可选原始数值。
- `windowMinutes`、`resetsAt`：窗口长度与重置时间。

Gate 0 已确认：GLM 上游 `percentage` 表示已使用百分比；`remaining` 是服务端独立字段。适配器必须把服务端 `remaining` 原样投影为 `remainingAmount`，禁止用总量减已用量重算。所有协议时间继续使用 Unix 整数毫秒。

## 保守降级

- 未知 `AgentSource` 在各客户端映射为通用 `unknown`，任务仍保留在快照中。
- 未知 provider、quota group 和 `quotaType` 使用开放字符串承载，不新增封闭枚举。
- 缺失 `usageProviders` 时继续读取 `usage`；不得把缺失、错误或未知显示为 0% 或额度耗尽。
- 缺失新增可选字段时使用空列表、`null` 或现有任务默认值，不能让整条快照解析失败。
- `Stop` 只表示当前模型轮次结束；协议扩展本身不得据此把 ZCode 会话直接标记为成功终止。

Windows 在本阶段只解析、序列化和转发这些字段，不安装 ZCode Hook，也不查询 GLM。

## 兼容样本

- `fixtures/task-snapshot.json`：扩展前的 Codex 状态快照。
- `fixtures/task-snapshot-v2.json`：同时包含旧 `usage`、ZCode、多提供方额度和待审批请求标识的新快照。
- `fixtures/task-snapshot-unknown.json`：未知来源、未知提供方、未知额度组和缺失可选字段的降级样本。
