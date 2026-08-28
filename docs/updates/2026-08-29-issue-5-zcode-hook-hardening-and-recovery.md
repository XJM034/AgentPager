# Issue #5：补齐 ZCode 状态语义与可恢复 Hook 管理

日期：2026-08-29

分支：`alexx_custom`

可靠远端基线：`d5d26f7d3c34c12594bdc3da9c07d28d095360d4`

## 结果

Issue #5 已把 Issue #4 的最小 ZCode 会话链路补齐为七事件集成，并增加可恢复、并发保护和权限受限的 Hook 配置管理。真实验收使用全新 ZCode Desktop Session、调试 Bridge、正式设置界面和 Redmi 真机完成；结束后已经通过界面双确认恢复用户配置，并切回测试前的原 Bridge。

本实现没有增加手机端权限裁决、Hook 长等待或 ZCode stdout allow / deny 返回；这些能力继续属于 Issue #6。没有实现 GLM Key、额度查询或网络请求。

## 状态与脱敏语义

七类官方事件均已通过自动化测试和真实新 Session 验证：

| ZCode 事件 | AgentPager 投影 | 验收结论 |
| --- | --- | --- |
| `SessionStart` | `starting / thinking` | 通过 |
| `UserPromptSubmit` | `running / thinking` | 通过 |
| `PreToolUse` | `running` 加安全工具活动 | 通过 |
| `PermissionRequest` | `waitingApproval`，仅观察本地等待 | 通过 |
| `PostToolUse` | `running / thinking` | 通过 |
| `PostToolUseFailure` | 保持 `running`，显示脱敏失败类别 | 通过 |
| `Stop` | `idle` 非终态 | 通过 |

`Stop` 不设置 `completedAt`，不产生成功未读态，也不误报会话完成。同一 Session 在 `Stop → idle` 后提交后续 prompt，可以恢复为 `running`。单次工具失败不会把整个 Session 标记为中断。

共享快照和普通诊断只保留来源、事件类别、生命周期、工具分类、结果类别与脱敏错误类别。真实手机验收没有出现完整 prompt、完整命令、工具输入输出、响应或错误正文，也没有出现测试用敏感标记。审查收尾后，ZCode 任务标题进一步改为只把首个 prompt 映射为有限的固定安全类别，不复制 prompt 原文片段；同 Session 后续 prompt 保持首轮标题不变，从设计上避免新格式凭据绕过黑名单。

## Hook 配置管理

- 安装或修复前先创建权限受限备份；原配置不存在时写入专用 ABSENT 标记。
- 备份与恢复前备份均校验为 `0600`。
- 安装、修复和卸载只管理带 AgentPager 标识的 ZCode Hook，保留其他根字段、第三方事件组和混合组中的第三方 Hook。
- 重复安装保持幂等；配置无变化时不创建无意义备份。
- 无效 JSON、异常结构、备份失败或安全写入失败时拒绝覆盖。
- 恢复采用“检查最近备份 → 确认恢复最近备份”的双确认流程；确认间配置指纹变化时拒绝写入。
- 恢复前另建权限受限备份，不删除历史 AgentPager 备份。

## 真实 ZCode Session 验收

真实验收只在新建的隔离目录和全新 ZCode Desktop Session 中执行。测试内容仅包含可控读取、无副作用本地命令、ZCode 自身的本地权限卡片和确定性失败读取，不访问项目文件、用户文档、账户数据或凭据，也不执行上传和破坏性命令。

实际结果：

- 七类事件全部进入 Bridge 诊断与共享任务投影。
- `PermissionRequest` 只呈现本地等待；权限由用户在 ZCode Desktop 人工处理，手机没有 approve / deny 能力。
- `PostToolUseFailure` 保持 `running`，同一 Session 随后的操作仍可继续。
- `Stop` 收敛为 `idle`，后续同一 Session 可重新进入 `running`。
- Redmi 真机可以识别并显示 ZCode 任务；为完成验收，手机 Custom App 更新到包含 ZCode 兼容模型的本地构建，未产生 Android 源码改动。
- 手机快照和普通诊断未包含测试敏感值或完整正文；可见内容限于安全任务标题和固定分类。

## 安全恢复证据

真实配置测试结束后，通过调试 Bridge 的正式设置界面完成两步确认恢复：

- 用户级 `config.json` 已恢复为测试前的“不存在”状态。
- ABSENT 标记保留，内容有效、不是软链接、权限为 `0600`。
- 恢复前备份存在且权限为 `0600`。
- 真实配置中的调试版 `AgentGridHooks` 引用计数为 0。
- 调试 Bridge 已正常退出，没有强制结束 ZCode 或其他 Agent 进程。

原 `/Applications/AgentPager Bridge.app` 恢复后：

- 实际二进制路径来自原 App。
- 二进制 SHA-256 为 `139f9764d4e8fdfadb6ce587fbf648db819b2b4957482570e55f8315745b2435`，与测试前完整哈希一致。
- TCP 49361 与 49362 均恢复监听。
- Redmi 真机重新连接 49362。

原 Bridge 第一次恢复启动时，钥匙串提示阻塞了服务初始化，因此进程存在但端口尚未监听。用户人工输入密码并允许后，两个端口恢复监听，手机也恢复连接。自动化没有代替用户处理钥匙串授权，也没有读取钥匙串内容。

## 自动化覆盖

自动化测试覆盖：

- 七事件 payload、snake_case / camelCase、缺失可选字段与未知字段；
- PermissionRequest 的 waitingApproval 投影和无手机裁决能力边界；
- `PostToolUseFailure → running`、`Stop → idle` 与同 Session 恢复；
- 未知事件、未知工具、标题、步骤和诊断脱敏；
- 备份、同秒备份冲突、幂等安装、修复、残缺或旧版受管 Hook 识别、混合第三方 Hook、安全卸载与最近备份恢复；
- ABSENT 原状态、恢复双确认、确认间并发变化、无效 JSON 与写入失败；
- 合成 ZCode Hook 经真实 Hook Bridge、TaskCatalog 和共享协议的最高层接缝；
- 现有 Codex 与 Claude Code 回归。

最终测试数量和命令以本次提交报告为准。

## 未验证与后续边界

- Windows 继续沿用 Issue #3 的协议兼容结论，本次没有 Windows/.NET 实际运行。
- 没有执行长时间 Bridge 资源占用或断网恢复测试。
- 真实用户配置的初始状态为不存在；第三方字段、混合 Hook 与并发配置变化由自动化测试覆盖，没有在真实用户配置上人为制造。
- Issue #6 仍负责手机 approve / deny、裁决回传、Hook 等待、超时、断线和重复回答处理。
- Issue #7/#8 的 GLM Key、网络查询、额度和错误降级没有开始。

## 开场时已有的用户内容

以下内容在 Issue #5 开始前已经存在，本票不修改、不暂存、不回退也不提交：

- `.agents/skill-profile.json`
- `AGENTS.md`
- `CLAUDE.md`
- `docs/README.md`
- `.claude/agents/`
- `.claude/settings.json`
- `.codex/`
- `.entire/`
- `docs/custom-development-workflow.md`
- `docs/updates/2026-08-28-glm-coding-plan-quota-monitoring-research.md`
- `docs/updates/2026-08-28-zcode-glm-session-quota-prd.md`
- `docs/updates/2026-08-28-zcode-session-monitoring-research.md`
