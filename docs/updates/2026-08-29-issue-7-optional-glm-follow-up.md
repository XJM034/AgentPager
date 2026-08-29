# Issue #7 可选 GLM 额度连接收尾

日期：2026-08-29

范围：在 `da9fb61 feat(glm): show Coding Plan quota (#7)` 之后，将 GLM 额度明确为用户主动启用的独立连接，并完成已暴露手机配对密钥的轮换。没有开始 Issue #8，没有推送、关闭 Issue、创建 PR 或 Release，也没有运行 Entire Review。

## 产品结果

- ZCode 会话监控和手机审批默认独立工作，不依赖 GLM Key。
- macOS 设置页标题改为“GLM 额度连接（可选）”，并说明 ZCode 当前没有供第三方使用的额度读取接口；用户只有希望在 AgentPager 手机端显示额度时，才单独保存一次 Coding Plan Key。
- 未配置 Key 时显示中性的“未启用”，不是错误或警告，也不显示“ZCode 未连接”。
- 未配置 Key 时不发起 GLM 网络请求，不发送空 GLM provider，Android 不显示 GLM 顶栏占位。
- 配置 Key 后继续复用既有 Keychain、独立 provider adapter、single-flight、10 分钟轮询和 Gate 0 字段映射。
- Android 顶栏继续保持 `GENERAL → SPARK → GLM`；GLM 只有在快照包含可信额度窗口时才出现。

## 配对密钥事故与轮换

当前手机配对密钥曾意外进入本地工具输出，因此按已泄露处理。本次轮换遵守以下边界：没有读取、复述、输出、备份或恢复旧密钥，也没有通过辅助功能、截图、OCR、日志或命令读取设置窗口中的配对文本。

执行与结果：

- 正常退出 Bridge 后，只删除 macOS 钥匙串中 `service=com.agentgrid.bridge`、`account=pairing-secret` 的精确项目。
- 启动已安装的 AgentPager Bridge 0.3.0 Build 12，由 Bridge 自动生成新配对密钥。
- 轮换后，旧 Redmi 配对发出的签名控制被 Bridge 以“签名或序号无效”拒绝，证明旧密钥不能再授权手机控制。
- 用户在 Mac 和 Redmi 上人工查看并输入新配对信息；工具没有接触新配对文本。
- 重新配对后，Bridge 仍为 Build 12；49361 与 49362 正常监听；Redmi 与 49362 建立连接并收到当前任务状态；一个临时“标记已读”签名控制返回 `accepted`。
- GLM 钥匙串项目在轮换前后均不存在，没有被读取或修改。

现有协议边界：WebSocket 状态订阅位于可信局域网内，当前不使用配对密钥验证只读连接；因此旧密钥失效的直接证据是签名控制被拒绝，而不是 TCP/WebSocket 无法建立。本次没有把 Issue #7 扩大为跨平台协议鉴权改造。

## GitHub Issue #7

经用户明确授权，只更新了 [Issue #7](https://github.com/XJM034/AgentPager/issues/7)：

- 标题改为“[GLM/ZCode 6/9] 提供可选 GLM Coding Plan 额度连接”。
- 正文保留原有 Keychain、provider adapter、Gate 0、single-flight、轮询、协议裁剪和 Android 顶栏验收，并补充默认未启用行为、ZCode 独立工作、安全边界、未来官方接缝迁移条件和公开分发前政策确认要求。
- 回读确认 Issue 仍为 `OPEN`，`ready-for-agent` 标签和空评论列表保持不变。
- 没有修改 #1、#8、#9 或 #10。

## TDD 与实现范围

本轮按设置呈现这一公共接缝执行红绿循环：

1. 先新增“未配置时为未启用、中性色、可选标题与说明”的 Bridge 测试；测试因呈现接口不存在而编译失败。
2. 增加最小的 `GLMConnectionPresentation` 与状态色语义，并让 SwiftUI 设置页消费该呈现状态。
3. 窄测试转绿后运行全量测试。

产品行为修改只涉及 macOS 设置呈现。复审阶段另做了两项等价整理：Android 将额度标题与色调集中为单一呈现值，macOS GLM provider 将窗口 key、标签和分钟数集中为单一描述值；没有改变 Keychain、协议、Gate 0 映射或 ZCode Hook / 审批路径。既有无 Key、空 provider、Android 不占位、Key 隔离、single-flight 和 ZCode 独立审批测试继续作为功能证据。

## 无重复 Key 调研

[ZCode / GLM 额度无重复 Key 接入调研](2026-08-29-zcode-glm-quota-no-key-research.md) 已纳入 Issue #7 范围。结论是：ZCode 自身能通过内部登录/provider 链路显示 Coding Plan 额度，但当前没有向第三方发布稳定的只读 CLI、API、Hook 字段或本地快照契约。调研文档中披露的本地缓存字段名/类型检查发生在新禁读边界建立之前；边界建立后没有再次读取。当前实现不读取 ZCode OAuth、Cookie、provider 配置、`coding-plan-cache` 内容或 Electron 私有 RPC；现有 Keychain 路径只作为用户主动选择的可选额度连接。

## 验证结果

- TDD 窄测试：先红后绿。
- `swift --version`：Apple Swift 6.4（swiftlang-6.4.0.33.1，Target `arm64-apple-macosx27.0.0`）。
- `cd macos && swift test`：154 个 AgentGridCore 测试与 4 个 AgentGridBridge 测试通过，失败 0 项。
- Android `testDebugUnitTest lintDebug assembleDebug`：最终复验通过，55 个 Gradle 任务中 11 个执行、44 个复用缓存。
- 真实 Redmi：新配对后状态同步和一次签名控制成功；默认无 GLM provider 时顶栏只显示 GENERAL 与 SPARK，没有 GLM 占位。
- `protocol/fixtures` 与 `docs/contracts` 下的 JSON：全部通过 `jq empty`。
- `git diff --check`：通过。
- Issue #7 两个提交涉及的源码、测试和文档，以及新增无重复 Key 调研文档：高置信度私钥、GitHub Token、OpenAI Key、JWT 与 AWS Access Key 模式扫描未发现命中。上下文扫描只命中调研文档中的公开环境变量名和固定提交链接，没有凭据值。
- 按 `$claude-agents-bootstrap` 做了限于 macOS Package 结构的指令文档审计，并同步 `AgentGridBridgeTests` 的职责；没有重写根 AGENTS/CLAUDE，也没有触碰开场已有修改。
- 真实 GLM Key 查询：未执行。当前 GLM Key 未配置，真实 Key 路径留给 #10 在用户主动启用时验证。

## Standards / Spec 复审

固定点选择 `91446e8`（`da9fb61` 的父提交），因此三点 diff 同时覆盖原实现提交和本次后续提交。首轮与第二轮发现包括 Package 测试目标文档、测试证据精度、重复 switch，以及既有调研与新禁读边界的时序说明；均已修复或通过准确的历史边界说明澄清。

第三轮完整复审结果：

- Standards：发现 0 项。
- Spec：发现 0 项。
