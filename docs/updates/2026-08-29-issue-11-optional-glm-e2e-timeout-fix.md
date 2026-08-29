# Issue #11：可选 GLM 本地 Bridge E2E 超时修复

日期：2026-08-29

## 结果与范围

本次在 `alexx_custom` 分支、基线 `2be1521a5c57e73550c94c4ec689439985f4a382` 上修复 `configuredGLMLocalBridgeEndToEnd` 贴近 5 秒上限抛出 `.timedOut` 的测试竞态。修改严格限定在 Issue #11，只调整 macOS 本地 Bridge E2E 的事件屏障，不修改生产 Bridge、GLM 协调器、WebSocket 服务、共享协议或 Android。

没有继续 Issue #10，没有打包或安装 Build 13，也没有操作真实 Bridge、49361/49362、ZCode、钥匙串、GLM Key、Android 或 Redmi。

## 精确根因

可选 GLM 场景在 fake provider 的首请求被测试屏障阻塞时创建 WebSocket 客户端，但客户端构造函数调用 `resume()` 不等于服务端已经完成握手并把该连接加入广播订阅。测试随后立即释放首请求，存在以下竞态：

1. GLM 首请求成功，Bridge 广播 `available`；
2. WebSocket 握手尚未完成，客户端错过该快照；
3. 握手完成后，Bridge 的手机连接刷新触发第二次 GLM 请求；
4. 第二个 fake 结果把状态推进到 `auth_unauthorized`；
5. 测试仍在等待已经错过的 `available`，最终在 5 秒后抛出 `.timedOut`。

定向探针在失败时记录到：最后等待阶段为首次 `available`；模型状态已是 `auth_unauthorized`，GLM 操作已经结束，请求数为 2。这排除了 GLM 状态发布卡死、fake provider 首请求未释放、single-flight 死锁、后续 approve/deny、删除 Key和重连等待点。

根因分类为测试 WebSocket 建连/消息订阅竞态；没有发现生产 Bridge 行为缺陷。

## 最小复现与修复前证据

精确测试命令：

```bash
cd macos
swift test --filter 'AgentGridBridgeTests.configuredGLMLocalBridgeEndToEnd'
```

`swift test list` 确认该标识只选择可选 Key 场景，不会同时选择默认无 Key 场景。首次未插桩的 20 次精确循环中 1 次失败，修复前复现率为 `1/20`（5%）；失败测试本体耗时 5.343 秒，抛出 `.timedOut`。后续阶段探针再次在首次 `available` 等待复现，并证明客户端已错过成功快照而模型已进入第二个鉴权失败状态。

最小公共接缝是：被阻塞的首个 GLM 请求、尚未确认完成握手的真实 WebSocket 客户端，以及连接建立后的自动刷新。其余 Hook、审批、删除 Key 和重连步骤不是触发超时的必要条件。

## 修复方式

在释放首个 fake GLM 请求前，测试先通过真实 WebSocket 接收一份无 GLM provider、包含 Codex General/Spark 的基线快照。这份可观察快照是明确的连接与订阅就绪屏障，之后才继续原有 single-flight 重叠刷新和 GLM 状态序列。

该修复没有提高 5 秒超时、增加重试、删除断言或加入固定 sleep；原有成功、鉴权失效、额度超时、服务错误、approve/deny、single-flight、删除 Key 与断线重连语义全部保留。

## 修复后验证

- 可选 Key 精确场景：屏障验证循环 `50/50`，删除临时插桩后的正式循环 `20/20`，合计连续 `70/70` 通过。
- 默认无 Key E2E：连续 `20/20` 通过，请求数为 0 的原断言保留。
- 两个 Local Bridge E2E 共同过滤：`2/2` 通过。
- AgentGridCore：`163/163` 通过，2 个 suites，0 失败。
- AgentGridBridge：`8/8` 通过，0 失败。
- 完整 `cd macos && swift test`：Core 163 项与 Bridge 8 项全部通过，0 失败。

最终改动没有触及共享协议或 Android，因此不需要重跑 Android 单元测试、Lint 或构建。协议/契约 JSON、敏感信息、diff 格式和临时调试前缀另行完成静态检查。

## 未验证项

- 已安装的 Build 12、真实 49361/49362、真实 Hook、真实手机连接和真实 GLM 服务：按 Issue #11 安全边界不操作。
- Build 13 打包、安装和 #10 现场验收：继续由仍被 #11 阻塞的 Issue #10 后续处理，本次不恢复。
- Android 与 Redmi：没有 Android 或跨平台协议改动，不发送任何命令。

## Standards 与 Spec 审查

按固定点 `2be1521a5c57e73550c94c4ec689439985f4a382` 对 Issue #11 提交执行双轴审查：

- 第一轮 Standards 为 0 项发现。
- 第一轮 Spec 为 1 项文档完整性发现：本节仍保留审查结果待补充的占位说明。补入实际审查结果后重新审查。
- 最终 Standards 为 0 项发现，Spec 为 0 项发现。

## 工作区保护

开始前已有的已修改、未跟踪文件及 `.entire/` 元数据保持原样，不暂存、不覆盖、不回退。最终提交只包含 Issue #11 专属测试与本记录。
