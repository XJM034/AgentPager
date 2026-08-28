# ZCode / GLM Gate 0 真实契约验证

日期：2026-08-28

范围：GitHub Issue #2（父 Issue #1 的 Gate 0）

分支：`alexx_custom`

## 结论

Issue #2 的真实契约验证已经执行。用户在完整知情的前提下，明确批准将“第一次 OAuth 刷新前没有既有凭据的字节级备份”作为一次性验收豁免，因此 Gate 0 最终状态为 **带用户批准的豁免通过**。

这项豁免不表示刷新前的原始凭据已经恢复，不证明 OAuth 刷新没有影响，也不放宽以后任何 ZCode 配置、凭据、钥匙串或 OAuth 操作必须先完成可恢复备份的要求。该不可逆事实继续保留在本报告中。

ZCode 桌面端的七类目标 Hook 事件均已通过真实会话捕获，GLM Coding Plan 的三个额度接口也已使用用户明确授权的个人套餐凭据验证。页面没有展示可与接口 `lite` 直接对应的标识，但 Issue #2 的要求是完成同时间对照并如实记录未知边界，而不是强行证明一一对应，因此该未知映射不是 Gate 0 失败项。

仓库只保存脱敏后的字段结构、状态序列与同一时间的额度对照，不保存提示词、命令、完整路径、工具输出、错误正文、真实标识符、凭据、Cookie 或账户信息。

本报告可以作为后续设计依据，但本次没有开始 #3 或任何后续产品功能。是否启动后续 Issue 必须由用户另行明确要求。以下冲突必须成为后续适配约束：

- 当前额度类型为 `CREDIT_LIMIT`，不能只接受旧插件代码中的 `TOKENS_LIMIT` 或 `TIME_LIMIT`。
- 无效凭据返回 HTTP 200，但 JSON 业务状态是 `success=false`、`code=401`；不能只判断 HTTP 状态。
- 本次两个额度的 `remaining` 都比 `usage - currentValue` 少 1；不能在客户端自行重算剩余额度。
- `Stop` 只能证明当前模型轮次结束，不能单独证明会话正常结束、被中断或已经终态。
- Bash 非零退出码在本次实测中仍产生 `PostToolUse`；不能据此推导 `PostToolUseFailure`。

## Gate 0 验收矩阵

| Issue #2 验收项 | 结果 | 证据与边界 |
| --- | --- | --- |
| 修改配置或使用 Key 前明确授权并创建可恢复备份 | 带豁免通过 | 用户已明确授权；临时 Hook 配置原状态为不存在并已恢复。既有 ZCode 凭据被意外 OAuth 刷新前没有字节级备份，无法追溯补救；用户明确批准仅对此历史过程缺口作一次性豁免。 |
| 全新 Session 捕获七类事件 | 通过 | `SessionStart`、`UserPromptSubmit`、`PreToolUse`、`PermissionRequest`、`PostToolUse`、`PostToolUseFailure`、`Stop` 均已在真实桌面会话捕获。 |
| ID、工具、权限 stdout、超时和 Stop 语义 | 通过 | Session ID、`tool_use_id`、Bash/Read 分类、allow/deny/ask、Hook 超时回退及 Stop 边界均已记录；无法证明的终态语义保留为未知。 |
| 使用用户 Key 查询官方插件接口且不泄露敏感内容 | 通过 | 三个接口均完成脱敏读取；Key、认证头和原始敏感响应未进入日志、测试输出或 Git。 |
| 同时间对照窗口、percentage、重置时间、套餐标识和错误 | 通过 | 5 小时与周额度、已使用百分比和重置时间一致；无效凭据业务层 401 已验证；页面“个人编程套餐”与 API `lite` 已完成对照但稳定映射未知。 |
| 仓库保留脱敏样本、步骤和结论，并阻止冲突假设继续扩散 | 通过 | 两份契约样本和本报告已提交；`CREDIT_LIMIT`、业务层 401、`remaining` 独立值和 Stop 边界均被记录为后续约束。 |
| 产物不包含用户敏感内容 | 通过 | 不含 prompt 全文、完整路径、Key、Cookie、认证头或可识别个人账号信息。 |

脱敏样本：

- [ZCode Hook 契约](../contracts/zcode/2026-08-28-zcode-hooks.sanitized.json)
- [GLM Coding Plan 契约](../contracts/glm/2026-08-28-coding-plan.sanitized.json)

## 授权与保护措施

