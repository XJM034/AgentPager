# #17：Paseo–omp 恢复与可信状态补齐

范围为子票 #17，父规格 #13；固定审查基准 `1181482b50fdbb838dfa3a1774d0ea2a7f673a65`，长期分支 `alexx_custom`。#14–#16 已完成，不补办前票。开工回读 #17 为 OPEN / ready-for-agent / 无评论，原生依赖仅 #15 CLOSED。

## 当前实现

- 公开目录更新与权威分页清单共同发现恢复、导入和独立分支，不再依赖 created。身份仍为主机命名空间与 Paseo agent ID。
- 每 15 秒重新读取公开清单，单次清单请求 5 秒超时；SDK 连接使用 1.5–30 秒退避，清单或 Bridge 失败亦退避。不重放断线积压的完成事件。
- 每个快照查询记录期间发生变更的会话，跳过这些会话的旧快照，同时保留其他恢复会话。目录代次切换重置序号；归档墓碑抑制迟到更新，权威恢复可重新接纳身份。
- 生命周期回调同步返回，最多 200 个异步任务、200 条待发摘要、200 个监控会话；原生请求刷新每次最多读两次。源文本不进入手机，仍使用公开 API 和认证 loopback 入口。
- Bridge 仅对启用的 Paseo 接入每 5 秒检查状态；45 秒未收到有效摘要时变为 offline，不写完成时间、不发成功提醒。归档清理和传输序号共用顺序门禁，旧适配进程的摘要不能覆盖较新进程。
- 重复恢复快照不延长完成时间。Android 每次连接的首个有效快照建立声音基线，防止离线期间的完成被重连补播；后续轮次、静音和总开关仍按原规则工作。
- 没有新增共享手机字段/枚举、手机控制动作或模型 Key；不改审批模式、不批准、不回答。#16 等待/失败与全面恢复的组合验收仍属 #18。

## TDD 与受控证据

既有实际插件 → 认证 TCP → 隔离 Bridge → 手机 WebSocket 接缝验证后启动、无 created 的导入/分支、归档、漏事件后的当前事实、同步竞态、旧代次、快速回调、资源压力和手机重连。归档迟到消息测试曾明确复现两张卡；繁忙会话使整批快照丢弃的问题也先超时失败，改为逐会话保护后通过。

TaskCatalog 公开接缝用受控时间验证 45 秒失联、同身份恢复、旧归档、重复完成基线和旧进程消息。Android PhoneSession 先复现重连历史完成音，增加首快照代次后通过。

`protocol/fixtures/paseo-omp-recovery.json` 由真实隔离 Bridge 的 WebSocket 输出捕获；上游是受控 SDK 数据，不是模型实测。

```sh
AGENTPAGER_CAPTURE_OMP_RECOVERY="$PWD/protocol/fixtures/paseo-omp-recovery.json" \
  swift test --package-path macos --filter paseoRecoveryReachesPhone
```

当前自动化：SDK 0.8.0 类型检查通过；Swift 179 Core + 16 Bridge 通过；Android 93 单元测试、Lint、Debug 构建通过（临时 Build 25，尚未安装）。工具链为 Xcode 27 / Swift 6.4 / macOS SDK 27，JDK 17 / Android SDK 36。

Context7 未检索到 Paseo；依据本机锁定的官方 SDK 公共类型及实现核对连接、清单 timeout、生命周期签名。官方网页本次读取未返回并已取消，不将其冒充成功获取。

## 尚待本 Session 完成

双轴审查、独立真实 Paseo/Android 验证和恢复、最终文档与票据关闭尚未完成。实际安装、隔离 daemon 启停与模型调用须取得本 Session 针对具体目标的授权，不能沿用前票授权。未进行正式安装、Redmi、长时间运行或 Windows 桌面验收；不推送、不发布、不关闭父 #13、不实施 #18。
