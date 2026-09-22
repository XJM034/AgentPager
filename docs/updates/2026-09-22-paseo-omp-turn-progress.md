# Paseo–omp 运行与本轮完成（#15）

日期：2026-09-22。范围：[子票 #15](https://github.com/XJM034/AgentPager/issues/15)，父规格 #13；基准 `c92b017c68bea1852fc4b0697d0ca7c99d0ce1cb`，长期分支 `alexx_custom`。

## 当前状态

实现、受控输入自动化和双轴代码审查已完成。**真实隔离 Paseo 模型调用与 Android 模拟器验收尚未执行，等待本 Session 的明确授权；#15 不关闭，不宣称整票验收完成。** #14 已完成并关闭，无需补办。未推送、发布或实施 #16–#18。

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
- Android JDK 17 / Gradle 8.13 / SDK 36：`testDebugUnitTest lintDebug assembleDebug` 全部通过，**90 项单元测试，0 失败**。产物仍为 `.custom` / AgentPager Custom，尚未安装本票版本。
- Standards 初审：0 硬违反、1 重复查找建议、1 订阅资源风险；已修复，复核 0 剩余发现。
- Spec 初审：2 项（同毫秒旧轮回退 P1、初始子任务 P2）；高层回归复现并修复，独立复核 0 剩余发现。
- 共享手机协议没有新增字段/枚举。Windows Core 编解码复验 **7/7 通过**（复用 #14 隔离 .NET SDK 8.0.425，原 Windows 目标 EnableWindowsTargeting）；不代表 Windows 桌面运行。

## 真实验证授权与边界

已在当前 Session 请求明确授权：独立临时 Paseo home/端口/测试目录，安装本插件并启动隔离 Bridge；备份后临时升级 medium_phone，验收后恢复；使用 omp 既有登录分别调用 Codex/GLM 最小读取、编辑、执行及同会话模型切换。不读取/输出凭据，不改日常服务，不操作 Redmi。尚未获得回复，因此未执行这些操作。

现有自动化证明受控条件下的状态归约、接线及 Android 策略，不证明真实 Paseo 的自动重试/后台工作交付，也不证明设备提示音或硬件亮度。Redmi、正式安装管理和长期运行仍属于 #18；本票必需的真实正常轮次验收不能据此豁免。

## 文档与票据

领域术语、平台安装流程、协议结构未改变，无需改写 CONTEXT.md、根/子 AGENTS 或新增 ADR。待真实验收通过后同步现行接入说明和索引、补实际证据、选择性本地提交并关闭 #15 回读。用户原有研究/规格/拆票及索引改动保留，不全量暂存。

下一票 #16 最新正文、评论、标签及原生依赖已于本 Session 读取：OPEN / ready-for-agent，无评论，仅依赖仍 OPEN 的 #15；在本票真正收尾前不启动 #16，也不把遗留验收写入下一票 prompt。