- 用户在测试前明确回复“授权”，并确认使用 Coding Plan 套餐。
- 测试开始时用户级 ZCode CLI 配置文件不存在，因此记录“原状态为不存在”，临时验证结束后恢复为不存在。
- 套餐凭据只临时进入 macOS 钥匙串和查询进程内存；Hook/接口原始输入均先脱敏再落盘。
- 页面截图包含头像和账户界面，只用于人工比对，不进入仓库。
- 没有改动项目已有未提交文件，没有推送、创建 PR、发布 Release 或安装产品构建。
- 用户随后明确批准将第一次 OAuth 刷新前缺少字节级备份作为一次性验收豁免，并要求继续保留不可逆事实。

有一项无法宣称完全回滚的副作用：ZCode CLI 0.16.5 的 `login` 帮助文本看起来接受参数，但实测忽略参数并启动了官方 OAuth 登录流程，随后刷新了用户已有的 ZCode 凭据文件。调用前该凭据文件已存在，但没有为其制作字节级备份，因此无法恢复刷新前的原始字节，也不能证明刷新没有影响。用户批准的豁免只允许据此完成本次 Gate 0 验收，不改变这一历史事实。临时 CLI 配置和临时钥匙串项已单独清理；后续不应使用该 `login` 形式注入 Coding Plan Key。

## ZCode Hook 验证

### 环境与方法

- ZCode Desktop：3.10.1（Build 6272）。
- 内置 CLI：0.16.5。
- 在用户级临时配置中为七类事件注册同一个捕获器，每次修改权限行为后都开启新会话。
- 捕获器从标准输入读取事件，仅写入字段名、字段类型、字段形状、布尔存在性和临时伪标识；原始 JSON 不落盘。
- 用可控 Bash、缺失文件 Read、Hook allow、deny 和 timeout 场景建立状态序列。

### 已确认契约

七类事件均出现：

1. `SessionStart`
2. `UserPromptSubmit`
3. `PreToolUse`
4. `PermissionRequest`
5. `PostToolUse`
6. `PostToolUseFailure`
7. `Stop`

同一会话内 `session_id` / `sessionId` 保持一致；同一次工具调用的 `tool_use_id` 在 `PreToolUse`、`PermissionRequest` 和对应的后置事件之间保持一致。真实负载同时出现多组 snake_case 与 camelCase 别名，但 `tool_use_id` 本次只观察到 snake_case。

权限 Hook 的标准输出行为实测如下：

- `PreToolUse` 返回 `hookSpecificOutput.permissionDecision=ask` 后进入 `PermissionRequest`。
- `PermissionRequest` 返回 `decision.behavior=allow` 后工具执行并产生后置事件，未出现 macOS 系统权限弹窗。
- 返回 `decision.behavior=deny` 后工具没有执行，也没有产生后置事件，随后出现 `Stop`。
- Hook 配置 1500 毫秒超时而处理器等待 2500 毫秒时，ZCode 记录 Hook 失败并退回会话内“需要权限”卡片；这不是 macOS 系统弹窗。用户在卡片中允许后，工具执行并产生 `PostToolUse`。

缺失文件的 `Read` 调用产生 `PostToolUseFailure`，其中错误字段存在，但错误正文没有保存。相反，Bash 进程非零退出仍产生 `PostToolUse`。

`Stop` 中观察到 `stop_hook_active=false` 和助手消息相关字段，但没有观察到 `SessionEnd`。因此后续状态机只能把它当作“模型轮次停止”信号，不能直接写成“会话已正常完成”。

CLI/桌面边界也已确认：内置 CLI 在 `ask` 决策后报告没有 permission client，无法完成 `PermissionRequest` 交互；完整权限流程必须在 ZCode Desktop 中验证。项目级 Hook 还受到工作区信任/功能开关限制，本次真实验证使用用户级临时 Hook。

## GLM Coding Plan 验证

### 已验证接口

以下官方插件使用的接口各请求一次，原始响应只在进程内解析：

- `GET /api/monitor/usage/model-usage`
- `GET /api/monitor/usage/tool-usage`
- `GET /api/monitor/usage/quota/limit`

三个有效凭据请求均返回 HTTP 200 和 JSON 包装层 `code`、`data`、`msg`、`success`。模型/工具使用接口的实际数值没有保存，只记录字段与数组长度。额度接口保存了经过授权的单次匿名快照，以便验证页面语义。

### 同一时间页面对照

页面在 14:54（Asia/Shanghai）显示：

