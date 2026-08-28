# ZCode / GLM Gate 0 真实契约验证

日期：2026-08-28

范围：GitHub Issue #2（父 Issue #1 的 Gate 0）

分支：`alexx_custom`

## 结论

Issue #2 的真实契约验证已经执行，但 Gate 0 **未完全通过**。ZCode 桌面端的七类目标 Hook 事件均已通过真实会话捕获，GLM Coding Plan 的三个额度接口也已使用用户明确授权的个人套餐凭据验证；但既有 ZCode 凭据被 CLI 意外刷新且没有事前字节级备份，官方页面也没有展示可与接口 `lite` 直接对应的套餐标识。因此父 Issue 的后续实现继续保持阻塞。

仓库只保存脱敏后的字段结构、状态序列与同一时间的额度对照，不保存提示词、命令、完整路径、工具输出、错误正文、真实标识符、凭据、Cookie 或账户信息。

已确认的部分可以作为后续设计依据，但在 Gate 0 缺口得到明确处置前不能开始后续 Issue。本次没有实现任何后续功能。以下冲突必须成为后续适配约束：

- 当前额度类型为 `CREDIT_LIMIT`，不能只接受旧插件代码中的 `TOKENS_LIMIT` 或 `TIME_LIMIT`。
- 无效凭据返回 HTTP 200，但 JSON 业务状态是 `success=false`、`code=401`；不能只判断 HTTP 状态。
- 本次两个额度的 `remaining` 都比 `usage - currentValue` 少 1；不能在客户端自行重算剩余额度。
- `Stop` 只能证明当前模型轮次结束，不能单独证明会话正常结束、被中断或已经终态。
- Bash 非零退出码在本次实测中仍产生 `PostToolUse`；不能据此推导 `PostToolUseFailure`。

脱敏样本：

- [ZCode Hook 契约](../contracts/zcode/2026-08-28-zcode-hooks.sanitized.json)
- [GLM Coding Plan 契约](../contracts/glm/2026-08-28-coding-plan.sanitized.json)

## 授权与保护措施

- 用户在测试前明确回复“授权”，并确认使用 Coding Plan 套餐。
- 测试开始时用户级 ZCode CLI 配置文件不存在，因此记录“原状态为不存在”，临时验证结束后恢复为不存在。
- 套餐凭据只临时进入 macOS 钥匙串和查询进程内存；Hook/接口原始输入均先脱敏再落盘。
- 页面截图包含头像和账户界面，只用于人工比对，不进入仓库。
- 没有改动项目已有未提交文件，没有推送、创建 PR、发布 Release 或安装产品构建。

有一项无法宣称完全回滚的副作用，也是本次 Gate 0 未完全通过的原因：ZCode CLI 0.16.5 的 `login` 帮助文本看起来接受参数，但实测忽略参数并启动了官方 OAuth 登录流程，随后刷新了用户已有的 ZCode 凭据文件。调用前该凭据文件已存在，但没有为其制作字节级备份，因此“事前可恢复备份”验收项未满足，也不能覆盖回退。临时 CLI 配置和临时钥匙串项已单独清理；后续不应使用该 `login` 形式注入 Coding Plan Key。

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

## 未验证与后续阻塞条件

本 Issue 不继续处理父 Issue 中的后续实现。以下内容仍是待确认边界：

- 真实 403、429、额度耗尽、套餐过期、5xx、网络超时和非 JSON 响应。
- 团队套餐与更高等级套餐的数据形状。
- 页面“个人编程套餐”与接口 `level=lite` 是否为稳定的一一映射。
- ZCode 后续版本是否继续同时提供 snake_case / camelCase 字段。
- `Stop` 之外是否有可稳定订阅的会话终态事件。

如果后续实现与本记录的 `CREDIT_LIMIT`、业务层 401、`remaining` 独立字段或 `Stop` 语义冲突，应停止对应后续 Issue，先更新契约设计，不能沿用旧假设继续开发。

## 参考来源

- ZCode 官方 Hook 文档：<https://docs.z.ai/devpack/tool/zcode/hooks>
- ZCode 官方插件 Hook 示例（固定提交）：<https://github.com/zai-org/zcode-plugins/tree/e2d4b3751102877ea2caf32f6ca6533bdcaa5e79/plugins>
- GLM Coding Plan 官方用量插件查询脚本（固定提交）：<https://github.com/zai-org/zai-coding-plugins/blob/0446d0bb26e0f02df628b24f19ef4a61dd44bcfb/plugins/glm-plan-usage/skills/usage-query-skill/scripts/query-usage.mjs>
