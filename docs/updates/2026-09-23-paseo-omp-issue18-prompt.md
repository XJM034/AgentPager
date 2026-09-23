# #18 完整实施 prompt

以下内容可直接复制到下一 Session：

```text
请使用 [$mattpocock-skills:implement](/Users/minxian/Projects/agent-skill-sources/repos/mattpocock-skills/skills/engineering/implement/SKILL.md) 实施 AgentPager 开发票 #18。
Skill：/Users/minxian/Projects/agent-skill-sources/repos/mattpocock-skills/skills/engineering/implement/SKILL.md
开发票：https://github.com/XJM034/AgentPager/issues/18
父规格：https://github.com/XJM034/AgentPager/issues/13
工作目录：/Users/minxian/Documents/alex_project/AgentPager-0.3.0
沿用本地工作目录和长期分支 alexx_custom，不创建或切换分支。

#14–#17 已完成各票实现、同 Session 验收、双轴审查、文档、选择性本地提交及关闭回读。#17 实现 50b475f，修复 f5842e3、02f3959，最终验收 34f789c；关闭回读为 CLOSED，父 #13 保持 OPEN。先读 handoff/260923-handoff.md 及其中关闭记录，不把早期待授权、旧插件采样或修复前结果当成当前未完成，不补办前票收尾。

先检查 Git 状态，阅读适用 AGENTS.md、docs/README.md、CONTEXT.md、最新 handoff；读取 #18、#13 完整正文、评论、标签及原生依赖，按索引读调研、Paseo 开发接入说明及 #14–#17 最终验收记录。#18 最近原生依赖为 #16、#17 CLOSED，执行时回读。保留已有未提交规格、研究、拆票、CONTEXT.md 和 docs/README.md 六行索引改动，不覆盖、不全量暂存。

本次只做 #18，以最新验收标准为准：
1. 复用现有 Bridge 配置交互，提供一次启用、连接诊断、关闭、恢复与撤销，不要求每项目或每会话设置；区分未启用、连接不可用、已连接但暂无会话。
2. 仅管理 AgentPager 自身插件/配置，变更前备份，重复操作幂等，保留第三方配置和 Paseo 权限模式；关闭清理活跃呈现但不停止 omp，恢复后权威补齐，撤销只删除自身管理项。
3. 正式打包/安装前核实分支、远程、版本、Bundle/包名、签名与设备；macOS 替换先备份，Android 保持 Custom 身份和原配对数据。记录实际版本，不能把构建当安装。
4. 真实 Paseo 分别使用 Codex/GLM 验证新会话、运行/活动、完成、同会话继续、模型切换、多会话；Redmi 实测提示音、静音、亮度、卡片与完成反馈。
5. 按票据整体验收等待/失败与恢复：等待期间断开恢复准确，旧请求已解决时不重现等待或虚假按钮；覆盖 Bridge 后启动、手机重连、Paseo/适配层重启、归档和异常退出，避免重复卡片、历史提醒及永久运行。
6. 回归 Codex、Claude Code、ZCode 原来源及 Codex/GLM 额度，无 GLM Key 也可监控 omp。保持脱敏、本地信任边界、有界资源和快速回调；不新增手机审批/回答/停止/重试，不修改审批模式，不自动批准。

按 implement 在既有插件→隔离 Bridge→手机 WebSocket 与 Android 呈现接缝做 TDD；完成真实配置接线，不只交付模拟数据。运行适用 Swift、Android 单元测试、Lint、Debug 构建与 SDK 类型检查；共享协议变化核对全部平台并跑兼容测试。开工固定本 Session 审查基准，完成后按 code-review 做 Standards/Spec 双轴审查，修复复验。

本票之前的隔离安装、重启和四次模型调用授权不沿用。先准备可审查的具体安装/备份/恢复方案，再在当前 Session 说明目标、操作和验证目的取得额外授权；不得静默替换或重启日常应用。Paseo directory 插件源码改动后须对获准目标显式 reload 并核对 running。#17 开发 Bridge 使用临时配对密钥，不能当正式持久化配置验收。

明确区分受控自动化、实际 Paseo/Android/Redmi、未验证范围。#17 未做真实运行中杀进程、原生 fork/import、听音、Redmi 硬件、长期性能和正式应用全来源/额度组合验收，这些不能从前票结果推定完成。公开接口若无法表达要求，给出官方/类型/运行证据并提出取舍，不静默降级为成功。

本票在当前 Session 完成实现、实际验收、审查、文档同步、选择性本地提交与状态收尾，不把验收转交下一 Session。验收全部满足后授权关闭子 Issue #18 并回读；不关闭父 #13、不推送、不发布。按父规格逐项汇总证据和剩余边界，子票关闭不能自动代表父规格通过。最终报告验收、测试、双轴审查、提交号、实际安装/恢复结果、未验证范围和父规格状态。
```
