# #16：Paseo 原生待处理请求与异常轮次

日期：2026-09-22。范围：子票 #16 / 父 #13。基准 `72dffd318449a63a05801509a7e9451d644ce208`，长期分支 `alexx_custom`。

## 实现与受控验证

实际插件监听公开 permission_requested / permission_resolved，刷新公开 pendingPermissions，以请求 ID 集合保留并发等待；只传类别，不传请求正文、参数或裁决。工具请求使用 waitingApproval，其余问题、计划、mode、other/未知类别使用 waitingAnswer，安全文案指向 Paseo。手机能力集合保持空，不增加控制动作，不调用 respondToPermission、不修改模式。

失败和取消使用既有 interrupted 与中断提醒，分别显示“本轮执行失败，请回到 Paseo 查看”“本轮已取消”；正常 completed 保持 succeeded。工具失败不结束会话。相同轮次重复结束不能覆盖终态；新轮次仍可继续。

TDD 在既有实际适配器 → 隔离 TCP Bridge → 手机 WebSocket 接缝进行：审批测试先超时，接线后通过；失败测试先超时，映射后通过；重复失败测试复现终态退回 offline，修复后通过。之后受控序列覆盖混合并发请求、只解决一个请求、过期 resolved、请求全部解决后恢复、计划/other、失败、取消及下一轮。#15 正常生命周期回归通过。

`protocol/fixtures/paseo-omp-attention.json` 来自本票 Swift 测试的实际 Bridge/WebSocket 输出；上游仍是受控 SDK 输入，不是模型生成事件。捕获命令：

```sh
AGENTPAGER_CAPTURE_OMP_ATTENTION="$PWD/protocol/fixtures/paseo-omp-attention.json" swift test --package-path macos --filter paseoAttentionReachesPhone
```

Android 使用同一快照验证网络接收、呈现、无动作能力、提醒、重复快照、静音和总开关基线；不把 JVM 测试称为设备渲染。

## 已执行检查

- Xcode 27.0 / Swift 6.4 / macOS SDK 27.0。
- `npm run check --prefix integrations/paseo-omp` 通过；官方 SDK 0.8.0 类型和官方固定版本插件 reference 已核对。Context7 没有 Paseo 匹配资料，使用官方文档和本地固定版本类型。
- `swift test --package-path macos --no-parallel`：177 Core + 15 Bridge = 192 项通过。
- Android JDK 17 / Gradle 8.13 / SDK 36：91 项单元测试、Lint、Debug 构建通过。
- Windows Core 兼容测试 7/7 通过（沿用临时 .NET SDK 8.0.425，EnableWindowsTargeting）；不代表 Windows 桌面实测。
- 无共享手机协议字段或枚举变化；复用 waitingApproval、waitingAnswer、interrupted、latestStep 与既有能力集合。Windows 不增加采集或控制。

实现提交 `689770a`；审查修复提交 `d725129`。修复后 SDK 类型检查、3 项 Paseo Swift 集成与 Android Omp/PhoneSession 定向复验通过。

## 审查与修复记录

Standards / Spec 双轴初审均发现同一 P1 并发刷新竞态：较旧刷新先返回会使较新解决结果被版本门禁丢弃。补充两个重叠 deferred Promise 的真实 Bridge 测试，先超时失败，改为每会话合并刷新并在更新期间再次读取后通过，提交 `d725129`。此前“待授权”是当时阶段状态，本 Session 随后获得明确授权并完成以下实测，不再是遗留事项。

#14/#15 最终验收已完成，不补办前票；不实施 #17/#18，不推送、不发布、不关闭父 #13。


## 同 Session 真实验收与追加修复

用户在本 Session 回复“允许”后，在新的私有 Paseo home、四个独立 loopback 端口和隔离 Bridge 实施；实际安装官方插件并确认 running。Paseo 0.8.0、omp 18.2.8；Android medium_phone / emulator-5554，临时 Build 24，与原 Build 20 的 Debug 签名一致。没有改日常 daemon、/Applications 或 Redmi。

首次真实验证包含两条真实会话、三轮调用：Codex 正常工具序列；GLM 原生 ask 问答后通过 Paseo 原生 stop 取消；同一 GLM 会话下一轮执行。两条均保持 Full Access（公开 currentModeId=full）。Codex 的非零退出在公开 timeline 中仍是 completed；GLM bash 明确报告 failed 后继续 write 并最终 succeeded。两模型结果文件均正确。不把 Codex 的非零退出冒充公开 failed 证据。

GLM 的真实 ask 产生 kind=question / OMP select；手机 waitingAnswer、安全文案、空能力集合，实际 Android 显示需要回到 Paseo。Paseo 原生停止后 pendingPermissions 为空、activeTurn 为空、手机 interrupted / 本轮已取消。没有发送工具审批或问答回答指令。原生工具审批、并发/重复/过期事件、整轮 failed 由受控上游贯通实际适配器、Bridge、Android 设备渲染验证；不冒充真实模型产生事件。

逐段受控设备验证：工具审批 → 混合一般问题 → 解决部分后仍工具等待 → 全部解决后运行 → 并发刷新恢复 → 整轮失败 → 下一轮计划/other → 取消。Android 布局核对安全文案且无允许/拒绝/发送回答/停止/重试按钮；七张截图已逐张查看。

