# 2026-08-31 Entire 评审安全与提交关联修复

## 范围与状态

用户确认修复重复误删、错误流程和 checkpoint 验收缺口。仅修改项目开发工具、Codex 项目 Hook 与说明，以及外部 Skill 管理仓库的现行说明；不修改 Android/macOS 产品源码、AgentPager 的业务 Hook、配对/Key、Skill 规范源或托管软链接。没有提交、推送、安装 App 或改写已有提交。

已完成本地修复及隔离验证。用户随后确认已通过官方界面重新信任；真实 Desktop 的提示词事件、Session 身份和执行前拦截已验证。**本轮 Stop 在回复结束后触发，以及下一次授权提交的 checkpoint 关联，尚未在真实项目中验收**；不将隔离测试冒充这两项实际结果。

## 已确认的原因

1. 项目 `custom-development-workflow.md` 与管理仓库 `OPERATIONS.md` 将 `entire doctor` 错写为只读预检。Entire 0.7.7 的该命令具有清理行为，实际非交互运行触发 Discard；上次部分恢复没有同步移除错误入口。本次移除错误指引，并在两个仓库根规则加入明确路由。
2. 本项目只有 `.entire/settings.local.json`，缺少 `.entire/settings.json`。独立仓库对照测试确认：本地配置相同，只补一个内容为 `{}` 的项目设置文件，两种提交时序都从“无 trailer/无 metadata”变为“有 trailer，元数据/转录身份匹配”。本项目已补该空文件，本地启用、遥测与上传设置保持原样。
3. 观察到父 Session 状态携带子任务转录路径；这发生在 UI 提交之后，不能当作该提交缺失 checkpoint 的直接原因。增加身份适配器，错配时不转发事件、不猜选文件，显示追踪降级提示。
4. 旧解析器对 Desktop 顶层 `exec` 和结构化 `FileChange` 存在识别限制。隔离回放在原生 `apply_patch` PostToolUse 可用时能保存 Desktop 转录并完成关联。没有修改 CLI 解析器，也不宣称全部工具格式已支持。

