# ZCode / GLM 额度无重复 Key 接入调研

日期：2026-08-29

范围：调查 AgentPager 能否像读取 Codex 本地 Session JSONL 中的 `rate_limits` 一样，在不要求用户再次输入 GLM Coding Plan Key、也不读取或复制 ZCode OAuth、Cookie 或其他私有凭据的前提下，获得 5 小时与每周额度。本轮只读调查，没有调用真实额度接口，没有读取或输出 Key、OAuth、Cookie、账号或原始接口响应。

时序说明：本文件中的本地缓存字段名/类型检查完成于“不得读取 `coding-plan-cache` 内容”的新产品边界建立之前。新边界建立后没有再次读取该文件；当前实现不消费这些信息，后续也不得重复该检查。保留这段历史披露，是为了准确说明调研证据及其已被新策略废止的边界，不构成实现依赖或继续授权。

## 结论摘要

截至本次调查，**不能把 Issue #7 改成一个有公开契约保证的“完全无 Key”实现**。

ZCode 自己确实能够在用户登录后展示 Coding Plan 的 5 小时、每周和 MCP 额度；官方文档明确说明，这部分读取的是 Z.ai / BigModel 的**远端统计**，而不是本地 Session 记录。只有“应用用量”来自本地 ZCode Session。[ZCode 官方使用统计](https://zcode.z.ai/cn/docs/usage-stats) [ZCode 官方模型与套餐连接说明](https://zcode.z.ai/en/docs/configuration)

但当前没有找到 ZCode 对第三方程序公开的 quota/usage CLI 子命令、本地 API、Hook 字段或稳定的本地额度快照契约：

- 官方 Hook stdin 契约只覆盖会话、prompt、模型、工具、权限、错误和停止相关字段，没有 quota、usage-limit 或 rate-limit 字段；Hook 获得的是本地子进程输入，也拿不到可直接调用 ZCode 模型的内部对象。[ZCode 官方插件开发教程，固定提交](https://github.com/zai-org/zcode-plugins/blob/e2d4b3ebecc795e8ba545283ce0e28e96493959c/docs/PLUGIN_DEVELOPMENT_CN.md#45-stdin-%E8%BE%93%E5%85%A5%E5%A5%91%E7%BA%A6)
- 本机 ZCode Desktop 3.10.1 所带 CLI 0.16.5 的完整顶层帮助只列出 `app-server`、`commands`、`doctor`、`login`、`logout`、`plugins`、`skills`、`tui` 和 `version`；内建 Slash Commands 也没有 quota/usage 命令。只读复核命令见下文。
- 本机存在 `~/.zcode/v2/coding-plan-cache.json`，但本轮仅脱敏检查字段名与类型后，当前文件只含版本、更新时间和四个内建套餐入口的可用状态/原因，不含 5 小时、每周、剩余量或重置时间。更重要的是，ZCode 官方文档没有把该路径或 Schema 声明成外部集成契约；即使未来某个版本把额度放进去，也只能视为内部缓存，不能直接当产品 API。
- 本机安装包的限定静态检查确认 ZCode 自己包含 `UsageStats`、`getCodingPlanUsageSnapshot`、`resolveAuthorization`、`refreshCodingPlanApiKey` 和 quota endpoint。授权函数会先检查专用环境变量，再读取 ZCode 自己缓存的 provider；当指定 Coding Plan provider 没有可用 Key 时，它还可能要求 provider service 刷新 Coding Plan API Key，最后用 provider 持有的 Key 请求额度。这证明“ZCode 内部已经完成登录态取凭据并查询额度”这个判断成立；检查只覆盖相关函数周边，没有读取任何凭据值。上述能力位于 Electron `app.asar` 内部实现，当前 ZCode 进程也没有对外 TCP 监听。它解释了为什么 ZCode UI 不需要用户再填一次 Key，却仍不是 AgentPager 可调用的受支持 API。
- Z.ai 官方 `glm-plan-usage` 插件不是从 ZCode 登录态或 Session 日志读取额度。固定提交源码明确读取 `ANTHROPIC_AUTH_TOKEN`，将它放入 `Authorization` 头，然后请求 `/api/monitor/usage/quota/limit`；未提供 Token 时脚本直接失败。[官方插件查询脚本，固定提交](https://github.com/zai-org/zai-coding-plugins/blob/0446d0bb0bc537d97d3ab3664c4b8b9c4a0e1254/plugins/glm-plan-usage/skills/usage-query-skill/scripts/query-usage.mjs) 官方文档也把它描述为 Claude Code 插件，而不是 ZCode 对外额度桥接接口。[智谱官方用量查询插件文档](https://docs.bigmodel.cn/cn/coding-plan/extension/usage-query-plugin)

因此，用户提出的体验目标是合理的，但当前缺少 ZCode 提供的安全公开接缝。**推荐暂时保留 Issue #7 的“Bridge 钥匙串一次性配置 Key”能力，同时把它改成明确的可选降级方案；不要自动扫描或复制 ZCode 登录凭据，也不要改用内部缓存、日志或私有 IPC。** 如果 ZCode 后续公开只读额度 CLI/API，或公开一个不暴露凭据的本地快照契约，再切换成真正的无重复 Key 路径。

## 证据矩阵

| 问题 | 当前证据 | 判断 | 产品含义 |
| --- | --- | --- | --- |
| ZCode Hook 是否携带额度 | 官方列出的七类事件及 stdin 重点字段没有 quota、rate limit、剩余额度或重置时间；`transcript_path` 是 Hook 生命周期内的临时 JSONL，Hook 完成后清理。[官方 Hook 契约](https://github.com/zai-org/zcode-plugins/blob/e2d4b3ebecc795e8ba545283ce0e28e96493959c/docs/PLUGIN_DEVELOPMENT_CN.md#45-stdin-%E8%BE%93%E5%85%A5%E5%A5%91%E7%BA%A6) | 不可用 | 现有 AgentPager ZCode Hook 不能顺带取得套餐额度。 |
| 官方 CLI 是否有只读 quota/usage 命令 | 本机 ZCode 3.10.1 / CLI 0.16.5 顶层命令和 Slash Commands 均无 quota/usage；`--json` 只是“在支持处输出机器可读 JSON”的通用选项，不构成额度命令。 | 当前没有发现 | 不能像调用 `zcode usage --json` 那样接入；也不应借 `login` 获取额度。 |
| 官方 ZCode UI 是否已能显示额度 | 官方使用统计页明确区分：App Usage 读本地会话，Coding Plan 读远端 Z.ai / BigModel 统计，展示 5 小时、每周与 MCP 额度。[ZCode 官方使用统计](https://zcode.z.ai/cn/docs/usage-stats) | 能，但属于 ZCode 内部登录链路 | “ZCode 能显示”不等于“ZCode 已向 AgentPager 发布额度接口”。 |
| 官方 GLM 用量插件怎样鉴权 | 脚本读取 `ANTHROPIC_BASE_URL` 与 `ANTHROPIC_AUTH_TOKEN`，用 Token 请求三个 monitor endpoint；quota 请求不带时间参数。[官方插件源码](https://github.com/zai-org/zai-coding-plugins/blob/0446d0bb0bc537d97d3ab3664c4b8b9c4a0e1254/plugins/glm-plan-usage/skills/usage-query-skill/scripts/query-usage.mjs) | 仍需要可用的 Coding Plan 凭据 | 插件证明额度接口存在，但不能证明第三方可无凭据读取。 |
| 是否有公开稳定的本地额度文件 | 官方 ZCode 文档没有公开文件路径或 Schema。本机内部缓存当前只有套餐入口状态，且其权限、结构和生命周期都未被官方承诺。 | 没有已确认契约 | 不应把 `~/.zcode/v2/coding-plan-cache.json` 作为生产数据源。 |
| ZCode 内部是否已经有额度读取能力 | 本机 `app.asar` 的限定静态检查确认内部存在 Usage Stats、quota snapshot、授权解析、Coding Plan Key 刷新及 quota endpoint；授权会从 ZCode 自己的 provider / 登录链路取得可用 Key。官方文档也展示同一 UI 能力。[ZCode 官方使用统计](https://zcode.z.ai/cn/docs/usage-stats) | 有内部能力，但没有受支持外部契约 | 可以解释“ZCode 为什么不用重复填”，不能据此调用私有 RPC、读取私有 provider cache 或复制登录凭据。 |
| 是否可复用 ZCode OAuth/Cookie | ZCode 登录后会直接应用账号的套餐和额度。[官方模型与套餐连接说明](https://zcode.z.ai/en/docs/configuration) 但没有公开第三方取用登录凭据或委托查询的接口。 | 技术上可能存在内部链路，产品上不可用 | 自动读取、复制或转发 OAuth/Cookie 超出隐私边界，也可能破坏登录态。 |
| 本地模型 Token 统计能否推算额度 | 官方 ZCode 使用统计把本地 Session Token 统计与远端 Coding Plan 额度分成两个数据面。[ZCode 官方使用统计](https://zcode.z.ai/cn/docs/usage-stats) | 不能等价替代 | 本地 Token 只能描述本机 ZCode 活动，无法覆盖其他工具消耗、服务端积分倍率、重置和服务器 `remaining`。 |

## 与 Codex 机制的差异

AgentPager 当前 Codex 路径不需要 OpenAI API Key，是因为 Codex 已把 `token_count.rate_limits` 写入自己的 Session JSONL；AgentPager 只读 `~/.codex/sessions` 和 `~/.codex/archived_sessions`，从 `primary` / `secondary` 窗口解析 `used_percent`、窗口分钟数和重置时间。[CodexUsageLoader.swift](../../macos/Sources/AgentGridCore/CodexUsageLoader.swift) [CodexUsageTests.swift](../../macos/Tests/AgentGridCoreTests/CodexUsageTests.swift)

这条路径有一个明确的本地载体：

```text
Codex 服务端响应
  → Codex Session JSONL 的 event_msg / token_count / rate_limits
  → AgentPager 只读解析
```

ZCode 当前公开能力则是：

```text
ZCode 本地 Session
  → Hook：会话/工具/权限/停止事件（无套餐额度）

ZCode 登录账号
  → ZCode 内部远端统计链路
  → ZCode Usage Stats UI（未公开第三方读取接缝）

Coding Plan Key
  → monitor/usage/quota/limit
  → 官方 Claude Code 用量插件或 AgentPager Issue #7 adapter
```

所以差异不是 OpenAI “不需要鉴权”而 GLM “一定需要再鉴权”，而是 **Codex 已把额度结果落到了 AgentPager 可只读消费的本地 Session 事件里；ZCode 目前没有为第三方公开等价输出。** ZCode 自己仍通过登录账号或 Key 与远端套餐服务建立授权关系。[ZCode 官方模型与套餐连接说明](https://zcode.z.ai/en/docs/configuration)

## 逐项调查

### 1. Hook 没有额度字段

ZCode 官方当前支持 `SessionStart`、`UserPromptSubmit`、`PreToolUse`、`PermissionRequest`、`PostToolUse`、`PostToolUseFailure` 和 `Stop`。官方 stdin 字段表包括 `session_id`、`transcript_path`、`cwd`、`permission_mode`、事件名、模型、prompt、工具输入/输出、错误和停止信息，没有额度相关字段。[官方 Hook 事件与 stdin 契约](https://github.com/zai-org/zcode-plugins/blob/e2d4b3ebecc795e8ba545283ce0e28e96493959c/docs/PLUGIN_DEVELOPMENT_CN.md#4-hooks-%E5%BC%80%E5%8F%91%E6%8C%87%E5%8D%97)

`transcript_path` 也不是 Codex 那类长期日志：官方明确写明它是本次 Hook 可读的临时 JSONL，Hook 完成后 ZCode 会清理临时目录，插件自己的长期数据应写到 `ZCODE_PLUGIN_DATA`。[官方 stdin 契约](https://github.com/zai-org/zcode-plugins/blob/e2d4b3ebecc795e8ba545283ce0e28e96493959c/docs/PLUGIN_DEVELOPMENT_CN.md#45-stdin-%E8%BE%93%E5%85%A5%E5%A5%91%E7%BA%A6)

这意味着即使 Hook 当前能可靠告诉 AgentPager “ZCode 正在思考/执行/等待审批”，也不能从同一负载中得到套餐额度。

### 2. 当前 CLI 没有只读 quota/usage 命令

本机只读验证：

```bash
plutil -p /Applications/ZCode.app/Contents/Info.plist
node /Applications/ZCode.app/Contents/Resources/glm/zcode.cjs --version
node /Applications/ZCode.app/Contents/Resources/glm/zcode.cjs --help
```

结果是 ZCode Desktop `3.10.1 (6272)`、CLI `0.16.5`。CLI 帮助列出的顶层命令只有：

```text
app-server, commands, doctor, login, logout,
plugins, skills, tui, version
```

内建 Slash Commands 只有帮助、登录/退出、压缩、专家流程、fork、MCP、模式、模型、新会话、resume、rewind、skill 和 goal，没有 quota/usage。版本元数据见本机 [Info.plist](</Applications/ZCode.app/Contents/Info.plist>)，CLI 入口见 [zcode.cjs](</Applications/ZCode.app/Contents/Resources/glm/zcode.cjs>)。

这个结论只针对当前安装的 3.10.1 / 0.16.5；CLI 将来可能新增命令。当前不能因为存在通用 `--json` 选项，就推断隐藏的额度 API。

### 3. 官方用量插件仍然需要 Token

Z.ai 官方 `glm-plan-usage` README 写明该插件用于 Claude Code，并通过 `/glm-plan-usage:usage-query` 触发查询。[官方插件 README](https://github.com/zai-org/zai-coding-plugins/blob/0446d0bb0bc537d97d3ab3664c4b8b9c4a0e1254/plugins/glm-plan-usage/README.md)

固定提交的查询脚本行为是：

1. 读取 `ANTHROPIC_BASE_URL` 和 `ANTHROPIC_AUTH_TOKEN`；
2. 缺少 Token 或 Base URL 时直接失败；
3. 根据 Z.ai / BigModel 域名构造 `model-usage`、`tool-usage`、`quota/limit`；
4. 用 `Authorization: <token>` 请求；
5. 把 quota 响应映射为用量结果。

来源：[官方插件查询脚本，固定提交](https://github.com/zai-org/zai-coding-plugins/blob/0446d0bb0bc537d97d3ab3664c4b8b9c4a0e1254/plugins/glm-plan-usage/skills/usage-query-skill/scripts/query-usage.mjs)

它复用的是运行环境中的 Coding Plan Token，不是 ZCode Session JSONL，也没有通过 ZCode OAuth 向外委托查询。因此，AgentPager 调用该脚本并不能消除凭据问题，只是把同一个凭据依赖换了位置。

### 4. 本机内部缓存目前不是额度快照

本机存在：

```text
~/.zcode/v2/coding-plan-cache.json
```

为避免读取账号或原始响应，本轮只输出了 JSON 字段名和字段类型，不输出任何标量值。当前脱敏结构为：

```text
version: number
entryStatus:
  updatedAt: number
  items:
    builtin:zai-start-plan: status, reason?
    builtin:zai-coding-plan: status, reason?
    builtin:bigmodel-start-plan: status, reason?
    builtin:bigmodel-coding-plan: status, reason?
```

当前结构没有额度窗口、已用百分比、服务器剩余值或重置时间。官方 Usage Stats 文档说明 ZCode 的 Coding Plan 页面读取远端统计，但没有把这个文件公开为第三方接口。[ZCode 官方使用统计](https://zcode.z.ai/cn/docs/usage-stats)

因此该文件最多能证明“ZCode 内部维护了套餐入口状态缓存”，不能证明它是类似 Codex `rate_limits` 的持久额度事件。路径、字段、刷新时机和并发写入方式均没有外部契约；直接监听它会形成版本敏感、静默失效的产品依赖。

### 5. ZCode 内部有能力，但没有对外接缝

为核实“ZCode 自己是否已经实现这套”，本轮对本机安装包做了限定静态检查：先检查固定实现名称，再只查看 `resolveAuthorization` 周边的打包代码；没有执行内部方法，也没有读取运行时凭据：

```bash
rg -a -o 'getCodingPlanUsageSnapshot|resolveAuthorization|refreshCodingPlanApiKey|/api/monitor/usage/quota/limit|UsageStats' \
  /Applications/ZCode.app/Contents/Resources/app.asar \
  | sort -u
```

五个目标字符串都存在。授权函数周边代码还显示：它会检查专用环境变量、读取 ZCode 自己缓存的 model provider，在指定 Coding Plan provider 缺少可用 Key 时尝试刷新，再使用 provider 持有的 Key 构造额度授权。这与官方 Usage Stats 页面所述“Coding Plan 读取远端统计”一致，可以确认 ZCode 内部已经有：额度页面、额度快照入口、授权解析、Coding Plan 凭据刷新和 quota endpoint。该检查没有输出 Key、provider 内容或接口响应。

但这仍不能成为 AgentPager 的集成方案：

- 这些是 `app.asar` 内部名称，不是公开文档或版本化协议；
- 当前 CLI 帮助没有把快照方法暴露成命令；
- 对本机全部 `/Applications/ZCode.app` 进程做只读 socket 检查，没有发现 TCP LISTEN，因此没有可调用的公开 loopback HTTP/WebSocket 服务；
- 从命名和官方登录说明可以推断，内部授权来自 ZCode 自己管理的 provider/账号状态；让 AgentPager 直接触达它仍会跨越 OAuth/API Key 私有边界。

因此更准确的判断是：**不是 ZCode “没有额度”，而是额度目前封装在 ZCode Electron 内部 RPC / 账号服务中，没有发布给外部客户端。** 私有实现细节可作为解释性证据，不能当稳定 API，也不应通过 renderer 注入、Mojo/RPC 探测或读取 provider cache 来绕过边界。

### 6. Gate 0 只证明了 Key 路径，不证明无 Key 路径

仓库已有 Gate 0 脱敏验证确认：`quota/limit` 能返回 5 小时与每周窗口；当前实际类型为 `CREDIT_LIMIT`，`percentage` 表示已用百分比，`remaining` 必须按服务器值保留；无效凭据可能 HTTP 200 但业务 `code=401`。[Gate 0 契约记录](2026-08-28-zcode-glm-gate0-contract-validation.md) [脱敏 GLM 契约](../contracts/glm/2026-08-28-coding-plan.sanitized.json)

但该验证使用的是用户明确授权的 Coding Plan Key，并且原始响应只在进程内处理。它确认了“凭据 + monitor endpoint”契约，不代表 ZCode 已公开无凭据查询能力。

## 可行方案排序

### 1. 等待 ZCode 发布只读额度接缝（长期推荐）

理想契约应由 ZCode 官方提供其一：

- `zcode usage --json` 这类只读 CLI；
- 本地 loopback API / IPC，只返回裁剪后的 quota snapshot；
- 官方声明稳定的本地 JSON/JSONL 文件，包含版本、来源、5 小时/周窗口、服务器剩余值、重置时间和更新时间；
- 新 Hook/插件 API，由 ZCode 主进程把额度快照交给插件，但不交出 OAuth/Key。

这能真正达到 Codex 当前体验：AgentPager 只消费 ZCode 已授权后生成的额度结果，不接触登录凭据。当前没有找到上述公开契约，所以这是未来方案，不是可立即实现的事实。

### 2. 保留 Bridge 钥匙串的一次性 Key 配置（当前可交付方案）

当前 Issue #7 已把 Key 限制在 macOS Bridge 钥匙串，Android 只收到裁剪后的额度窗口；Bridge 不扫描 ZCode 配置、OAuth、Cookie 或浏览器状态。[Issue #7 实现记录](2026-08-29-issue-7-glm-coding-plan-quota.md)

建议保留它，但产品文案应明确：

- 这是“可选的独立额度连接”，不是使用 ZCode Hook 的必填项；
- 不配置 Key 时，ZCode 会话监控与手机审批继续工作，只是不显示 GLM 额度；
- Key 只需首次保存，后续由系统钥匙串使用；
- 一旦 ZCode 提供官方无凭据接缝，应优先迁移并允许删除 Bridge 中的 Key。

风险：官方用量插件明确面向 Claude Code，ZCode/智谱官方使用政策又要求 Coding Plan 只在支持的工具与产品环境中使用。[智谱使用须知](https://docs.bigmodel.cn/cn/coding-plan/usage-notes) 因此 AgentPager 只查询额度这一用途是否属于允许的辅助集成，官方文档没有明确承诺。当前方案技术上已由 Gate 0 验证，但公开发布前仍应向官方确认用途边界。

### 3. 监听内部 `coding-plan-cache.json`（不推荐）

优点是可能不要求用户重复输入凭据；缺点是当前文件根本没有目标额度字段，并且没有官方 Schema、兼容性、权限或刷新保证。不能把“文件存在”升级成“稳定 API”。

只有 ZCode 官方未来公开该文件契约，或 AgentPager 明确把它做成版本锁定、默认关闭、失败即无数据显示的实验适配器时，才值得重新评估；当前不应替换 Issue #7。

### 4. 自动复用 ZCode OAuth、Cookie、私有配置或内部 IPC（禁止）

这条路径可能在技术上接近 ZCode 自己的远端统计链路，但会复制或转用 ZCode 私有登录能力：

- 凭据格式和刷新规则没有外部契约；
- 可能触发刷新、覆盖、登出或账号状态变化；
- 会扩大 AgentPager 的敏感权限和泄露面；
- 违背本次明确的“不读取/复制 OAuth、Cookie、私有凭据”边界。

因此不应做探索性实现，也不应把内部数据库、日志搜索或 renderer IPC 注入包装成“无 Key”。

### 5. 用本地 Token 自行估算（不推荐）

本地 Session Token 无法覆盖其他工具对同一套餐的消耗，也不能可靠复现服务端积分倍率、滚动窗口、周重置和 `remaining`。仓库 Gate 0 已证明 `remaining` 甚至可能与简单减法存在差异。[Gate 0 契约记录](2026-08-28-zcode-glm-gate0-contract-validation.md)

这类估算最多是“本机活动统计”，不能标成“GLM 剩余额度”。

## 对 Issue #7 当前实现的建议

1. **不要删除现有 Keychain 路径，也不要现在改成读取 ZCode 私有数据。** 当前没有已验证、稳定、合规的替代数据源。
2. **把 GLM Key 明确为可选。** 未配置时不显示 GLM 卡片，不影响 ZCode Hook、任务监控或手机审批；这与当前实现行为一致。
3. **修正文案。** 不应写成“GLM 必须重复登录”，而应写成“ZCode 已在自己的登录态中显示额度，但尚未提供给 AgentPager 的公开读取接口；如需在 AgentPager 显示，可选择单独保存一次 Coding Plan Key”。
4. **为未来官方接缝保留 provider adapter。** 若 ZCode 增加稳定 CLI/API/快照，只替换 macOS 的数据来源，继续复用 `UsageProviderSnapshot` 与 Android `GENERAL → SPARK → GLM` 展示。
5. **建立迁移优先级。** 新版本 ZCode 发布时，先复查 `zcode --help`、官方 Usage Stats / Plugin / Hook 文档；只有官方明确给出契约，才实现无 Key provider。
6. **公开分发前确认政策。** 向 Z.ai / 智谱确认“本地辅助应用使用用户自己的 Coding Plan Key，只调用 monitor usage endpoint”是否属于支持范围；在官方确认前，不把插件源码存在解释为长期 API SLA。

## 未验证边界

- 没有调用真实 `quota/limit`、`model-usage` 或 `tool-usage`，也没有触发 ZCode 登录、登出或 OAuth 刷新。
- 没有读取 ZCode OAuth、Cookie、账号字段、Key、真实额度数值或原始接口响应。
- 对 `coding-plan-cache.json` 只检查文件存在性、元数据、字段名和类型；没有输出任何标量值。当前文件状态只代表本机 ZCode 3.10.1，不能推断其他账号、平台、团队套餐或未来版本。
- 没有反编译或依赖 ZCode 私有 IPC / renderer 实现；即使内部代码存在额度调用，也不构成公开外部契约。
- 对 `app.asar` 只检查五个固定实现名称及授权函数的限定周边，没有提取完整源码、调用内部方法或检查 provider 凭据值；这一证据仅证明内部能力及大致授权来源存在。
- 本机 `app-server` 没有公开的 quota/usage 帮助；本轮没有启动会话或发送协议请求，因此不声称穷尽所有未文档化方法。
- 官方文档确认 ZCode UI 读取远端 Coding Plan 统计，但没有公开其本地缓存或第三方委托鉴权方式；“内部一定有可复用 API”只是推断，不能用于产品。

## 来源

### 官方公开来源

- [ZCode 使用统计：本地 App Usage 与远端 Coding Plan 的边界](https://zcode.z.ai/cn/docs/usage-stats)
- [ZCode Connect Models & Plans：账号套餐与 API Key 两类接入](https://zcode.z.ai/en/docs/configuration)
- [ZCode 官方插件开发教程 / Hook 契约，固定提交 e2d4b3e](https://github.com/zai-org/zcode-plugins/blob/e2d4b3ebecc795e8ba545283ce0e28e96493959c/docs/PLUGIN_DEVELOPMENT_CN.md)
- [GLM Plan Usage 官方插件 README，固定提交 0446d0b](https://github.com/zai-org/zai-coding-plugins/blob/0446d0bb0bc537d97d3ab3664c4b8b9c4a0e1254/plugins/glm-plan-usage/README.md)
- [GLM Plan Usage 官方查询脚本，固定提交 0446d0b](https://github.com/zai-org/zai-coding-plugins/blob/0446d0bb0bc537d97d3ab3664c4b8b9c4a0e1254/plugins/glm-plan-usage/skills/usage-query-skill/scripts/query-usage.mjs)
- [智谱官方用量查询插件文档](https://docs.bigmodel.cn/cn/coding-plan/extension/usage-query-plugin)
- [智谱 Coding Plan 快速开始：Key 获取与保护](https://docs.bigmodel.cn/cn/coding-plan/quick-start)
- [智谱 Coding Plan 使用须知](https://docs.bigmodel.cn/cn/coding-plan/usage-notes)

### 本地一手证据

- [ZCode Info.plist](</Applications/ZCode.app/Contents/Info.plist>)：Desktop 版本元数据。
- [ZCode CLI 入口](</Applications/ZCode.app/Contents/Resources/glm/zcode.cjs>)：本轮仅执行 `--version` / `--help`，没有运行登录或额度请求。
- [ZCode Electron app.asar](</Applications/ZCode.app/Contents/Resources/app.asar>)：本轮只检查五个固定实现名称及授权函数的限定周边，用于区分“内部能力存在”与“公开外部契约不存在”；没有读取凭据值。
- `~/.zcode/v2/coding-plan-cache.json`：仅做字段名/类型脱敏检查；因属于用户目录内部缓存，本报告不提供可点击链接，也不把它作为公开契约。
- [CodexUsageLoader.swift](../../macos/Sources/AgentGridCore/CodexUsageLoader.swift)：AgentPager 当前从 Codex Session JSONL 解析 `rate_limits` 的实现。
- [CodexUsageTests.swift](../../macos/Tests/AgentGridCoreTests/CodexUsageTests.swift)：Codex 本地 `rate_limits` 样本和窗口测试。
- [ZCode / GLM Gate 0 契约记录](2026-08-28-zcode-glm-gate0-contract-validation.md)：真实接口的脱敏契约结论。
- [GLM Coding Plan 脱敏契约](../contracts/glm/2026-08-28-coding-plan.sanitized.json)：不含真实凭据、账号或原始响应。
- [Issue #7 实现记录](2026-08-29-issue-7-glm-coding-plan-quota.md)：当前 Keychain、provider adapter 和 Android 展示边界。
