# PRD：ZCode（GLM）会话监控与 GLM Coding Plan 额度显示

> 状态：历史产品基线；后续 Issue 已改变部分契约，本文不再作为现行验收清单。
> 日期：2026-08-28
> 产品范围：macOS AgentPager Bridge、Android AgentPager，以及跨平台协议兼容层。
> 术语约定：本 PRD 使用“ZCode 会话”指智谱 ZCode 编码 Agent 的会话；使用“GLM 额度”指 BigModel.cn GLM Coding Plan 的套餐额度。两者相关，但不是同一种数据。

> 当前依据：`Stop` 已实测并收敛为非终态 `idle`，参见
> [Issue #4 实施记录](2026-08-28-issue-4-zcode-session-monitoring.md)；GLM 独立 Key
> 路径参见 [Issue #7 实施记录](2026-08-29-issue-7-glm-coding-plan-quota.md)；复用 ZCode
> 登录态且不重复提供 Key 的要求仍受
> [Issue #12 Gate](2026-08-29-issue-12-no-duplicate-key-glm-quota-gate.md) 阻塞。

## Problem Statement

AgentPager 当前可以在 Android 端显示 Codex Desktop、Codex CLI 和 Claude Code 的任务状态，也能显示 Codex 的 General、Spark 额度，但用户在 ZCode 中使用 GLM Coding Plan 编程时仍存在两个信息断点：

1. ZCode 会话不进入 AgentPager。用户离开 Mac 后，无法从旧 Android 手机上看到 ZCode 是否刚开始、正在思考、正在使用工具、等待权限或已经完成。
2. GLM Coding Plan 额度不进入 AgentPager。用户必须登录 BigModel.cn 页面或在其他工具中查询，无法和 Codex 额度放在同一块常亮信息屏上比较。

用户需要的不是新的 ZCode 客户端，也不是让 AgentPager 接管 ZCode，而是在现有“Mac Bridge 收集状态、Android 只负责展示与有限控制”的产品边界内，增加一个与 Codex、Claude Code 一致的 ZCode 会话来源，并增加一组可安全降级的 GLM Coding Plan 额度数据。

当前最大风险不是界面能否画出来，而是两个上游能力的稳定性不同：ZCode 已公开七类 Hook，可支撑核心会话状态；GLM 额度接口虽然被官方插件实际使用，但没有公开的稳定响应 Schema 和版本承诺。因此产品必须明确区分“确定状态”“推断状态”“数据暂不可用”，不能为了填满界面而误报完成、0% 或 100%。

## Solution

在现有 AgentPager 任务终端中增加 ZCode 来源，在现有额度仪表中增加 GLM Coding Plan 提供方，并保持当前像素终端设计语言、局域网架构和隐私边界。

### 用户可见结果

- 用户启动 ZCode 新会话后，Android 任务列表出现一条带 `ZCode` 徽标的任务。
- 任务继续使用当前像素核心、状态色、排序、自动展开、声音、振动和亮度策略，不创建 ZCode 专属任务页面。
- ZCode 的开始、思考、读取、搜索、编辑、执行、测试、协作、等待批准、工具失败和本轮结束会映射到现有状态语言。
- 当 ZCode 请求工具权限时，Android 任务自动置顶并展开，用户可以批准或拒绝本次请求。
- 顶部额度区在 `GENERAL`、`SPARK` 之后增加一个同高的 `GLM` 紧凑额度块，展示可用的 5 小时与每周窗口。
- 额度详情页增加 `CODEX / GLM` 提供方切换，Codex 现有视图保持不变；GLM 视图展示套餐、窗口、剩余比例、刷新时间、更新时间和数据状态。
- GLM 数据缺失、过期、鉴权失败或上游格式变化时，界面显示明确状态并保留最后一次可信值；绝不把失败显示成额度耗尽。
- macOS Bridge 设置中增加 GLM 集成区，用于安装或修复 ZCode Hook、保存 Coding Plan Key、验证连接、刷新额度和卸载集成。

### 设计原则

- 延展而不重做：继续使用深黑背景、深蓝表面、像素字体、直角容器、细分隔线和现有状态色。
- 状态优先：会话任务仍是主内容，新增额度块不得下压或遮挡第一条任务。
- 读数诚实：有可信数值才显示百分比；未知、过期和错误使用文案表达，不用伪造进度条。
- 来源清楚：任务显示 `ZCode`，额度显示 `GLM`，避免把模型套餐和 Agent 会话混为一谈。
- 本地优先：Key、原始 Hook 输入和上游响应留在 Mac；Android 只接收完成裁剪的数据。
- 可恢复：安装和卸载 ZCode Hook 必须保留用户原配置并创建备份；GLM 查询失败不得影响会话状态同步。

### 设计延展决策

- ZCode 任务徽标使用现有青色作为来源强调色，不新增品牌色；任务生命周期仍由现有状态色决定。
- 顶部 `GLM` 额度块固定为现有 28dp 高度，采用现有 8sp 标签、11sp 百分比和 2dp 进度线；5 小时与每周窗口用现有分隔线分开。
- 顶部顺序固定为 `GENERAL`、`SPARK`、`GLM`、额度页切换按钮、设置按钮；缺少某一数据组时不显示空占位。
- `GLM` 额度正常时使用青色；剩余低于 20% 使用橙色，低于 10% 使用红色，与现有额度警示一致。
- 额度详情页不增加新的全屏路由。在当前页面的额度面板中增加 `CODEX / GLM` 直角选择器，并保持当前左右双栏结构。
- 选择 `CODEX` 时，现有 Codex 额度和 Token 历史视图完全保留。
- 选择 `GLM` 时，左侧显示套餐和核心额度窗口；右侧只在官方明细契约完成验证后显示模型或工具用量图表。未验证前显示额度规则、刷新状态和最近一次成功更新时间，不画假图表。
- GLM 尚未配置时，顶部不显示 `GLM` 额度块；详情页可选择 GLM 并看到“尚未连接 GLM Coding Plan”的设置引导。
- GLM 已配置但当前请求失败时，顶部显示最后一次可信值并附带过期语义；没有可信历史值时显示 `--%` 和“暂不可用”。
- 所有新增控件继续提供中文无障碍描述，不能只依赖颜色区分提供方、额度健康度或错误状态。

## User Stories

1. As an AgentPager 用户, I want ZCode 会话自动出现在任务列表, so that 我不必一直盯着 Mac 才知道 GLM Agent 是否正在工作。
2. As an AgentPager 用户, I want 一眼区分 ZCode、Codex 和 Claude Code, so that 多个 Agent 同时运行时不会认错来源。
3. As an AgentPager 用户, I want ZCode 新会话显示“正在启动”, so that 我能确认 Hook 已经捕获任务。
4. As an AgentPager 用户, I want 提交 ZCode prompt 后看到“正在思考”, so that 我知道请求已经进入执行链路。
5. As an AgentPager 用户, I want ZCode 读取文件时看到“正在读取”, so that 我能理解 Agent 当前阶段。
6. As an AgentPager 用户, I want ZCode 搜索内容时看到“正在搜索”, so that 我能区分查找和实际修改。
7. As an AgentPager 用户, I want ZCode 修改文件时看到“正在编辑”, so that 我能及时关注高影响操作。
8. As an AgentPager 用户, I want ZCode 运行命令时看到“正在执行”, so that 我知道任务并非卡住。
9. As an AgentPager 用户, I want ZCode 运行测试时看到“正在测试”, so that 我能判断任务是否进入验证阶段。
10. As an AgentPager 用户, I want ZCode 调用 Agent 工具时看到“正在协作”, so that 即使第一版没有独立子代理详情，我仍知道它正在并行处理。
11. As an AgentPager 用户, I want 任务卡展示项目名和简短标题, so that 多个 ZCode 会话同时出现时仍能快速定位。
12. As an AgentPager 用户, I want 标题缺失时由首条 prompt 生成稳定的临时标题, so that 第一版不依赖私有数据库也保持可读。
13. As an AgentPager 用户, I want 当前工具步骤经过清洗和截断, so that 手机能提供上下文而不会泄露完整命令、源码或内部路径。
14. As an AgentPager 用户, I want 单次工具失败不会把整个会话误报为中断, so that 我不会被错误提醒干扰。
15. As an AgentPager 用户, I want ZCode 本轮准备结束时看到“任务完成”, so that 我能及时返回查看结果。
16. As an AgentPager 用户, I want 不确定的中断原因被保守处理, so that AgentPager 不会把崩溃、取消或正常结束混为一谈。
17. As an AgentPager 用户, I want ZCode 权限请求自动置顶并展开, so that 我不会错过需要处理的阻塞事项。
18. As an AgentPager 用户, I want 在手机上批准一次 ZCode 权限请求, so that 我离开 Mac 时仍能让任务继续。
19. As an AgentPager 用户, I want 在手机上拒绝一次 ZCode 权限请求, so that 我能阻止不希望执行的操作。
20. As an AgentPager 用户, I want 同一会话的多个权限请求分别关联, so that 一个回答不会错误作用到另一项工具调用。
21. As an AgentPager 用户, I want 重复点击或过期回答得到明确反馈, so that 我不会误以为权限仍然生效。
22. As an AgentPager 用户, I want Bridge 离线时 ZCode Hook 快速放行到本地体验, so that AgentPager 故障不会卡死 ZCode。
23. As an AgentPager 用户, I want ZCode 状态继续遵循现有任务优先级, so that 等待批准、运行和完成任务的排序保持熟悉。
24. As an AgentPager 用户, I want ZCode 完成、等待批准和异常沿用现有声音与振动规则, so that 我不需要学习另一套提醒语言。
25. As an AgentPager 用户, I want ZCode 任务遵循现有亮度策略, so that 常亮终端在活跃和空闲时保持一致体验。
26. As an AgentPager 用户, I want 顶部同时看到 Codex 和 GLM 额度, so that 我能决定接下来把任务交给哪个 Agent。
27. As a GLM Coding Plan 用户, I want 看到 5 小时窗口剩余比例, so that 我能避免短时额度突然触顶。
28. As a GLM Coding Plan 用户, I want 看到每周窗口剩余比例, so that 我能规划本周剩余开发任务。
29. As a GLM Coding Plan 用户, I want 看到套餐名称或通用 Coding Plan 标识, so that 我知道当前读数属于哪个订阅。
30. As a GLM Coding Plan 用户, I want 看到每个额度窗口的刷新时间, so that 我知道何时可以继续高强度使用。
31. As a GLM Coding Plan 用户, I want 看到数据最后更新时间, so that 我能判断百分比是否仍然可信。
32. As a GLM Coding Plan 用户, I want 低额度变成橙色或红色, so that 我在远处也能注意到风险。
33. As a GLM Coding Plan 用户, I want 接口失败时保留最后一次可信读数并标记过期, so that 短时网络问题不会让信息完全消失。
34. As a GLM Coding Plan 用户, I want 从未成功读取时看到“暂不可用”而不是 0%, so that 我不会误判套餐已经耗尽。
35. As a GLM Coding Plan 用户, I want 鉴权失效时看到明确的重新连接提示, so that 我知道需要在 Mac 端更新 Key。
36. As a GLM Coding Plan 用户, I want Bridge 定时低频刷新额度, so that 数据足够新又不会频繁触发未公开接口。
37. As a GLM Coding Plan 用户, I want 打开 Bridge 或重新连接手机时自动刷新, so that 常用场景无需手动操作。
38. As a GLM Coding Plan 用户, I want 在 Mac 设置中手动刷新并验证连接, so that 我能主动确认配置是否正常。
39. As a GLM Coding Plan 用户, I want Android 上永远不保存 Coding Plan Key, so that 手机丢失或日志导出不会暴露调用凭据。
40. As a macOS 用户, I want Coding Plan Key 保存在系统安全存储中, so that 它不会以明文写进项目、配置或日志。
41. As a macOS 用户, I want 安装 ZCode Hook 前自动备份原配置, so that 出现兼容问题时可以恢复。
42. As a macOS 用户, I want 安装 ZCode Hook 保留所有已有字段与第三方 Hook, so that AgentPager 不会破坏现有工作流。
43. As a macOS 用户, I want 重复执行“安装或修复”不会叠加 Hook, so that 配置保持幂等和可维护。
44. As a macOS 用户, I want 卸载时只删除 AgentPager 管理的 ZCode Hook, so that 其他 ZCode 配置不受影响。
45. As a macOS 用户, I want 删除 GLM Key 后立即停止远程额度查询, so that 我可以清楚撤销授权。
46. As a 用户, I want 额度查询失败不影响会话同步、配对和审批, so that 次要能力不会拖垮核心终端。
47. As a 用户, I want GLM 额度与 ZCode 会话使用同一套像素设计语言, so that 新功能看起来是 AgentPager 的自然延展。
48. As a 用户, I want 顶部额度块保持单行且不遮挡第一条任务, so that 新增第三组额度后主页密度仍然稳定。
49. As a 用户, I want 在额度详情页切换 CODEX 和 GLM, so that 多提供方数据不会挤成难读的一张面板。
50. As a 用户, I want Codex 现有 General、Spark 和历史用量保持不变, so that 新增 GLM 不会造成已有功能回归。
51. As a 用户, I want 旧 Bridge 或缺少 GLM 数据时 Android 仍能展示 Codex, so that 部分升级不会导致整页空白。
52. As a 用户, I want 新 Bridge 发送未知额度类型时客户端保守展示或忽略, so that 上游套餐调整不会破坏整个状态快照。
53. As a 用户, I want 未知 ZCode Hook 事件只刷新时间而不改变生命周期, so that ZCode 新增事件时不会被误判。
54. As a 用户, I want 诊断页只显示脱敏状态和错误类别, so that 排障不需要暴露 prompt、Key 或完整响应。
55. As a 开发者, I want 用一个高层端到端接缝验证 Hook、Bridge、协议、Android 模型和审批回路, so that 测试关注真实外部行为而不是内部实现细节。
56. As a 开发者, I want 用脱敏的真实额度响应建立契约样本, so that 当前积分制字段方向和窗口含义得到验证。
57. As a 开发者, I want 未知字段、缺失字段和错误响应有固定降级行为, so that 官方接口变化时产品仍然诚实可用。
58. As a 维护者, I want macOS、Android 和 Windows 共享协议模型保持同步, so that 新来源和额度字段不会造成跨平台协议分叉。
59. As a 维护者, I want ZCode 和 GLM 适配器与 Codex、Claude 逻辑隔离, so that 上游变化只影响对应提供方。
60. As a 维护者, I want 所有新增功能可以独立关闭或卸载, so that 遇到兼容问题时能够快速回滚。

## Implementation Decisions

1. 会话来源使用 `ZCode` 作为产品与协议语义，不使用笼统的 `GLM 会话`。GLM 只用于套餐和额度语义。
2. 现有 ZCode Desktop 会话的主数据源是官方同步 Hook。第一版不使用 `app-server` 托管、私有 SQLite、rollout JSONL、窗口 OCR 或进程观察作为主要状态源。
3. ZCode 适配器覆盖七类官方事件：SessionStart、UserPromptSubmit、PreToolUse、PermissionRequest、PostToolUse、PostToolUseFailure、Stop。
4. 状态归约采用现有 Agent 生命周期和活动类型，不新增 ZCode 专属状态枚举。事件映射为：
   - SessionStart → starting / thinking；
   - UserPromptSubmit → running / thinking；
   - PreToolUse → running，并按工具映射 reading、searching、editing、executing、testing、browsing 或 delegating；
   - PermissionRequest → waitingApproval，并开放 approve、deny；
   - PostToolUse → running / thinking；
   - PostToolUseFailure → 保持 running，展示脱敏错误步骤；
   - Stop → 暂映射 succeeded，最终语义以真实会话验证为准。
5. 未知事件和未知工具名采用保守回退：未知事件不改变生命周期；未知工具显示 thinking 或通用执行文案。
6. ZCode 标题第一版由项目名和首条用户 prompt 派生，不读取私有会话数据库。标题必须截断并清洗。
7. ZCode 子代理第一版不建立独立 SubagentSnapshot。识别到 Agent/Task 工具时只把主任务活动显示为“正在协作”。
8. 权限请求使用“来源 + Session ID + tool_use_id”形成稳定请求标识。待处理连接和手机控制不能继续只按 Session ID 索引。
9. 待审批协议增加可选的 pending request ID，Android 提交批准或拒绝时必须携带该 ID。旧来源缺少 tool_use_id 时允许回退为单会话单请求，但不得覆盖已经存在的不同请求。
10. ZCode 权限响应只支持本次 allow 或 deny。第一版不允许手机更新工具输入、写永久权限或绕过 Plan 模式和工具硬限制。
11. Hook 等待必须有明确超时。Bridge 不在线、请求无法登记或手机断开时，Hook 快速返回无裁决，让 ZCode 回到本地审批路径，不能无限阻塞。
12. ZCode Hook 安装器使用用户级配置，保留所有现有字段与 Hook，只替换 AgentPager 自己的管理项；修改前备份，卸载只删除管理项，重复安装幂等。
13. ZCode Hook 配置变更后必须通过新建 Session 验证，因为现有 Session 不保证热加载更新。
14. ZCode 来源加入共享任务协议，macOS、Android 和 Windows 的协议模型同步更新。Windows 第一版只保持解析与转发兼容，不实现 ZCode Hook 安装或 GLM 查询。
15. 新来源对旧 Android 客户端不是天然安全的，因为未知枚举可能导致整条快照解码失败。定制版发布时 macOS Bridge 与 Android 必须成对升级；同时为未来未知来源增加容错模型，避免再次扩大该问题。
16. GLM 额度由 macOS Bridge 查询，Android 不直接访问 BigModel.cn，不保存 Key，也不复用网页 Cookie。
17. Coding Plan Key 由用户在 macOS GLM 设置中主动输入，保存到系统安全存储。不得自动扫描 shell 历史、浏览器 Cookie、项目文件或 ZCode 私有数据库寻找凭据。
18. GLM 额度查询封装在独立提供方适配器中。上游接口、鉴权格式、字段解析和错误映射不能散落到 Bridge、协议和 Android UI。
19. MVP 以官方插件使用的 quota/limit 接口作为额度主数据源。model-usage 与 tool-usage 只有在 Gate 0 真实响应契约验证后才进入明细或趋势；不因界面需要而假设字段。
20. 内部额度模型从 Codex 单一快照扩展为“提供方列表”。每个提供方至少包含 provider ID、显示名、套餐名、采集时间、状态、额度组和窗口；历史用量为可选能力。
21. 跨平台状态快照增加可选的多提供方额度字段，同时保留现有 Codex 旧字段作为兼容读取路径。Android 优先读取新字段，没有时回退现有 Codex 数据。
22. 每个额度窗口保留 usedPercentage 与 remainingPercentage，并以 remainingPercentage 作为 UI 读数。Gate 0 必须确认官方 percentage 的方向，不能根据字段名或旧插件 UI 猜测。
23. 5 小时、每周和未来未知窗口都由上游响应归一化；不得根据 Lite、Pro、Max 名称写死总量、窗口数量或周额度存在性。
24. GLM 没有返回套餐名时显示“GLM Coding Plan”，不能根据额度数值反推套餐。
25. GLM 刷新时机与现有 Bridge 节奏对齐：Bridge 启动、手机新连接、Mac 设置手动刷新，以及每 10 分钟低频轮询。错误时指数退避，成功后恢复正常周期。
26. 同一时间只允许一个 GLM 额度请求在途，避免重复连接和轮询重叠。额度请求在独立任务中执行，不阻塞 Hook 端口、WebSocket 广播或任务归约。
27. 最后一次成功快照与当前错误状态分开保存。暂时错误保留可信旧值并标记陈旧；鉴权错误要求用户重新连接；未知 Schema 隐藏数值并记录脱敏诊断。
28. 401、403、429、业务额度错误、套餐过期、超时和 5xx 分别映射，不统一显示成“额度用尽”。只有官方明确返回额度耗尽语义时才显示耗尽。
29. 原始 API 响应、完整 prompt、完整 tool_input、tool_response、认证请求头和 Key 不进入 Android 协议，不写入普通日志，也不进入任务持久化快照。
30. Android 继续复用现有任务排序、自动展开、PixelCore 动画、通知声音、振动、设置和亮度策略。新增来源不得建立第二套任务投影。
31. 顶部额度展示从“挑选 General 和 Spark”扩展为按固定优先级选择现有组：General、Spark、GLM。最多显示三组，不换行；缺失组不占位。
32. 额度详情页增加提供方选择状态。默认选择上次用户选择；无历史选择时优先 Codex，只有 GLM 数据时选择 GLM。
33. Android 的百分比、重置时间、更新时间、低额度颜色和无数据文案继续由纯展示层转换函数生成，UI 组件不直接解释上游字段。
34. macOS 设置增加独立 GLM 集成区，包含 ZCode Hook 状态、安装/修复、卸载、Key 状态、保存并验证、手动刷新、删除 Key、最后成功时间和脱敏错误。
35. macOS 菜单栏可增加“安装或修复 ZCODE HOOK”快捷入口，但凭据配置和详细错误只在设置页展示，避免菜单过长。
36. 诊断事件只记录来源、事件类别、生命周期、请求结果和错误类别，不记录用户内容或凭据。
37. 会话监控与额度显示分别可用：没有 Key 时 ZCode 会话仍工作；没有 Hook 时 GLM 额度仍可显示；任何一方失败不得清空另一方数据。
38. 第一版不增加云后端、遥测、账号体系或生产数据上传，继续使用现有可信局域网签名协议。

## Testing Decisions

### 主测试接缝

采用一个最高层的本地端到端接缝作为主要验收入口：模拟 ZCode Hook 进程向真实 Bridge 发送事件，模拟 Android 客户端通过现有 WebSocket 接收状态并发送签名控制，同时向可替换的 GLM 用量客户端提供脱敏固定响应。

这个接缝必须一次验证以下外部行为：

- ZCode SessionStart 和 PreToolUse 变成 Android 可解码的 ZCode running 任务；
- PermissionRequest 变成 waitingApproval 和唯一 pending request；
- Android 的签名 approve/deny 返回正确的 ZCode stdout JSON；
- Stop 收敛为终态；
- 同一状态快照同时带有 GLM 5 小时和每周额度；
- GLM 请求失败不会停止 Hook 状态、WebSocket 或审批回路；
- 关闭客户端连接后 Bridge 仍存活。

该接缝沿用项目现有本地 E2E 思路，只扩展来源和可替换的额度适配器，不再创建多套重叠的集成脚本。

### 模块级测试

1. ZCode Hook payload 解码测试覆盖七类官方事件、camelCase/snake_case 兼容字段、未知字段和缺失可选字段。
2. ZCode reducer 测试只断言外部 TaskSnapshot 行为：生命周期、活动、标题、步骤、能力和完成时间；不锁定内部函数调用。
3. 工具活动映射和 ToolStepSanitizer 测试覆盖命令、文件、搜索、浏览、测试、Agent 工具及敏感字段清洗。
4. Hook 配置测试沿用 Codex/Claude 先例，覆盖保留用户配置、自动备份、幂等安装、只删除管理项、恢复备份和无效 JSON。
5. 权限关联测试覆盖同一 Session 连续或并发的两个 tool_use_id，保证批准不会串单。
6. 权限超时测试覆盖 Bridge 不在线、手机断线、重复回答和过期请求，并断言 ZCode 不被无限阻塞。
7. GLM 客户端契约测试使用脱敏固定样本，覆盖 5 小时、每周、历史套餐、未知额度类型和百分比方向。
8. GLM 错误映射测试覆盖 401、403、429、套餐过期、额度耗尽、5xx、超时、非 JSON、字段缺失和 Schema 漂移。
9. GLM 快照测试覆盖保留最后成功值、陈旧标记、无历史值时不显示 0%、并发刷新合并和退避恢复。
10. 协议测试覆盖 ZCode 来源、pending request ID、多提供方额度、旧 Codex 字段回退和毫秒时间编码。
11. Android 展示转换测试覆盖 General、Spark、GLM 排序、三组顶部额度、低额度颜色、刷新文案、无配置、过期和暂不可用。
12. Android 任务投影测试确认 ZCode waitingApproval 仍置顶并自动展开，完成任务仍按现有 90 秒节奏切换额度页。
13. Windows 协议测试至少确认新来源和可选额度字段可解码，避免跨平台协议模型分叉。

### 视觉与设备验证

1. 为 ZCode running、waitingApproval、succeeded 和 GLM 正常、低额度、过期、未配置状态增加 Compose Preview。
2. 在 medium_phone 横屏模拟器验证三组顶部额度与右侧两个按钮同高、无换行、不遮挡任务首行。
3. 用已有 General/Spark 真机截图作为布局基线，对比新增 GLM 后的任务起点、顶部总宽度、字号、进度线和状态色。
4. Redmi 真机验收任务列表、额度详情、自动置顶、批准/拒绝、声音、振动、常亮和亮度；模拟器不能替代这些厂商与硬件行为。
5. macOS 设置页人工验收五个标签的点击区域、GLM 面板滚动/布局、SecureField、错误文案和减少动态效果。
6. 真实 ZCode 新 Session 验证七类 Hook payload、Stop 语义、本地权限弹窗竞争、Hook 超时和 Agent 工具字段。
7. 用户明确授权后，用实际 BigModel 个人套餐做一次脱敏额度对照：Bridge 结果必须与官方用量页在同一时间点的方向、窗口和刷新语义一致。

### 通过标准

- 健康局域网中，ZCode Hook 事件在 2 秒内出现在 Android 状态快照。
- 用户点击批准或拒绝后，Bridge 在 2 秒内返回控制确认，并且裁决只作用于对应 tool_use_id。
- GLM 查询成功后，Android 显示相同的窗口、剩余方向和更新时间；查询失败时会话同步继续工作。
- 三组顶部额度在 medium_phone 与 Redmi 横屏都不遮挡首条任务，也不改变现有 28dp 顶栏节奏。
- Key 不出现在 Android 快照、普通日志、Git diff、测试输出或持久化任务文件中。
- Codex General/Spark、Claude Code 会话、配对、签名、任务排序、通知、亮度和现有 E2E 全部保持通过。

## Out of Scope

- 由 AgentPager 启动、托管、恢复或控制 ZCode `app-server` 会话。
- 从手机新建 ZCode 任务、发送后续 prompt、回答 AskUserQuestion、批准 Plan、停止或重试任务。
- 精确展示 ZCode 独立子代理的开始、结束、路径、Token 或层级关系。
- 把 ZCode 私有 SQLite、JSONL、临时 transcript、窗口 OCR 或进程列表作为正式数据源。
- 在第一版展示 ZCode 会话精确 Token；只有未来稳定辅助通道验证后才能加入。
- 在 GLM 明细 Schema 未验证前展示模型、MCP 或每日趋势图。
- 把旧官方插件中的“MCP 月额度”写成当前固定权益。
- 支持团队版或企业版 Coding Plan；第一版只以官方插件明确支持的个人版为验收对象。
- Android 直接保存 Key、直接请求 BigModel、使用 WebView 登录或抓取个人用量页面。
- 新增 AgentPager 云服务、遥测、远程账号、外部通知转发或互联网明文通信。
- 第一版在 Windows 安装 ZCode Hook 或查询 GLM 额度；Windows 只保持协议兼容。
- 自动启用 Yolo、修改永久权限规则或绕过 ZCode 自身安全限制。
- 推送、发布 Release、正式签名、公证或上游 PR。

## Further Notes

### 开发顺序

1. **Gate 0：真实契约验证。** 在用户明确授权后，备份 ZCode 配置并捕获七类脱敏 Hook 样本；使用用户 Coding Plan Key 对官方插件使用的额度接口做一次脱敏读取，并与官方用量页人工对照。Gate 0 不通过时停止涉及不确定字段的开发，但仍可开发确定的 Hook 基础模型与静态 UI。
2. **阶段 A：领域与协议。** 增加 ZCode 来源、ZCode Hook payload/reducer、唯一权限请求标识、多提供方额度模型，以及 macOS/Android/Windows 兼容解析。
3. **阶段 B：Bridge 集成。** 实现 ZCode Hook 安装器、事件接收、权限回传、GLM 安全存储、低频查询、错误降级和诊断状态。
4. **阶段 C：Android 体验。** 增加 ZCode 徽标、任务状态、三组顶部额度、CODEX/GLM 详情选择、无数据和错误状态。
5. **阶段 D：验证与安装。** 完成单元、协议、本地 E2E、Compose Preview、模拟器、Redmi 真机、真实 ZCode 会话和实际额度对照，再按项目现有备份流程安装 Bridge 与 APK。

### 主要风险

- GLM 额度接口是官方插件实际使用的接口，但不是有公开版本承诺的稳定 OpenAPI；适配器和降级路径是必需条件。
- ZCode Hook 没有 SessionEnd、SubagentStart/Stop、等待回答和反向 stop，第一版无法与 Claude Code 完全对齐。
- PermissionRequest Hook 与 ZCode 本地弹窗的并发、超时和先到先得行为仍需真实会话确认。
- 新 AgentSource 枚举会影响旧客户端解码，Bridge 和 Android 必须成对升级。
- 第三个顶部额度组可能在更窄的横屏设备上造成拥挤，必须以 medium_phone 和 Redmi 作为最低验收基线，并禁止换行覆盖任务区。

### 成功定义

- 用户可以只看 Android，就知道 ZCode 当前是否工作、在做什么、是否需要批准以及本轮是否结束。
- 用户可以在同一顶部区域比较 Codex 与 GLM 的剩余额度，并能识别数据是否新鲜可信。
- 任何 GLM 查询故障都不会影响 ZCode/Codex/Claude 会话监控、配对或手机审批。
- 新功能保持 AgentPager 现有像素终端设计语言，没有引入第二套导航、状态系统或云端依赖。
- 凭据和敏感会话内容不离开 Mac 的必要边界，安装和卸载均可恢复。

### Issue Tracker 发布状态

- 已发布：[GitHub Issue #1：ZCode（GLM）会话监控与 GLM Coding Plan 额度显示](https://github.com/XJM034/AgentPager/issues/1)
- 状态：Open
- 标签：`ready-for-agent`
- 发布时间：2026-08-28
