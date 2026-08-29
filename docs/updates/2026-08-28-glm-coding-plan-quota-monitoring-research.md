# 2026-08-28 GLM Coding Plan 额度监控调研

> 历史调研记录：本文保留 Gate 0 之前的方案判断。当前响应契约以
> [Gate 0 验证](2026-08-28-zcode-glm-gate0-contract-validation.md)为准；当前无重复 Key
> 接入结论以 [Issue #12 Gate](2026-08-29-issue-12-no-duplicate-key-glm-quota-gate.md)
> 为准，后者目前未通过。本文不作为现行验收清单。

## 调研范围

- 目标：判断 AgentPager Android 能否安全、持续地显示用户在中国站 `bigmodel.cn` 订阅的 GLM Coding Plan 已用量、剩余额度、刷新周期和模型/时间窗限制。
- 查询日期：2026-08-28（UTC+8）。
- 资料边界：只采用智谱官方文档、智谱官方页面和 `zai-org` 官方源码；没有把第三方监控工具或社区逆向结果当成事实来源。
- 本轮只做调研和方案判断，没有读取用户的 API Key、没有调用用户账户的用量数据、没有修改 AgentPager 功能代码。

## 结论

可以做，但当前最稳妥的定义应是“实验性额度读取”，还不能把它当成有版本承诺的公开 OpenAPI 集成。

官方已经提供两条确定可用的查看路径：

1. 登录后的[个人用量统计页面](https://www.bigmodel.cn/coding-plan/personal/usage)。官方文档明确说这里可查看当前消耗进度和剩余额度；这是用户人工查看时最权威的入口，但页面依赖 JavaScript 和登录状态，不适合 Android App 抓页面。[套餐 FAQ](https://docs.bigmodel.cn/cn/coding-plan/faq)
2. 智谱官方 `glm-plan-usage` Claude Code 插件。官方文档说明它可以查询当前配额和使用统计，且目前仅支持个人版套餐。[官方插件说明](https://docs.bigmodel.cn/cn/coding-plan/extension/usage-query-plugin)

官方插件源码进一步公开了中国站实际使用的三个读取接口：

- `GET https://open.bigmodel.cn/api/monitor/usage/quota/limit`
- `GET https://open.bigmodel.cn/api/monitor/usage/model-usage?startTime=...&endTime=...`
- `GET https://open.bigmodel.cn/api/monitor/usage/tool-usage?startTime=...&endTime=...`

它使用 Coding Plan 的 `ANTHROPIC_AUTH_TOKEN`，以裸值放入 `Authorization` 请求头（不是源码中的 `Bearer ...` 形式）；`model-usage` 和 `tool-usage` 附带 `startTime`、`endTime`，`quota/limit` 不附带时间参数。[官方插件固定提交源码](https://github.com/zai-org/zai-coding-plugins/blob/0446d0bb0bc537d97d3ab3664c4b8b9c4a0e1254/plugins/glm-plan-usage/skills/usage-query-skill/scripts/query-usage.mjs)

关键限制是：这些路径虽然由官方插件实际调用，但本次没有在智谱公开 API Reference 中找到独立的接口说明、响应 Schema、版本策略或兼容性承诺。现有官方源码也停留在 2026-02-22，而当前套餐文档已经切换为“积分”口径。因此，适合在 AgentPager 中做成可降级的供应商适配器，不适合把字段和路径硬编码成永远不变的协议。

## 当前套餐事实

截至查询日，个人套餐的公开额度是：

| 套餐 | 5 小时积分 | 每周积分 |
| --- | ---: | ---: |
| Lite | 2,000 | 10,000 |
| Pro | 12,000 | 60,000 |
| Max | 28,000 | 140,000 |

刷新规则不是简单的“每天固定几点清零”：

- 5 小时额度采用动态刷新；一笔请求消耗的积分在 5 小时后恢复。
- 周额度从套餐下单时起，以 7 天为一个周期刷新。
- 所有当前个人套餐支持 GLM-5.3 和 GLM-5.3-Flash；部分历史模型名会自动映射到这两个模型。
- 工作日 14:00–18:00（UTC+8）是高峰时段；非高峰时段按基础积分消耗的 50% 抵扣。
- 模型与 MCP 工具目前按同一积分公式扣减。模型积分同时受输入 Token、缓存命中 Token、输出 Token、模型系数和高/低峰时段影响，不能只累计“总 Token”反推准确剩余额度。

以上均来自当前[个人套餐概览](https://docs.bigmodel.cn/cn/coding-plan/overview)。

还要兼容历史套餐。官方说明曾存在“无周限额”的老套餐，旧权益可以持续到当期结束，之后再迁移到新套餐。因此，不能只根据 Lite/Pro/Max 名称就在客户端写死一定有周额度；需要以当前账号返回的数据为准。[老套餐迁移与补偿说明](https://docs.bigmodel.cn/cn/coding-plan/transition)

## 可观测方式对比

| 方式 | 能得到什么 | 能否作为 AgentPager 主数据源 | 主要限制 |
| --- | --- | --- | --- |
| 官方用量统计页 | 官方确认可查看消耗进度和剩余额度 | 否，适合作为人工核对和失败回退 | 依赖登录和 JavaScript；抓页面、复用 Cookie 都脆弱且扩大凭据风险 |
| 官方 `glm-plan-usage` 插件 | 当前配额、模型用量、工具用量 | 可以作为实现依据 | 仅明确支持个人版；接口未形成公开稳定 OpenAPI 合同 |
| `quota/limit` | 官方插件读取配额百分比；旧源码认识 `TOKENS_LIMIT` 和 `TIME_LIMIT` | 推荐作为额度卡片的首选候选 | 当前“积分制”响应类型和字段仍需用用户实际套餐脱敏确认；不能假设旧 Schema 永远成立 |
| `model-usage` | 官方插件查询指定时间段的模型使用统计并原样输出 `data` | 可做明细/趋势的候选 | 官方源码没有定义返回字段 Schema，也没有说明允许的最大时间跨度和时区合同 |
| `tool-usage` | 官方插件查询指定时间段的工具使用统计 | 可做 MCP 明细的候选 | 同样没有公开 Schema 和版本保证 |
| 标准模型响应中的 `usage` | 单次请求的输入、输出、缓存命中和总 Token | 只能做本地辅助统计 | 不返回套餐剩余额度或周/5 小时窗口；也不能覆盖别的客户端产生的消耗。[官方响应字段](https://docs.bigmodel.cn/api-reference/%E6%A8%A1%E5%9E%8B-api/%E6%9F%A5%E8%AF%A2%E5%BC%82%E6%AD%A5%E7%BB%93%E6%9E%9C) |
| 429/业务错误 | 额度真正耗尽时，`1308`、`1310` 等错误可包含 `next_flush_time`；`1309` 表示套餐过期，`1311` 表示模型无权限 | 只适合作为兜底状态 | 只能在失败后知道，不能提前显示连续进度。[官方错误码](https://docs.bigmodel.cn/cn/api/api-code) |
| 本地日志累计 Token | 可估算当前 AgentPager 观察到的会话消耗 | 不应作为官方余额 | 看不到其他工具的消耗，且积分还受模型、缓存、输出和时段系数影响 |

## 官方插件源码与当前套餐之间的差异

这部分是实现前最重要的兼容性风险：

- 官方插件源码把 `TOKENS_LIMIT` 显示为 `Token usage(5 Hour)`，只保留 `percentage`。
- 对 `TIME_LIMIT`，源码显示为 `MCP usage(1 Month)`，保留 `percentage`、`currentValue`、`usage` 和 `usageDetails`。
- 同一源码会原样返回它不认识的其他类型，但没有为当前积分制定义专门映射。
- 当前 2026-08-28 套餐文档改为 5 小时积分和每周积分，并把模型与 MCP 纳入同一积分抵扣公式；当前公开套餐页没有承诺一条独立的“每月 MCP 额度”。

因此，“MCP 月额度”只能描述为旧官方插件源码支持的一种历史响应类型，不能在 Android UI 中写成当前套餐的固定权益。上线前应以用户账户的实际脱敏响应和当前控制台显示为准。

## 对 AgentPager 的推荐架构

推荐让 macOS AgentPager Bridge 查询额度，Android 端只接收经过裁剪的状态，不让 GLM API Key 进入手机：

```text
BigModel 官方监控接口
          |
          | HTTPS + Coding Plan API Key
          v
macOS AgentPager Bridge
  - Key 留在 Mac 的安全存储/既有配置
  - 兼容多种额度类型和未知字段
  - 只输出已用%、剩余值、窗口、刷新时间、更新时间、错误状态
          |
          | 现有可信局域网 WebSocket
          v
AgentPager Android
  - 显示额度卡片
  - 手动刷新
  - 数据过期/接口变化时显示“暂不可用”，不显示 0
```

这样做的产品效果是 Android 可以看到 GLM 额度，但手机丢失、日志导出或 App 数据泄露时不会直接暴露可调用模型的 Key。它也符合 AgentPager 现有“Mac Bridge + 局域网 Android”的边界，不需要新增云后端。

不推荐以下方案：

- Android 直接保存 API Key 并请求 BigModel：凭据暴露面更大，且会把未公开接口兼容逻辑复制到两端。
- 在 Android WebView 登录 BigModel 并抓页面：Cookie、验证码、页面结构和登录策略都可能变化。
- 为了测额度主动调用模型：会额外消耗额度，且只能得到单次 Token。
- 只解析 429：用户只有在已经用尽后才收到信息。

## 实施前必须完成的最小验证

1. 确认用户当前是个人版还是团队版、套餐等级、下单/迁移状态。官方插件文档目前明确只支持个人版。
2. 在用户明确同意后，由 Mac 使用现有 Coding Plan Key 对三个官方插件接口各查询一次；只保存脱敏后的字段名、类型和数值范围，不记录 Key 或完整响应。
3. 对 `quota/limit` 至少确认：
   - 当前额度类型名称；
   - 5 小时和每周窗口如何区分；
   - `percentage` 是已用还是剩余；
   - 是否存在总量、已用、剩余和精确刷新时间；
   - 没有用量或字段缺失时的返回形态。
4. 将同一时刻结果与官方用量统计页人工对照，确认百分比方向、积分数和刷新时间。
5. 用未知额度类型、字段缺失、401、403、429、5xx 和超时做契约测试；未知响应必须显示“额度数据暂不可用”，不能误报为 0% 或 100%。
6. 初版采用手动刷新加低频轮询；在官方没有公布查询频率上限前，不做秒级刷新。网络错误使用退避重试，不能让额度查询阻塞 AgentPager 的任务状态同步。

## 待确认项

- 用户当前套餐具体版本与等级，以及是否仍处于历史套餐/迁移权益。
- 2026-08-28 中国站个人套餐对 `quota/limit` 的实际响应 Schema。
- 返回数据是否包含可直接使用的精确剩余额度和 `nextResetTime`；官方公开源码只可靠证明了百分比读取，不能证明所有当前账号都有这些字段。
- `model-usage`、`tool-usage` 的时区、最大查询范围、分页/聚合规则和刷新延迟。
- 智谱是否愿意把监控接口作为第三方 App 的正式集成合同；若需要长期公开分发，建议在开发前向官方工单确认允许的使用方式和频率。
- 团队版监控所需的组织/项目上下文。当前官方插件明确只支持个人版，不能直接把个人版结论外推到团队版。

## 一手来源

- [GLM Coding Plan 套餐概览](https://docs.bigmodel.cn/cn/coding-plan/overview)
- [GLM Coding Plan 使用须知](https://docs.bigmodel.cn/cn/coding-plan/usage-notes)
- [GLM Coding Plan 常见问题](https://docs.bigmodel.cn/cn/coding-plan/faq)
- [GLM Coding Plan 快速开始](https://docs.bigmodel.cn/cn/coding-plan/quick-start)
- [官方用量查询插件说明](https://docs.bigmodel.cn/cn/coding-plan/extension/usage-query-plugin)
- [官方 `query-usage.mjs` 固定提交源码](https://github.com/zai-org/zai-coding-plugins/blob/0446d0bb0bc537d97d3ab3664c4b8b9c4a0e1254/plugins/glm-plan-usage/skills/usage-query-skill/scripts/query-usage.mjs)
- [智谱官方 API 错误码](https://docs.bigmodel.cn/cn/api/api-code)
- [老套餐迁移与补偿说明](https://docs.bigmodel.cn/cn/coding-plan/transition)
- [订阅及自动续费协议](https://docs.bigmodel.cn/cn/terms/subscription-agreement)
