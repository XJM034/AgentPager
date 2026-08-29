# Issue #12：无需重复 Key 的 GLM 额度接缝 Gate 调研

日期：2026-08-29

范围：GitHub [Issue #12](https://github.com/XJM034/AgentPager/issues/12)。本轮只读取当前安装版本的公开元数据、CLI 帮助和安装包内严格限定的协议注册/处理器元数据，并核对 ZCode、Z.ai、智谱官方文档、官方公开仓库固定提交和公开 OpenAPI；没有读取 ZCode OAuth、Cookie、provider 配置、登录缓存、Key 或 `coding-plan-cache` 内容，没有启动 app-server、调用协议方法或探测私有 Electron RPC，没有调用真实 GLM 额度接口，也没有修改 ZCode、Bridge、Android、Redmi 或任何端口状态。

## 结论摘要

**Gate 未通过。**

截至 2026-08-29，在当前安装的 ZCode Desktop `3.10.1` / CLI `0.16.5` 以及本轮核对的最新官方公开资料中，仍没有找到一种同时满足以下条件的接缝：

- 公开、受支持并有稳定机器可读契约；
- 复用 ZCode 已有账号登录状态；
- 不要求用户向 AgentPager 或另一个本地进程重复提供 Coding Plan Key；
- AgentPager 不接触 OAuth、Cookie、Token、Key 或 provider 内容；
- 能输出 5 小时与每周窗口、重置时间、采集时间和可区分的错误状态。

本轮发现的最新变化是 ZCode 官方文档已经更明确地说明：账号授权成功后，ZCode 会直接应用该账号的 Coding Plan 和额度；Usage Stats 会读取远端 Z.ai / BigModel 套餐统计，并在 `3.8.1+` 展示额度重置卡片。这个变化证明 ZCode 宿主内部拥有所需数据，但官方仍只把它作为 ZCode UI 能力发布，没有同步发布第三方只读 CLI、app-server quota 方法、Hook 字段、插件宿主 API 或本地快照 Schema。[Connect Models & Plans](https://zcode.z.ai/en/docs/configuration) [Usage Stats](https://zcode.z.ai/en/docs/usage-stats)

因此：

- 现有 Keychain provider 仍是“用户另行提供 Key”的可选连接，不是本 Gate 的无重复 Key 方案；
- “无 Key 时隐藏 GLM 卡片”不能视为原始目标完成；
- #12、被其阻塞的 #10，以及父 Issue #1 均应继续保持 **OPEN**；
- 当前没有可执行原型。任何未来原型都必须等官方新增接缝后另行说明读取、修改与恢复边界，并等待用户明确授权。

## 当前版本与调查边界

### 本机只读确认

| 项目 | 结果 |
| --- | --- |
| ZCode Desktop | `3.10.1` |
| Bundle build | `3.10.1.6272` |
| 内置 CLI | `0.16.5` |
| CLI 入口 SHA-256 | `3597160465b67da248fa3fb919920ca30d4e093003a4d70cde2a2e33903cbabc` |
| 分支 / HEAD | `alexx_custom` / `76c14e507c54aedebc21c906c11860916b284e9c` |
| 与 `origin/alexx_custom` | `0 / 0` |

只读命令范围：读取 `/Applications/ZCode.app/Contents/Info.plist` 的版本字段，计算公开 CLI 入口文件哈希，运行 `zcode --version`、`zcode --help` 及 `app-server`、`commands`、`plugins`、`skills` 的 `--help`，并在同一固定哈希 CLI 入口中只定位 `usage/stats`、`session/usage` 及其直接处理器。没有运行 `login`、`logout`、app-server、任何 prompt、插件、Hook、provider、额度命令或协议方法。

当前版本与 2026-08-29 旧调研记录中的 `3.10.1 / 0.16.5` 相同，没有版本变化可推翻旧版 CLI 结论。官方网页属于持续更新页面，本记录按 2026-08-29 访问结果判断；可固定的源码证据使用 Git 提交链接。

### 固定官方源码版本

- ZCode 官方插件仓库：[`zai-org/zcode-plugins@e2d4b3ebecc795e8ba545283ce0e28e96493959c`](https://github.com/zai-org/zcode-plugins/commit/e2d4b3ebecc795e8ba545283ce0e28e96493959c)，提交时间 2026-08-27。
- Z.ai 官方 Coding 插件仓库：[`zai-org/zai-coding-plugins@0446d0bb0bc537d97d3ab3664c4b8b9c4a0e1254`](https://github.com/zai-org/zai-coding-plugins/commit/0446d0bb0bc537d97d3ab3664c4b8b9c4a0e1254)，提交时间 2026-02-22。

## 已知旧结论与本轮复核重点

旧调研 [ZCode / GLM 额度无重复 Key 接入调研](2026-08-29-zcode-glm-quota-no-key-research.md) 已排除以下路径，本轮没有把它们重新包装成新方案：

1. 旧版 CLI 没有 `quota`、`usage`、`usage-stats` 或账户额度 JSON 命令。
2. Hook 七类事件没有套餐额度或 rate-limit 字段。
3. `coding-plan-cache` 没有官方公开路径与 Schema；本轮遵守新边界，没有打开或解析其内容。
4. Electron 内部额度能力、provider 登录缓存和私有 RPC 不是外部集成契约；本轮没有调用、逆向或探测。
5. 官方 `glm-plan-usage` 插件读取环境变量 Token，不复用 ZCode 登录态。
6. 本地 Session Token 只能描述本机活动，不能推算服务端套餐余额、跨工具消耗、积分倍率或重置时间。
7. 现有 AgentPager Keychain adapter 使用第二份 Key，只能算可选降级方案。

本轮复核的是这些路径是否因当前 CLI 帮助、官方 app-server/Hook/插件规范、官方授权能力或政策更新而出现了新的公开接缝。结论仍是否定的。

## 候选接缝矩阵

“未公开”表示在本轮核对的官方帮助、文档索引、公开 OpenAPI 和固定提交源码中没有找到相应契约；这是当前公开能力判断，不声称 ZCode 内部绝对不存在该能力。

| 候选路径 | 官方公开支持 | 复用 ZCode 登录态 | 重复 Key | AgentPager 接触凭据 | 稳定机器 Schema | 5h / 周窗口 | 重置 / 新鲜度 | 可区分 auth / 429 / 暂不可用 / Schema 变化 | 当前状态 | 主要一手证据 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `zcode quota/usage/usage-stats/account status --json` | 否；当前帮助无这些命令 | 不适用 | 不适用 | 不适用 | 无 | 无 | 无 | 无 | **不可用** | 当前安装 CLI `0.16.5` 公开帮助；[ZCode Usage Stats 仅描述 UI](https://zcode.z.ai/en/docs/usage-stats) |
| `zcode app-server` quota/usage 方法或本地只读 API | 仅公开了 stdio 入口；安装包元数据有 `usage/stats`、`session/usage`，但没有公开协议/兼容承诺，且处理器只读本地 App/Session Token 统计 | 否；不是 Coding Plan 数据 | 不适用；没有目标额度 | 否；但也没有目标数据 | 有内部统计结构，无公开 quota Schema | 无 | 只有统计生成时间，无套餐重置/新鲜度 | 无额度鉴权或 429 语义 | **不可用** | 当前 CLI `0.16.5` 固定哈希入口；[Usage Stats 对本地 App Usage 与远端 Coding Plan 的区分](https://zcode.z.ai/en/docs/usage-stats) |
| ZCode Hook 额度字段 | Hook 本身公开；额度字段未发布 | 否 | 不要求 Key，但没有数据 | 否 | Hook Schema 有，quota Schema 无 | 无 | 无 | 只有 Hook 运行错误，不是额度错误 | **不可用** | [固定提交 Hook stdin 契约](https://github.com/zai-org/zcode-plugins/blob/e2d4b3ebecc795e8ba545283ce0e28e96493959c/docs/PLUGIN_DEVELOPMENT_CN.md)；[当前 Hook 文档](https://zcode.z.ai/en/docs/hooks) |
| ZCode 官方插件 / 扩展宿主能力 | 插件机制公开；账户/额度宿主 API 未发布 | 否；公开组件是 skill、command、agent、MCP、Hook | 若自行调 monitor endpoint 则仍需 Token | 自行调用时插件进程会接触 Token；不满足目标 | 无 quota Schema | 无宿主输出 | 无宿主输出 | 无宿主错误模型 | **当前不可用；未来最有希望的扩展点之一** | [固定提交插件开发教程](https://github.com/zai-org/zcode-plugins/blob/e2d4b3ebecc795e8ba545283ce0e28e96493959c/docs/PLUGIN_DEVELOPMENT_CN.md)；[当前 Plugin 文档](https://zcode.z.ai/en/docs/plugin) |
| 官方 `glm-plan-usage` 插件 | 是，但明确面向 Claude Code，且仅支持个人套餐 | 否 | **是**，需要环境变量 Token | 若由 AgentPager 驱动则本地插件进程接触 Token | 脚本直接打印上游 JSON，没有发布稳定裁剪 Schema | 上游响应可能有；插件旧映射未覆盖 Gate 0 的 `CREDIT_LIMIT` | 上游返回什么就打印什么；无采集时间契约 | 只先判 HTTP，业务错误与 Schema 变化没有完整分类 | **不满足 Gate** | [官方文档](https://docs.bigmodel.cn/cn/coding-plan/extension/usage-query-plugin)；[固定提交脚本](https://github.com/zai-org/zai-coding-plugins/blob/0446d0bb0bc537d97d3ab3664c4b8b9c4a0e1254/plugins/glm-plan-usage/skills/usage-query-skill/scripts/query-usage.mjs) |
| Z.ai / 智谱 OAuth scope、device authorization、只读 quota Token | ZCode UI 的账号授权公开；第三方授权规范未发布 | ZCode 自己能复用；AgentPager 不能 | 若未来有 scope 则可避免；当前无 | 当前只有 API Key 模型 | OpenAPI 无该授权或 quota Schema | 无 | 无 | 无 | **待官方新增，当前不可用** | [ZCode 账号授权说明](https://zcode.z.ai/en/docs/configuration)；[Z.ai OpenAPI 1.0.0](https://docs.z.ai/openapi.json) |
| 官方稳定本地 quota snapshot 文件 / JSONL | 否 | 未确认 | 理论上否 | 理论上否 | 无 | 无公开字段 | 无 | 无 | **不可用** | [Usage Stats 明确区分本地 App Usage 与远端 Coding Plan](https://zcode.z.ai/en/docs/usage-stats)；官方 Hook 的 transcript 还是临时文件 |
| AgentPager 直接请求 monitor usage endpoint | 只有官方 Claude Code 插件使用实例；未进入 Z.ai 公开 OpenAPI，未授权 AgentPager 场景 | 否 | **是** | **是**，必须持有 Token | 无公开版本化 Schema；现有 Gate 0 只是单次脱敏观测 | Gate 0 观测到 | Gate 0 观测到上游重置时间，但无公开兼容承诺 | Gate 0 仅实测业务 401；其他错误未验证 | **待官方书面确认；当前不得使用** | [固定提交脚本](https://github.com/zai-org/zai-coding-plugins/blob/0446d0bb0bc537d97d3ab3664c4b8b9c4a0e1254/plugins/glm-plan-usage/skills/usage-query-skill/scripts/query-usage.mjs)；[Z.ai 订阅条款](https://docs.z.ai/legal-agreement/subscription-terms)；[智谱使用须知](https://docs.bigmodel.cn/cn/coding-plan/usage-notes) |

## 逐项一手证据

### 1. CLI 没有新增公开只读额度命令

当前 CLI `0.16.5` 的顶层命令仍只有：

```text
app-server, commands, doctor, login, logout,
plugins, skills, tui, version
```

Slash Commands 仍是会话、模型、MCP、模式、目标、技能等操作，没有 `quota`、`usage`、`usage-stats`、`account status` 或其它额度命令。`--json` 的帮助是“在支持处输出机器可读 JSON”，它不会凭空构成一个额度命令。

对 `app-server --help`、`commands --help`、`plugins --help`、`skills --help` 的只读调用都返回同一顶层帮助，没有公开额外 quota 方法或 Schema。没有尝试未公开参数，也没有启动 app-server。

### 2. app-server 的 usage 方法只覆盖本地统计，不是套餐额度

CLI 帮助把 `app-server` 描述为 `ZCode Protocol stdio app server`，说明官方确实发布了一个 stdio 入口。当前帮助和官方文档没有发布方法列表或 quota Schema；不过，本轮在固定哈希 `3597160...3cbabc` 的官方 CLI 安装包中做了严格限定的静态元数据检查，确认协议注册表包含 `usage/stats` 与 `session/usage`。这两个相似名称不能直接忽略，也不能把它们误报成 Coding Plan 接缝。

直接处理器元数据显示：

- `usage/stats` 调用本地 session store 的 `queryAppUsage`，返回总 Token、输入/输出/推理/缓存 Token、请求数、会话/轮次、工具、模型与按日统计；
- `session/usage` 调用 `queryTaskUsage`，返回指定 Session 的 Token 与模型请求计数；
- 两者都没有 5 小时/周套餐窗口、服务端 `remaining`、`resetsAt` 或额度鉴权、限流、暂不可用与 Schema 变化状态。

这与官方 Usage Stats 文档把本地 **App Usage** 和远端 **Coding Plan** 分成两个数据面一致。[Usage Stats](https://zcode.z.ai/en/docs/usage-stats) 本轮没有启动 app-server、发送请求或读取登录状态；上述结论只来自固定哈希入口中方法注册表与直接处理器的限定静态检查。

此外，本轮在 ZCode 官方文档导航、官方插件仓库与当前 CLI 帮助中都没有找到：

- Coding Plan quota 方法名；
- 额度请求与响应 JSON Schema；
- 协议版本与兼容政策；
- 调用方如何继承 ZCode 登录态；
- 调用方能否在不接触凭据的情况下请求额度；
- 权限、用户同意、错误码和撤销模型。

因此 app-server 目前只能记为“存在公开进程入口和内部本地 usage 统计，但 Coding Plan 额度能力未公开且现有 usage 处理器不满足数据契约”。私有方法探测、协议猜测或对 Electron 内部 RPC 的逆向不在本 Gate 允许范围内，不能用“可能存在”替代受支持契约。

### 3. Hook 仍无 quota、limit 或 usage snapshot 字段

官方固定提交和当前网页都列出七类事件：`SessionStart`、`UserPromptSubmit`、`PreToolUse`、`PermissionRequest`、`PostToolUse`、`PostToolUseFailure`、`Stop`。官方 stdin 表列出的重点字段是 session、临时 transcript、cwd、权限模式、prompt、模型、工具输入输出、错误和停止状态，没有 quota、rate limit、剩余量、重置时间或采集时间。[固定提交开发教程](https://github.com/zai-org/zcode-plugins/blob/e2d4b3ebecc795e8ba545283ce0e28e96493959c/docs/PLUGIN_DEVELOPMENT_CN.md) [当前 Hook 文档](https://zcode.z.ai/en/docs/hooks)

官方还明确说明 `transcript_path` 是 Hook 本次执行可读的临时 JSONL，Hook 完成后会清理，不能当长期存储。即使 transcript 包含本地会话内容，它也不是 Coding Plan 的远端额度快照。

结论：现有 Hook 可以继续承担 AgentPager 的会话与审批接缝，不能顺带承担额度接缝。

### 4. 官方插件机制没有宿主级账户或额度能力

当前官方插件由 skill、command、subagent、MCP server 和 Hook 组成。Hook 是本地子进程协议；MCP 是外部 stdio / HTTP / SSE 服务；敏感 `userConfig` 需要显式配置，当前 UI 甚至还不能直接录入敏感值。官方文档列出的插件进程注入变量是插件根目录、数据目录、ID 和名称，没有 ZCode account、provider、quota client 或裁剪 snapshot 句柄。[固定提交开发教程](https://github.com/zai-org/zcode-plugins/blob/e2d4b3ebecc795e8ba545283ce0e28e96493959c/docs/PLUGIN_DEVELOPMENT_CN.md) [当前 Plugin 文档](https://zcode.z.ai/en/docs/plugin)

插件能运行代码不等于插件被授权读取 ZCode 登录态。让插件读取继承环境、provider 配置或私有缓存，再调用 monitor endpoint，会把凭据交给插件进程并依赖未公开状态，仍违反 Gate。

插件机制仍是最有希望的未来承载点之一：如果 ZCode 官方新增一个宿主调用，例如只把版本化、裁剪后的 `quotaSnapshot` 交给受授权插件，而不把 Token 交给插件，那么插件可以在 ZCode 受控环境内完成用户同意、权限与版本管理。**当前规范没有这项能力，不能开始原型。**

### 5. 官方 GLM usage 插件仍要求独立 Token

官方文档明确把 `glm-plan-usage` 描述为“在 Claude Code 中”查询个人版 Coding Plan 用量的插件。[智谱用量查询插件](https://docs.bigmodel.cn/cn/coding-plan/extension/usage-query-plugin)

固定提交脚本的鉴权路径没有变化：

1. 读取 `ANTHROPIC_BASE_URL`；
2. 读取 `ANTHROPIC_AUTH_TOKEN`；
3. 缺少任一值时退出；
4. 把 Token 放入 `Authorization` 请求头；
5. 请求 `model-usage`、`tool-usage` 和 `quota/limit`。[固定提交脚本](https://github.com/zai-org/zai-coding-plugins/blob/0446d0bb0bc537d97d3ab3664c4b8b9c4a0e1254/plugins/glm-plan-usage/skills/usage-query-skill/scripts/query-usage.mjs)

它不读取 ZCode 登录态，也不输出一个为 AgentPager 定义的稳定裁剪契约。脚本的 quota 后处理只识别旧 `TOKENS_LIMIT` / `TIME_LIMIT`，而本仓库 Gate 0 实测当前套餐返回 `CREDIT_LIMIT`；脚本还会直接打印上游 JSON。它是“带 Token 的官方查询实例”，不是“无重复 Key 的第三方接缝”。

### 6. 没有面向本地辅助应用的公开 OAuth / device flow / 只读 quota Token

ZCode 官方文档说明用户可以在 ZCode 中选择 Z.ai 或 BigModel，打开授权流程并等待认证；成功后账号自动绑定，ZCode 会直接应用账号的套餐与额度。这是 ZCode 自己的产品登录链路。[Connect Models & Plans](https://zcode.z.ai/en/docs/configuration)

但 Z.ai 当前公开 OpenAPI `1.0.0`：

- 全局安全模型只有 `bearerAuth`；
- 说明要求 `Bearer <your api key>`；
- 没有 OAuth security scheme；
- 没有 device authorization endpoint；
- 没有 quota-only scope 或只读 quota Token；
- 没有 `monitor/usage` 或 quota path。[Z.ai OpenAPI](https://docs.z.ai/openapi.json)

Z.ai 与智谱的官方文档索引也没有列出本地辅助应用授权规范。[Z.ai 文档索引](https://docs.z.ai/llms.txt) [智谱文档索引](https://docs.bigmodel.cn/llms.txt)

这只能得出“当前公开资料没有该能力”，不能据此逆向复用 ZCode 内部 OAuth。若官方实际上有合作方或未公开接口，仍需官方发布或书面确认后才能进入 Gate。

### 7. 没有官方稳定本地额度快照契约

ZCode 官方 Usage Stats 明确区分两个数据面：

- App Usage 读取当前设备的本地 ZCode session；
- Coding Plan 读取远端 Z.ai / BigModel 的 quota、模型用量和工具用量。

该文档公开了 UI 能展示 5 小时、每周、MCP、剩余额度和重置卡片，但没有公开本地文件路径、版本字段、并发写入规则、刷新语义或 Schema。[Usage Stats](https://zcode.z.ai/en/docs/usage-stats)

本轮没有查看 `coding-plan-cache`。即使机器上存在内部缓存，官方没有把它声明为第三方 API，就不能作为 AgentPager 稳定数据源。

### 8. monitor usage endpoint 没有明确授权给 AgentPager

官方 `glm-plan-usage` 插件证明智谱允许它在明确的 Claude Code 插件场景中，用用户已配置的 Token 查询 monitor usage endpoint；这不等于官方允许任意本地辅助应用复用该 endpoint，更不提供无凭据鉴权。

政策边界反而要求保守：

- Z.ai 订阅条款规定 Coding Plan 额度只能用于官方支持工具；未经书面协议，不得在自建应用、机器人、网站、SaaS 或其它系统中使用。[Z.ai 订阅条款](https://docs.z.ai/legal-agreement/subscription-terms)
- Z.ai Usage Policy 明确把未授权工具、SDK 与第三方集成列为可能触发权益限制的场景。[Z.ai Usage Policy](https://docs.z.ai/devpack/usage-policy)
- 智谱使用须知同样限定官方支持的工具与产品环境，并保留对非支持工具采取限制的权利。[智谱使用须知](https://docs.bigmodel.cn/cn/coding-plan/usage-notes)

AgentPager 只读查询额度是否能被官方认定为支持的“辅助显示”场景，当前文档没有明确答案。公开发布前需要 Z.ai / 智谱书面确认；在此之前不能把 endpoint 存在或官方 Claude Code 插件存在解释为 AgentPager 的接入许可。

## 安全评估

### 当前可接受的未来架构边界

只有当 ZCode 或 Z.ai / 智谱提供下列任一官方能力时，才值得重新开启原型：

1. ZCode 进程自己完成鉴权与额度查询，只向 AgentPager 输出裁剪快照；或
2. 用户单独授权一个 quota-only scope，AgentPager 取得的 Token 只能读取额度，不能调用模型、修改套餐或读取账号其它数据。

无论采用哪种方式，AgentPager 都不应读取或复制 ZCode 的 OAuth、Cookie、provider、登录缓存或主 API Key，也不应让 Android 保存任何凭据。

### 明确排除

- 私有 Electron RPC、renderer 注入或安装包修改；
- `coding-plan-cache` 或 provider 配置解析；
- OAuth、Cookie、Token、Key 或认证头提取与转存；
- OCR / 截图识别额度页面；
- 中间人代理、抓包或从网络流量恢复 Token；
- 本地 Token 消耗估算服务端余额；
- 把现有 Keychain provider 描述成无重复 Key；
- 用 fake provider 或合成 Key 证明真实登录态接缝；
- 调用未公开 app-server / IPC 方法碰碰运气。

## Gate 判定

### 判定：未通过

当前所有可见路径至少缺少以下一项关键条件：官方公开支持、复用 ZCode 登录态、不暴露凭据、稳定 Schema 或明确政策许可。没有候选能进入最小隔离原型。

### 最有希望的候选

当前最有希望的不是某个可立即调用的隐藏入口，而是由 ZCode 官方新增的 **宿主级裁剪额度快照**：

- 首选：`zcode usage --json` 或等价只读 stdio/app-server 方法；
- 次选：ZCode 插件宿主 API，把裁剪 snapshot 交给受授权插件；
- 备选：版本化本地 JSON 快照；
- 服务端方案：quota-only OAuth scope / device authorization。

这些都属于需要官方新增或公开的能力，不能在当前版本做原型。

## 原型前置条件

只有下列条件全部满足后，才向用户申请最小原型授权：

1. 官方发布不可变版本或明确兼容政策的入口与 Schema。
2. 官方说明鉴权发生在 ZCode 宿主或 quota-only 授权中，AgentPager 不接触主凭据。
3. 官方说明 AgentPager 这类本地辅助显示用途被允许。
4. 快照至少包含：
   - `schemaVersion`、provider ID、通用套餐显示名；
   - 5 小时与每周窗口；
   - 服务端已用或剩余比例；
   - 独立 `remaining`（若服务端提供）；
   - `resetsAt`、`capturedAt`、来源版本；
   - `fresh / stale / authRequired / rateLimited / unavailable / schemaChanged`。
5. 真实登录态验证前先书面列出会读取什么、修改什么、网络请求对象、日志与临时文件、停止条件、备份和恢复验证，并等待用户明确授权。
6. 原型在隔离目录和替换 provider adapter 中完成，不改真实 ZCode 配置、已安装 Bridge、Android 或 Redmi。

## 建议向官方请求的最小能力

按实现成本和安全收益排序，任一项均可重新打开 Gate：

1. `zcode usage --json`：由 ZCode 使用自己的登录态，stdout 只返回版本化裁剪 snapshot；退出码和错误体区分鉴权、429、暂不可用与 Schema 变化。
2. app-server 只读 `account/quotaSnapshot` 方法：明确协议版本、调用方权限、用户同意与错误模型，不暴露 provider 或凭据。
3. 插件宿主 `quotaSnapshot` capability：插件只收结果，不收 OAuth、Cookie 或 Key；宿主控制授权与撤销。
4. 官方稳定本地快照：原子写入、版本字段、5 小时/周窗口、重置、采集时间、健康状态和兼容承诺。
5. Z.ai / 智谱 quota-only OAuth scope 或 device flow：Token 只能读取套餐额度，有明确过期、撤销、最小权限和本地辅助应用政策。
6. 对 monitor usage endpoint 发布 OpenAPI 与使用政策：明确支持哪些客户端、鉴权方式、Schema 版本、限流、业务错误、缓存和数据新鲜度。

## 对 #10 / #1 的影响

- **#12：继续 OPEN。** 调研产物可以本地完成并提交，但 Completion Rule 尚未满足。
- **#10：继续 OPEN，并保持被 #12 阻塞。** Build 13 的默认无 Key 验收只证明隐私降级不破坏 ZCode / Android 行为，没有证明真实额度目标。
- **#1：继续 OPEN。** 原始产品目标“复用 ZCode 登录态显示真实 5 小时与每周额度”仍未完成。
- 不创建实现 Ticket，不修改现有 Issue 关系，不评论或关闭任何 Issue。

## 已验证、根据来源推断和未验证项

### 已验证

- 当前安装版本仍是 ZCode Desktop `3.10.1` / CLI `0.16.5`。
- 当前 CLI 公开帮助没有额度子命令或 Slash Command。
- 固定哈希 CLI 入口虽注册 `usage/stats` 与 `session/usage`，其直接处理器只返回本地 App/Session Token 统计，不返回 Coding Plan 额度；该协议也没有公开兼容承诺。
- 官方最新 Hook 契约没有 quota / usage snapshot 字段。
- 官方插件契约没有账户/额度宿主能力；公开变量和配置机制不提供 ZCode 登录态委托。
- 官方 `glm-plan-usage` 固定提交仍要求环境变量 Token，并直接请求 monitor usage endpoint。
- ZCode 官方 UI 能在账号授权后显示远端 5 小时与每周额度。
- Z.ai 公开 OpenAPI `1.0.0` 只有 API Key Bearer security scheme，没有 OAuth、device flow、quota scope 或 monitor usage path。
- Z.ai / 智谱官方政策没有明确授权 AgentPager 这类本地辅助应用查询 monitor usage endpoint。

### 根据官方来源推断

- ZCode 宿主内部具备账号登录后查询并展示额度的能力；依据是官方账号绑定、Usage Stats 与重置卡片说明，没有检查内部实现。
- 如果 ZCode 把裁剪 snapshot 作为 CLI、app-server 或插件宿主 capability 发布，可以在不交出主凭据的前提下满足 AgentPager 需求；这是设计推断，不是当前能力。
- 直接让 AgentPager 调 monitor endpoint 至少需要重复 Token，并可能落入未支持第三方集成政策边界；因此在官方书面确认前不能实施。

### 未验证

- ZCode 是否另有未注册、未公开或未来版本的 app-server / Electron quota 方法；按安全边界没有做运行时探测。
- ZCode 私有缓存、provider、OAuth 或 Cookie 的字段与刷新行为；没有读取。
- 真实账号登录态、真实额度响应、429、403、5xx、超时或 Schema 变化；没有调用真实接口。
- Z.ai / 智谱是否向合作方提供未公开 quota-only scope 或私有 SDK；公开资料中未找到，不代表内部绝对不存在。
- 官方是否愿意书面批准 AgentPager 的只读辅助显示用途；需要后续人工询问。

## 链接检查与敏感信息边界

本记录中的外部链接在 2026-08-29 通过官方网页、GitHub API 或固定提交读取；固定提交链接避免把源码结论绑定到可变 `main`。文档没有保存 Key、Token、Cookie、OAuth 值、认证头、个人账号、provider 内容、私有缓存正文或原始额度响应；环境变量名、公开 endpoint 路径和公开安装路径仅用于说明官方契约，不包含凭据值。