| 周期 | 页面 | 14:55 接口 | 结果 |
| --- | --- | --- | --- |
| 5 小时 | 102 / 2000，已使用 5%，16:03 重置 | `currentValue=102`、`usage=2000`、`percentage=5`、16:03:43 重置 | 一致 |
| 周 | 102 / 10000，已使用 1%，2026-09-04 10:58 重置 | `currentValue=102`、`usage=10000`、`percentage=1`、2026-09-04 10:58:05 重置 | 一致 |
| 套餐标识 | 个人编程套餐 | `level=lite` | 页面未显示 `lite`，映射待确认 |

由此确认 `percentage` 表示“已使用百分比”，不是“剩余百分比”；`unit=3, number=5` 对应 5 小时额度，`unit=6, number=1` 对应周额度。本次接口套餐等级字段为 `lite`，页面只显示“个人编程套餐”，没有暴露 `lite` 标识，因此二者是否一一对应仍是未知项。

套餐字段的后续契约为：`level` 是可选、不透明的上游值；不能根据 `lite` 或额度数值反推面向用户的套餐名。只有获得单独验证的显示名称时才使用该名称，否则统一回退为“GLM Coding Plan”。套餐映射未知已经按 Issue #2 要求记录，不构成 Gate 0 阻塞。

两个额度的服务器 `remaining` 分别是 1897 和 9897，而简单相减会得到 1898 和 9898。后续实现必须把 `remaining` 当作独立服务器字段，并允许它与其他值存在短暂或舍入差异。

用合成无效凭据验证时，服务仍返回 HTTP 200 JSON，但业务层返回 `success=false` 和 `code=401`。错误消息只记录“存在”，未保存正文。

## 可复现步骤

1. 记录用户级 ZCode 配置是否存在；如存在，先制作权限受限的备份。
2. 使用只写脱敏结构的捕获器注册七类 Hook；不要把标准输入原文写入日志。
3. 每种权限策略开启全新 ZCode Desktop 会话，依次验证允许、拒绝、超时和真实工具失败。
4. 对事件按会话和 `tool_use_id` 分组，只持久化字段名、类型、顺序和替代标识。
5. 将 Coding Plan Key 放在进程外安全存储中，查询进程只通过环境变量读取；禁止输出请求头和响应原文。
6. 分别查询三个接口，并在内存中投影为脱敏字段结构。
7. 在同一分钟刷新个人用量页面，对照 5 小时/周额度、百分比方向和重置时间。
8. 使用合成无效凭据验证业务错误包装；不要主动制造真实账户锁定、额度耗尽或限流。
9. 恢复原 ZCode 配置、删除临时凭据与临时捕获文件，再运行仓库敏感信息检查。

## 未验证边界与后续保护条件

本 Issue 不继续处理父 Issue 中的后续实现。以下内容仍是已知未知边界，但不影响本次带豁免通过的 Gate 0 判定：

- 真实 403、429、额度耗尽、套餐过期、5xx、网络超时和非 JSON 响应。
- 团队套餐与更高等级套餐的数据形状。
- 页面“个人编程套餐”与接口 `level=lite` 是否为稳定的一一映射。
- ZCode 后续版本是否继续同时提供 snake_case / camelCase 字段。
- `Stop` 之外是否有可稳定订阅的会话终态事件。

如果后续实现与本记录的 `CREDIT_LIMIT`、业务层 401、`remaining` 独立字段、套餐名回退策略或 `Stop` 语义冲突，应停止对应后续 Issue，先更新契约设计，不能沿用旧假设继续开发。

## Issue #2 关闭判断

Issue #2 的七项验收要求已有逐项证据；唯一不能追溯补救的事前备份缺口已由用户在保留全部风险事实的前提下明确批准一次性豁免。因此 Issue #2 可以诚实地按“带用户批准的豁免通过”关闭。

本地工作没有自行关闭 GitHub Issue、修改 Issue 状态或开始 #3；关闭动作仍由用户决定或另行明确授权。

## 参考来源

- ZCode 官方 Hook 文档：<https://docs.z.ai/devpack/tool/zcode/hooks>
- ZCode 官方插件 Hook 示例（固定提交）：<https://github.com/zai-org/zcode-plugins/tree/e2d4b3751102877ea2caf32f6ca6533bdcaa5e79/plugins>
- GLM Coding Plan 官方用量插件查询脚本（固定提交）：<https://github.com/zai-org/zai-coding-plugins/blob/0446d0bb26e0f02df628b24f19ef4a61dd44bcfb/plugins/glm-plan-usage/skills/usage-query-skill/scripts/query-usage.mjs>
