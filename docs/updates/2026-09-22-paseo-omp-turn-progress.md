# Paseo–omp 运行与本轮完成（#15）

日期：2026-09-22。范围：[子票 #15](https://github.com/XJM034/AgentPager/issues/15)，父规格 #13；基准 `c92b017c68bea1852fc4b0697d0ca7c99d0ce1cb`，长期分支 `alexx_custom`。

## 当前状态

实现、受控输入自动化、双轴代码审查及本 Session 获授权后的真实隔离 Paseo / Android 验收均已完成。实现提交 `d4b758a`。 #14 已完成并关闭，无需补办。未推送、发布或实施 #16–#18。

## 实现范围

- 沿用主机命名空间 + agent ID；模型、标题及目录不参与身份。同一张 omp 卡片经历空闲、运行/思考、工具活动、正常完成、下一轮运行。
- 插件使用公开 SDK 的目录及 timeline 订阅，生命周期回调 `agent.turn_started` / `agent.turn_ended`；仅在同一轮次、权威刷新为 idle 且无 activeTurn、结果为 completed 时报告 succeeded。单次工具失败、工具结束和仍在运行的 provider 不制造完成。
- 工具输入、输出、命令、提示词和错误原文均不越过插件。仅分类为既有活动，Bridge 复用安全步骤文案；思考保留既有“正在思考”。未知工具显示通用“执行工具”。
- 目录序号、快照时间、轮次身份、退役轮次及活动序号共同挡住重复、乱序和旧轮结束。发送队列保留生命周期转换，仅合并相邻同状态内容；快速完成后立即继续不会吞掉完成状态。
- 实时创建回调按 parentAgentId 过滤；初始/刷新快照同时按公开 `labels["paseo.parent-agent-id"]` 过滤已有子会话。此公开标签补全 #14 当时仅观察专用字段的范围说明；不改写其历史验收结论。
- 关闭/归档/移除后释放活动订阅和适配状态，避免耗尽 200 会话容量。这里只回收采集资源，不扩做手机归档处理或断线恢复。队列 200 项、退役轮次身份 64 项，超出旧身份窗口后使用保守时间边界。
- Bridge 保留原始任务 ID、startedAt、置顶与静音；正常完成设置现有 completedAt / isUnread，新一轮清除。Android 生产逻辑、排序、焦点、提示音追踪、静音与亮度策略不变。没有增加手机控制能力。
- 手机共享协议字段不变；本机认证入口增加可选 connectionID / revision / activity。连接标识和序号不输出到手机，活动复用手机已有 activity 字段。账户额度、其他 Agent 来源与配对机制不变。

## TDD 与自动化证据

已确认测试接缝是实际 JS 适配器 → loopback 认证入口 → 隔离 Bridge → 真实手机 WebSocket，再使用这条链路捕获的快照验证 Android 连接和呈现。上游是受控公开 SDK 输入，**不是实际模型执行**。

`paseoTurnProgressReachesPhone` 的逐段红/绿记录：

1. 原实现只发现空闲会话，运行更新超时；贯通后绿。
2. 工具活动、完成与下一轮原本超时；增加公开 timeline/轮次处理后绿。
3. 低目录序号、旧轮事件与子任务抢先目录更新导致错误；序号及创建身份过滤后绿。
4. 快速完成并立即下一轮被 Map 队列合并丢失；保留状态转换后绿。
5. 201 条会话生命周期后不能继续发现；订阅与状态回收后绿。
6. 双轴审查发现初始清单子会话入列（2 张卡）及同毫秒旧轮误报 succeeded；新增回归复现后修复，两者绿。
7. Android 快照测试发现思考时使用通用工具步骤；Bridge 保留思考默认文案后绿。

共享样本 `protocol/fixtures/paseo-omp-turns.json` 来自真实 Bridge/WebSocket 输出，捕获方法：

```sh
AGENTPAGER_CAPTURE_OMP_TURNS="$PWD/protocol/fixtures/paseo-omp-turns.json" \
swift test --package-path macos --filter paseoTurnProgressReachesPhone
```

Android `OmpTaskPresentationTest` 验证相同身份、焦点、完成收起、下一轮恢复、活动文案、首次快照、重复快照、任务静音、总开关禁用时推进基线及亮度策略；`PhoneSessionTest` 用相同样本验证网络接收。样本模型选择覆盖 Codex → GLM，模型内容本身不出现在手机。

## 检查与审查

- Xcode 27.0 / Swift 6.4 / macOS SDK 27.0；Paseo CLI 0.8.0、omp 18.2.8；SDK 锁定 0.8.0。Context7 无匹配资料，查询固定版本官方插件文档与本地 SDK 类型。
- `npm run check --prefix integrations/paseo-omp`：通过。
- `swift test --package-path macos --no-parallel`：177 Core + 14 Bridge，共 **191 项通过**。首次并行全套出现既有 Codex 额度测试 2 秒进程超时、两项旧 Bridge 测试端口尚未就绪；串行复跑全部通过，未将其误写为首次全绿。
- Android JDK 17 / Gradle 8.13 / SDK 36：`testDebugUnitTest lintDebug assembleDebug` 全部通过，**90 项单元测试，0 失败**。产物仍为 `.custom` / AgentPager Custom；真实验收临时安装 Build 23，结束后恢复 Build 20 及原数据。
- Standards 初审：0 硬违反、1 重复查找建议、1 订阅资源风险；已修复，复核 0 剩余发现。
- Spec 初审：2 项（同毫秒旧轮回退 P1、初始子任务 P2）；高层回归复现并修复，独立复核 0 剩余发现。
- 共享手机协议没有新增字段/枚举。Windows Core 编解码复验 **7/7 通过**（复用 #14 隔离 .NET SDK 8.0.425，原 Windows 目标 EnableWindowsTargeting）；不代表 Windows 桌面运行。

## 同 Session 补充真实验收

用户回复“允许”后执行；不是受控 SDK 模拟结果。Paseo 0.8.0 / omp 18.2.8 使用独立私有 home、测试目录和四个 loopback 端口；官方命令安装本插件、确认 running，启动本票隔离 Bridge。使用既有模型登录，不读取或输出凭据。正式 Bridge、日常 Paseo daemon、/Applications 和 Redmi 未修改。

- 两个实际会话：`Codex-Check` 使用 `openai-codex/gpt-5.5`，`GLM-Check` 使用 `zhipu-coding-plan/glm-5.3`。先创建无 prompt 的空闲会话，Android 实际显示两张卡。
- 两个模型分别读取合成文件、执行非零退出的 `false`、写入合成结果、执行短暂 sleep 后继续。两条手机快照均经历 thinking → reading → executing → editing → executing → succeeded；非零退出后继续运行，没有中途成功。结果文件内容已核对。
- Codex 的真实 Paseo UI 出现 `Background job bg_1 has completed. Resume your work`，后续完成前手机持续运行，最后仅一次 succeeded。此观察证明该次后台续跑，不推广为所有重试/后台场景都已现场覆盖。两模型的公开工具结果有差异：Codex 的命令非零退出仍呈 completed；GLM-Check 的真实 timeline 在 `1790064736840` 报 bash / failed，随后手机仍为 running，继续编辑与执行，最终正常完成。此 failed 来自真实采样，没有混入受控事件；更多失败顺序由自动化补充覆盖。
- 通过隔离 Paseo Web UI 的模型选择器，把 Codex-Check **原会话**切换成 GLM-5.3，再发送下一轮；公开 SDK refresh 确认模型变化。同一卡片回到运行并完成，ID 和 startedAt 全程不变，没有第三张卡。
- 经既有签名 `control.request / mute` 对该测试卡静音，再用 GLM 执行一轮；手机快照在运行、活动和完成时均保留 `isMuted=true`。Android 现有界面没有独立任务静音入口，因此这里是实际协议控制，并非声称点击了不存在的按钮；不发送审批指令。
- Android 实际切换“提示音：开 → 关 → 开”，关闭期间完成静音轮次；设置空闲亮度为约 34%，系统窗口 `sbrt=0.34270832` 与设置相符。提示音触发次数、禁用期间基线更新和重新打开不补播由 Android 自动化断言；没有把未录音的模拟器或截图当作物理发声证明。
- 使用官方 CLI 对原会话连续提交两次相同名称更新；前后实际手机 tasks 内容完全一致，保持两张卡。精确重复事件、乱序、同毫秒旧轮、并发子任务则由受控测试覆盖，不在真实 daemon 中伪造这些事件。
- WebSocket 采样核对：两条会话各只有一个 ID / startedAt；Codex-Check 共三次完整运行与完成（首轮 Codex、后两轮 GLM），GLM-Check 一次；真实快照和 Bridge 诊断不包含测试 prompt、完整命令、文件内容或工具参数。只输出安全活动文案。

可复核的去敏摘要：[真实链路采样](assets/2026-09-22-paseo-omp-15-live-summary.json)。它来自真实模型链路，与 `protocol/fixtures/paseo-omp-turns.json` 的受控上游样本明确分开。未提交私有配置、原始 daemon 日志、配对数据或模型内容。

Android `medium_phone / emulator-5554` 实际渲染截图（均已查看）：

- [首轮工具活动](assets/2026-09-22-paseo-omp-15-running.png)
- [首轮正常完成](assets/2026-09-22-paseo-omp-15-completion.png)
- [模型切换后原卡片下一轮](assets/2026-09-22-paseo-omp-15-model-switch-next.png)
- [任务已静音、总开关关闭时继续运行](assets/2026-09-22-paseo-omp-15-muted-next.png)
- [正常完成、总开关重新打开与亮度设置](assets/2026-09-22-paseo-omp-15-settings-completed.png)

### 恢复核对

安装前核对 `.custom` 包名及相同 Debug 签名，保存原 APK 与应用数据；临时 Build 23 完成验证后恢复原 Build 20。原有两个数据文件 SHA-256 全部一致，并移除仅本次测试新建的两个设置文件，最终文件集合及内容哈希完全一致。没有卸载或清空应用数据。官方 remove 只移除隔离 daemon 的本插件，stop 只针对本次独立 home；停止自己启动的 Bridge、采样器、模拟器，四个隔离端口均已关闭。

### 已验证与未验证边界

#15 正常轮次、两个真实模型与切换、实际 Bridge/Android 呈现、重复内容更新与任务静音已现场完成。异常精确排序、自动重试保守判断、子任务及提醒去重由受控真实接线测试覆盖。Redmi 声音/振动、物理亮度、MIUI 后台、正式安装管理、全面断线恢复和长期运行不属于本票的现场结论；分别按后续票范围验收，不作为 #15 遗留收尾。

## 文档与票据

领域术语、平台安装流程、协议结构未改变，无需改写 CONTEXT.md、根/子 AGENTS 或新增 ADR。现行接入说明、索引、阶段记录与 handoff 同步；用户原有研究/规格/拆票及索引改动保留，不全量暂存。#15 在验收与文档提交完成后按授权关闭并回读；父 #13 保持 OPEN。

下一票 #16 最新正文、评论、标签及原生依赖已于本 Session 读取：OPEN / ready-for-agent，无评论，仅依赖 #15；本 Session 不实施 #16–#18。其范围是等待请求、失败及取消的监控，不能顺带增加手机控制能力。完整可复制 prompt 见 [#16 新 Session](2026-09-22-paseo-omp-16-session-prompt.md)。

真实证据补录后由原两位审查者分别复核：Standards 0 项未解决，Spec 0 项未解决。未新增生产代码，沿用已完成的全套检查结果；文档本地链接与 `git diff --check` 通过。

## 票据关闭回读

2026-09-22 16:25:07（Asia/Shanghai），在实现 `d4b758a` 与真实验收/文档提交 `b81e74e` 完成后，按用户授权将 #15 关闭为 completed；回读 state=CLOSED。父 #13 回读 OPEN，未关闭。再次读取 #16 的完整正文、评论、标签及原生依赖：OPEN / ready-for-agent / 无评论，仅依赖 #15 且已 closed，具备新 Session 开工条件。未推送、发布，也未实施 #16–#18。