首次现场摘要：[采样与恢复](assets/2026-09-22-paseo-omp-16-live-summary.json)。其中 TurnTest 明确为受控输入，Codex-Check/GLM-Check 为真实模型。截图：[工具审批和真实问答](assets/2026-09-22-paseo-omp-16-approval.png)、[一般问题](assets/2026-09-22-paseo-omp-16-controlled-question.png)、[部分解决与真实取消](assets/2026-09-22-paseo-omp-16-controlled-partial.png)、[恢复运行](assets/2026-09-22-paseo-omp-16-controlled-resumed.png)、[失败](assets/2026-09-22-paseo-omp-16-controlled-failed.png)、[计划](assets/2026-09-22-paseo-omp-16-controlled-plan.png)、[取消](assets/2026-09-22-paseo-omp-16-controlled-canceled.png)。

复核现场采样发现，请求清除且权威状态已 idle/无 activeTurn 时，等待到取消间仍发出一次 running。新增高层测试复现“等待取消前不应出现 running”的红灯，修复为等待 turn_ended 原子发布结果，测试转绿；不再把已空闲的轮次伪装成恢复执行。首次修复 `56f7c6d` 仅阻止目录发布；双轴追加审查又通过实际 TCP 发现迟到 timeline 可绕过。补充“idle 目录 → 同轮迟到工具完成 → 取消”测试，先在 Swift 集成测试第 1023 行明确失败；`27d858a` 使用统一发送门禁 awaitingOutcome，实际结束仍可发送，权威活动恢复后解除。回归转绿。首次采样保留修复前事实，不作为最终修复证据。

## 最终复验、恢复与边界

修复 `27d858a` 后，在第二套独立 Paseo home / 四端口重新加载实际插件。GLM 5.3 再次真实触发原生 question，公开模式仍 full；Paseo 原生 stop 后，公开目录变为 idle / 无 activeTurn / 空请求，手机直接 waitingAnswer → interrupted，没有中间 running。受控 TurnTest 同时重放 idle → 迟到工具 → 取消，结果相同。Android Build 24 实际配对，布局和两张截图均核对安全文案、无操作按钮。第二套 Codex-Check 仅为空会话，不冒充再次模型验收。

证据：[最终安全摘要](assets/2026-09-22-paseo-omp-16-final-summary.json)、[最终等待](assets/2026-09-22-paseo-omp-16-final-waiting.png)、[最终取消](assets/2026-09-22-paseo-omp-16-final-canceled.png)。两套共四轮真实模型调用；未发送任何批准、拒绝或回答请求。首次 GLM 下一轮正常执行已验证取消后原会话仍可继续；解决请求后继续运行由受控请求序列验证。

最终 Swift 全套 177 Core + 15 Bridge 全通过；SDK 类型检查通过。Android 91 项单元、Lint、Debug 构建及 Windows Core 7 项通过，最后仅 JS 状态门禁与受控上游测试变更，Android/Windows 无后续代码变化。一次此前全套运行遇到未修改的 BridgeModelGLMTests:250–251 错误清除测试瞬态失败，立即全套复跑通过；追加门禁后全套再次通过。

固定审查基准始终为 `72dffd318449a63a05801509a7e9451d644ce208`，最终代码范围到 `27d858a`。Standards 独立重跑实际 Bridge 回归；Spec 独立重跑实际适配器 TCP 迟到事件及下一轮序列。Standards 0 剩余代码发现；Spec 0 剩余代码发现。两路均不把审查通过替代现场证据。

两次临时升级均恢复原模拟器 Build 20；原 APK SHA-256、两份原应用数据文件集合及哈希完全一致。额外测试文件清除；本票插件、daemon、Bridge、采样器及模拟器均停止，第二套四端口回读关闭，第一套也已核对关闭。不改日常 daemon、正式 App、Redmi，不推送发布。

验收对应：公开请求 ID 集合及并发/旧 resolved、Full Access 无请求不等待、安全分类、失败/取消/完成区别、重复结束、下一轮、空能力集合、Android 无动作、静音/提醒去重和 #15 回归均有受控自动化；请求全序列进一步贯通实际 Bridge 与 Android 渲染。真实模型补充证明原生一般问答、取消、Full Access、工具错误后继续及正常完成。公开接口足以表达 #16 所需状态，未发现需降低本票验收的接口缺口。

未验证范围：未诱发真实模型工具审批或整轮失败，也未实际回答原生问题（遵守不发送真实审批指令与不修改模式）；这些分支由受控公开输入验证。无 Redmi 硬件提醒/MIUI、正式安装管理、长时间性能或 Windows 桌面验收。首次单点 Bridge 观测约 0% CPU / 38.6 MiB RSS 仅为现场观测，不是性能保证。全面恢复及正式验收分别属于 #17/#18，不影响本票受控请求验收范围。

## 最终关闭记录

最终证据提交 `a4a5ede` 后，双轴独立证据复核均为 0 项实质剩余问题；基准 `72dffd3...a4a5ede`。2026-09-22 17:16:07（北京时间）按本 Session 授权关闭 #16，GitHub 回读 `CLOSED` / `closedAt=2026-09-22T09:16:07Z`。父 #13 回读仍 OPEN。#17 再读正文、评论、标签与此前一致，OPEN / ready-for-agent / 无评论；原生依赖只有 #15 CLOSED。

本票实现、验收、双轴审查、文档、选择性本地提交和票据收尾全部完成，不需下一 Session 补办。#17 完整 prompt 见 [下一票启动说明](2026-09-22-paseo-omp-17-session-prompt.md)。未推送、未发布，用户原有未提交文件及六行索引改动保留。
