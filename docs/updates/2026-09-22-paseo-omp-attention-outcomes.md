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
- 无共享手机协议字段或枚举变化；复用 waitingApproval、waitingAnswer、interrupted、latestStep 与既有能力集合。Windows 不增加采集或控制。

## 当前未完成

真实隔离 Paseo 插件安装、实际模型调用与 Android 模拟器渲染待本 Session 用户授权后执行；不会沿用前票授权。Standards / Spec 双轴初审均发现同一 P1 并发刷新竞态：较旧刷新先返回会使较新解决结果被版本门禁丢弃。补充两个重叠 deferred Promise 的真实 Bridge 测试，先超时失败，改为每会话合并刷新与 dirty 后再次读取后通过。独立复审、最终文档与票据收尾尚未完成。本记录是阶段证据，不能作为 #16 已完成或关票依据。

#14/#15 最终验收已完成，不补办前票；不实施 #17/#18，不推送、不发布、不关闭父 #13。