源码依据：Entire v0.7.7 的 [Codex 生命周期解析](https://github.com/entireio/cli/blob/v0.7.7/cmd/entire/cli/agent/codex/lifecycle.go)、[转录解析](https://github.com/entireio/cli/blob/v0.7.7/cmd/entire/cli/agent/codex/transcript.go)和 [Session 生命周期处理](https://github.com/entireio/cli/blob/v0.7.7/cmd/entire/cli/strategy/manual_commit_hooks.go)。结论以版本源码及本地隔离结果为依据，不把安装包内较旧的兼容说明当成现行实现。

配置标记的直接依据：[Git Hook 前置检查](https://github.com/entireio/cli/blob/v0.7.7/cmd/entire/cli/hooks_git_cmd.go#L103)调用 `IsSetUpAndEnabled()`；[设置检查](https://github.com/entireio/cli/blob/v0.7.7/cmd/entire/cli/settings/settings.go#L961)先要求项目 `settings.json` 存在，之后才合并本地启用设置。独立仓库对照与该源码分支一致。

## 实施

- `scripts/entire-review-readonly.py`：直接读取文件/Git，不启动 Entire；强制明确范围/Session，检测项目设置标记缺失、身份错配、checkpoint 证据不足。
- `scripts/entire-maintenance-guard.py`：Codex `PreToolUse` 拦截常见 Entire 维护命令，包括本次事故的环境变量前缀与 Shell 包装形式；拒绝时退出 2。
- `scripts/entire-codex-hook.py`：校验 Session 与转录身份后原样转发四类生命周期事件，规范继承的 Session 环境变量，不伪造原始记录。
- `.codex/rules/entire-safety.rules`：补充直接命令拒绝规则。完整访问模式与任意解释器不属于此规则的全面保障范围。
- `.codex/hooks.json`：仅替换四个 Entire handler 为身份适配器，追加维护拦截 handler；不删除无关配置，不写 `trusted_hash`。原配置已备份。
- `.entire/settings.json`：空对象标记，修复 Git Hook 提前跳过的条件。

使用与边界见 [安全流程](../entire-review-safety.md)。

## 验证

- 18 项 Python 回归测试通过：纯读取、过期状态不清理、危险命令拒绝、Shell/环境变量包装、路径与引用校验、转录续段身份、父子错配不转发、原始事件转发、缺失设置标记告警等。
- `codex execpolicy check` 对直接 `entire doctor` 返回 `forbidden`，正常 `entire hooks codex stop` 不命中拒绝规则。只检查规则，没有执行维护命令。
- `scripts/check-entire-checkpoint-integration.py` 的 8 个独立仓库场景全部符合预期：缺少标记的 2 个场景无关联；补齐标记、加入适配器、使用 Desktop 转录的 6 个场景均生成 trailer，实际保存的元数据与转录 Session ID 一致。两种时序分别为 Stop 后提交、轮次中提交后 Stop。
- 集成脚本不接收已有仓库，不复制真实转录，隔离继承的 Git/Session 环境；只调用明确列出的生命周期/Git Hook，不运行 `doctor` 或清理命令。结果检查失败会非零退出。
- 版本：Entire 0.7.7；终端 Codex 0.149.1，Desktop 内置 Codex 0.151.0-alpha.7.2。规则解析和 Hook 适配器已测试；用户已确认官方重新信任，真实 Desktop 验收见下。

本轮没有修改 App 源码，未重新运行 Android/Swift 产品测试。已有 Android UI 提交 `f907ce1` 保持原样，不补写 trailer 或伪造历史 checkpoint，原 UI 审查仍按 diff-only 解释。

## 两条误删记录与回退

本次误删的 `01a04668…` 和 `01a05570…` 已使用上一次恢复前保存的原始备份写回：2 个 JSON 与 6 个 sidecar 均逐字匹配备份。写前获取对应 Session 锁，拒绝覆盖已有目标；写回时原有 16 个文件哈希不变。未把这次恢复描述成上次 9 条重建索引的完整恢复。

私有备份位于 `.git/entire-recovery/20260831T164027-workflow-fix/`，包括配置/文档原件与清单、恢复结果、Hook 配置变化及 8 场景集成证据。Git 忽略目录内的记录不得提交/上传。恢复其他状态前先重新核对是否已变化，不整目录覆盖；回退 Hook 时同样需要官方信任。

## 官方信任后的真实 Desktop 验收

2026-08-31 17:04（Asia/Shanghai）核实：

- 用户回复“已信任”后，活动状态实际记录该提示词，Session ID 与转录首条 ID 一致，指向本任务的正确续段，不再指向子任务转录。
- 创建无害的临时假程序 `entire`，其唯一行为是写临时标记；通过当前 Desktop Shell 工具调用带 `ACCESSIBLE=1` 前缀的维护形态探针。
- 宿主返回 `Command blocked by PreToolUse hook: Entire maintenance blocked`，临时标记不存在。实际拦截已经触发，不只是直接运行脚本的单元测试；没有启动真实 Entire 维护命令，没有换工具重试被拒绝的操作。
- 恢复的两条原始 Session JSON 哈希仍与事前备份一致。Hook 配置未再次变化，不需要重复信任。
- 私有结果保存到同一备份目录的 `desktop-trust-acceptance.json`。

## 剩余验收

1. 官方重新信任、提示词事件、Session 身份和维护拦截已完成；不再要求用户重复授权。
2. 下一轮读取本轮 Stop 后的状态；下一次用户授权实际提交时，再核对真实 checkpoint trailer、元数据与转录。没有为本次验收额外提交，也没有手动伪造 Stop 事件。
3. 若仍出现身份错配或 Hook 失败，保留原始转录、先读日志/状态，保持 diff-only；不把清理或重新安装当作通用重试。
