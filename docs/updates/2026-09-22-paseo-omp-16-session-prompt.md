# #16 新 Session 完整 prompt

2026-09-22 16:25 回读：#15 CLOSED，#13 OPEN；#16 OPEN / ready-for-agent / 无评论，唯一依赖 #15 已 closed。实现 `d4b758a`，真实验收/文档 `b81e74e`。复制下方内容开始新的开发 Session；票据状态以开工时回读为准。

```text
请使用 $mattpocock-skills:implement 实施 AgentPager 开发票 #16。
Skill：/Users/minxian/Projects/agent-skill-sources/repos/mattpocock-skills/skills/engineering/implement/SKILL.md
开发票：https://github.com/XJM034/AgentPager/issues/16
父规格：https://github.com/XJM034/AgentPager/issues/13
工作目录：/Users/minxian/Documents/alex_project/AgentPager-0.3.0

沿用本地工作目录及长期分支 alexx_custom，不创建或切换分支，不推送、不发布、不关闭父 #13，不继续实施 #17–#18。

先检查 Git 状态，阅读适用 AGENTS.md、docs/README.md、CONTEXT.md、handoff/260922-handoff.md，以及 #16、#13 的完整正文、评论、标签和原生阻塞关系。按索引读取调研、Paseo 开发接入说明和 #14/#15 最终真实验收记录。

前置 #14、#15 已完成实现、同 Session 真实隔离验收、双轴审查、文档及选择性本地提交，并关闭回读。#14 的 a2b7d70 / fc5a135 / c92b017 和 #15 的 d4b758a 是实现及历史依据；#15 后续真实验收与关闭记录以最新阶段文档和 git log 为准。不要把首次提交时的“待真实验收”当成当前缺口，不补办 #14/#15 收尾。

工作区原有未提交 CONTEXT.md、规格、研究、拆票和 docs/README.md 索引改动必须保留，不覆盖、不全量暂存。

本次只做 #16：在现有 omp 卡片准确显示需要回到 Paseo 处理的原生审批、一般问答，以及本轮失败、取消；Paseo 处理请求后按真实事实恢复运行或结束。复用公开请求身份，正确处理多个请求、重复/过期 resolved、跨轮旧请求及重复结束。一般问题/计划确认/不明交互采用保守安全文案，不泄露问题或工具参数。Full Access 无请求时不制造等待，不更改审批模式、不加拦截、不自动批准。单次工具拒绝/错误不能等同整个会话失败。

仅监控，不新增手机批准、拒绝、回答、停止、重试能力；能力集合和 Android 界面不得出现虚假可操作项。沿用既有等待/结束提醒、静音、去重和正常轮次语义，不重新访谈。具体以 #16 验收标准为准。

按 implement 使用 TDD，优先复用实际插件 → 隔离 Bridge → 手机 WebSocket 快照和 Android 呈现测试接缝。受控请求序列必须覆盖等待、Paseo 解决后恢复、并发请求、过期/重复事件、失败、取消及 #15 正常轮次回归，不发送真实审批指令。完成真实接线，不只交付模拟数据；分别说明受控上游自动化、实际 Paseo/Android 实测与未验证范围。若公开接口无法表达父规格要求，给出官方/类型/运行证据并提出取舍，不静默标为成功。

运行适用 Swift 测试、Android 单元测试、Lint、Debug 构建及 SDK 类型检查；共享协议变化需核对全部平台实现并跑兼容测试。完成后按 code-review 使用固定基准做 Standards / Spec 双轴审查，修复并复验。

真实安装、重启、模型调用遵守项目授权边界；优先可恢复的隔离环境。需要额外授权时在本 Session 说明具体目标、操作、验证目的并取得授权，不复用前票授权，不把本票验收留给下一 Session，不把未执行实测宣称完成。

本票必须在当前 Session 完成实现、验收、审查、文档同步、选择性本地提交和票据状态收尾。我授权你验收全部满足后关闭子 Issue #16 并回读；不关闭父 #13，不推送或发布。保留其他未提交文件。

最终报告验收、测试、双轴审查、提交号、实际验证和未验证范围。核对下一票 #17 最新正文及依赖，直接给出可复制到新 Session 的完整 prompt，不留 #16 收尾债务。
```
