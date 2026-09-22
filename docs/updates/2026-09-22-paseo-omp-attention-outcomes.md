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

## 当前未完成

真实隔离 Paseo 插件安装、实际模型调用与 Android 模拟器渲染待本 Session 用户授权后执行；不会沿用前票授权。Standards / Spec 双轴初审均发现同一 P1 并发刷新竞态：较旧刷新先返回会使较新解决结果被版本门禁丢弃。补充两个重叠 deferred Promise 的真实 Bridge 测试，先超时失败，改为每会话合并刷新与 dirty 后再次读取后通过。修复提交 `d725129` 后两路独立复审通过：Standards 0 剩余发现；Spec 0 剩余代码发现，仍有真实验收门槛。两位审查者分别重跑实际 TCP 竞态复现，较新请求与恢复结果均保留；Standards 另独立重跑本票 Swift 集成测试通过。最终文档与票据收尾尚未完成。本记录是阶段证据，不能作为 #16 已完成或关票依据。

#14/#15 最终验收已完成，不补办前票；不实施 #17/#18，不推送、不发布、不关闭父 #13。


## 同 Session 真实验收与追加修复

用户在本 Session 回复“允许”后，在新的私有 Paseo home、四个独立 loopback 端口和隔离 Bridge 实施；实际安装官方插件并确认 running。Paseo 0.8.0、omp 18.2.8；Android medium_phone / emulator-5554，临时 Build 24，与原 Build 20 的 Debug 签名一致。没有改日常 daemon、/Applications 或 Redmi。

首次真实验证包含两条真实会话、三轮调用：Codex 正常工具序列；GLM 原生 ask 问答后通过 Paseo 原生 stop 取消；同一 GLM 会话下一轮执行。两条均保持 Full Access（公开 currentModeId=full）。Codex 的非零退出在公开 timeline 中仍是 completed；GLM bash 明确报告 failed 后继续 write 并最终 succeeded。两模型结果文件均正确。不把 Codex 的非零退出冒充公开 failed 证据。

GLM 的真实 ask 产生 kind=question / OMP select；手机 waitingAnswer、安全文案、空能力集合，实际 Android 显示需要回到 Paseo。Paseo 原生停止后 pendingPermissions 为空、activeTurn 为空、手机 interrupted / 本轮已取消。没有发送工具审批或问答回答指令。原生工具审批、并发/重复/过期事件、整轮 failed 由受控上游贯通实际适配器、Bridge、Android 设备渲染验证；不冒充真实模型产生事件。

逐段受控设备验证：工具审批 → 混合一般问题 → 解决部分后仍工具等待 → 全部解决后运行 → 并发刷新恢复 → 整轮失败 → 下一轮计划/other → 取消。Android 布局核对安全文案且无允许/拒绝/发送回答/停止/重试按钮；七张截图已逐张查看。

首次现场摘要：[采样与恢复](assets/2026-09-22-paseo-omp-16-live-summary.json)。其中 TurnTest 明确为受控输入，Codex-Check/GLM-Check 为真实模型。截图：[工具审批和真实问答](assets/2026-09-22-paseo-omp-16-approval.png)、[一般问题](assets/2026-09-22-paseo-omp-16-controlled-question.png)、[部分解决与真实取消](assets/2026-09-22-paseo-omp-16-controlled-partial.png)、[恢复运行](assets/2026-09-22-paseo-omp-16-controlled-resumed.png)、[失败](assets/2026-09-22-paseo-omp-16-controlled-failed.png)、[计划](assets/2026-09-22-paseo-omp-16-controlled-plan.png)、[取消](assets/2026-09-22-paseo-omp-16-controlled-canceled.png)。

复核现场采样发现，请求清除且权威状态已 idle/无 activeTurn 时，等待到取消间仍发出一次 running。新增高层测试复现“等待取消前不应出现 running”的红灯，修复为等待 turn_ended 原子发布结果，测试转绿；不再把已空闲的轮次伪装成恢复执行。当前追加隔离实测及双轴复审进行中，首次采样保留修复前过渡事实，不覆盖为最终证据。
