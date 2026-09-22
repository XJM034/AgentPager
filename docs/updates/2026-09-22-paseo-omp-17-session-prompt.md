# #17 下一 Session 启动 prompt

2026-09-22 回读：#17 OPEN / ready-for-agent / 无评论；原生依赖仅 #15（CLOSED），不依赖 #16。执行时再次读取最新事实。

```text
请使用 $mattpocock-skills:implement 实施 AgentPager 开发票 #17。
Skill：/Users/minxian/Projects/agent-skill-sources/repos/mattpocock-skills/skills/engineering/implement/SKILL.md
开发票：https://github.com/XJM034/AgentPager/issues/17
父规格：https://github.com/XJM034/AgentPager/issues/13
工作目录：/Users/minxian/Documents/alex_project/AgentPager-0.3.0
沿用本地工作目录和长期分支 alexx_custom，不创建或切换分支。

#14、#15、#16 已完成实现、同 Session 隔离验收、双轴审查、文档、选择性本地提交和关闭回读。#16 实现 689770a、并发刷新修复 d725129、终态修复 56f7c6d / 27d858a；最终证据和关闭记录见 docs/updates/2026-09-22-paseo-omp-attention-outcomes.md 与 handoff/260922-handoff.md。不要把早期待授权或修复前采样当成当前未完成，不补办前票收尾。

先检查 Git 状态，阅读适用 AGENTS.md、docs/README.md、CONTEXT.md、handoff/260922-handoff.md，以及 #17、#13 的完整正文、评论、标签和原生依赖。按索引读取调研、Paseo 开发接入说明及 #14–#16 最终记录。#17 最近原生依赖仅 #15 CLOSED，执行时回读；不要人为增加 #16 阻塞依赖。
已有未提交规格、研究、拆票、CONTEXT.md 和 docs/README.md 索引改动必须保留，不覆盖、不全量暂存。

本次只做 #17，具体以其最新验收标准为准：
1. Bridge 后启动发现当前有效 omp 会话；恢复/导入不依赖 created，保持原卡片身份，分支新会话拥有独立身份，不按目录、标题或模型合并。
2. 断线、手机重连、Paseo/适配层重启后，以公开权威快照补齐；初始或重连不重播历史完成音，不把 idle 当刚完成，重复快照不延长完成提示。
3. 正确处理快照与新事件交错、乱序、去重、旧状态覆盖及失效清理；归档历史不重新出现。
4. omp 异常退出、Paseo 断开或适配层停止后，不永久显示运行，不冒充成功；恢复后自动同步。
5. 有界队列、超时和退避重连，回调快速返回，不突破官方 30 秒限制，不忙轮询、不无限缓存；手机或 Bridge 不可用不阻塞编码，其他来源、额度刷新、脱敏和本地信任边界保持有效。
6. 独立使用 #15 正常轮次验证恢复；#16 等待/失败与恢复的完整组合场景按票据由 #18 整体验收。本票不扩做 #18，不新增手机审批、回答、停止或重试，不修改审批模式、不自动批准。

按 implement 使用 TDD，优先复用实际插件 → 隔离 Bridge → 手机 WebSocket 快照及 Android 呈现测试接缝。通过受控连接/时间和权威快照验证后启动、恢复、重连、分支、归档、异常退出、快照竞态、提醒基线及资源行为。完成真实接线，不只交付模拟数据；分别说明受控自动化、实际 Paseo/Android 实测和未验证范围。公开接口若无法表达要求，给出官方、类型或运行证据并提出取舍，不静默标为成功。

运行适用 Swift 测试、Android 单元测试、Lint、Debug 构建及 SDK 类型检查；涉及共享协议时核对全部平台并运行兼容测试。完成后按 code-review 使用本 Session 开始时确定的固定基准执行 Standards 和 Spec 双轴审查，修复并复验。

真实安装、重启和模型调用遵守项目授权边界，优先可恢复隔离环境。需要额外授权时，在当前 Session 说明具体目标、操作和验证目的并取得授权，不复用 #14–#16 授权。不把验收转交下一 Session，不把未执行实测宣称完成。

本票必须在当前 Session 完成实现、验收、审查、文档同步、选择性本地提交和票据状态收尾。我授权你在验收全部满足后关闭子 Issue #17 并回读；不关闭父 #13，不推送、不发布，不继续实施 #18。保留其他未提交文件。
最终报告验收、测试、双轴审查、提交号、实际验证与未验证范围；核对下一票 #18 最新正文及依赖，直接给出完整可复制 prompt，不让下一 Session 补办 #17 收尾。
```
