# Issue #9：ZCode 与可选 GLM 跨平台集成验收

日期：2026-08-29

## 结果与范围

本次在 `alexx_custom` 分支、基线 `d7460db740e857f0c69e72538675ec424d12b4c9` 上完成 Issue #9。新增最高层本地 E2E，通过生产 `HookBridgeServer`、`PersistentTaskCatalog`、`BridgeModel`、`WebSocketServer` 和签名控制协议，验证合成 ZCode Hook、共享快照与手机审批的完整路径；同时补齐 Android 状态、额度投影与 Compose Preview 覆盖。

范围严格限定在 Issue #9。未开始 Issue #10，未推送、发布、安装真实 Bridge/APK、操作 Redmi、访问真实 GLM 服务或读取真实凭据。

## 两条主场景

### 默认无 GLM Key

- 合成 `SessionStart`、工具活动、两个并发 `PermissionRequest` 和 `Stop` 经真实 TCP Hook 接缝进入 Bridge，并由真实 WebSocket 客户端收到共享快照。
- `Stop` 归约为 `idle`，没有伪造成功终态或完成时间。
- GLM fake provider 请求数严格为 `0`；协议中不含空 GLM provider，Android 无 GLM 顶栏占位。
- approve 与 deny 均通过现有签名控制通道完成；裁决按 `pendingRequestID` 精确命中，并发请求没有串单。
- 同一 Bridge 继续处理 ZCode、Codex CLI 与 Claude Code 合成会话；Codex General/Spark 保持可用。

### 主动启用合成可选 Key

- 只使用测试内存 Key、临时目录、临时端口和可替换 fake provider；没有访问钥匙串或网络额度接口。
- 同一快照同时包含 Codex General/Spark 与 GLM 5 小时/每周额度。
- 自动化依次观察 GLM 成功、鉴权失效、超时、临时服务错误和删除 Key；可信的旧额度窗口在失败时保留，并呈现相应状态。
- GLM 失败期间，Hook、WebSocket、任务归约、签名 approve/deny 与 Bridge 均继续工作；两种裁决均按各自 `pendingRequestID` 命中。
- 删除 Key 后恢复正常“未启用”，GLM provider 从协议消失，后续刷新与重连不再请求 GLM。
- 连接刷新与手动刷新重叠时最大并发请求数为 `1`；客户端断开后 Bridge 仍可处理新 Hook 和新 WebSocket 连接。

## 已自动化验证

- macOS `swift test`：通过。AgentGridCore 163 项、AgentGridBridge 8 项，0 失败。
- 新增本地 E2E 两项：两条主场景均通过，且断言外部 TCP/WebSocket/签名裁决行为。
- Android `testDebugUnitTest lintDebug assembleDebug`：通过，55 个 Gradle task（12 executed，43 up-to-date）。
- Android 单元测试覆盖 ZCode `running/editing`、`waitingApproval`、`idle`，额度顺序 `GENERAL → SPARK → GLM`、无 Key 不占位，以及 GLM 正常、陈旧、鉴权失效、暂不可用。
- Compose Preview 源码覆盖 ZCode running、waitingApproval、idle，以及 GLM 正常、低额度、陈旧、未启用、鉴权失效、暂不可用；Debug 构建已验证这些 Preview 源码可编译。
- `scripts/android-doctor.sh`：通过。Android Studio 2026.1、Android CLI 1.0.15985488、OpenJDK 17.0.19、Gradle 8.13，`medium_phone` AVD 可用。
- 协议及契约 JSON：`jq` 全量解析通过。
- `git diff --check`：通过。
- Issue #9 文件敏感信息扫描：通过；未发现认证头、Bearer 值、API Key 字段赋值或真实账号信息。
- 隔离 E2E 进程资源观察：两项测试并行于 0.050 秒完成；`/usr/bin/time -l` 记录整次测试命令 4.13 秒、0.99 秒 user CPU、0.86 秒 system CPU、最大常驻内存 119,029,760 字节、peak memory footprint 55,264,048 字节、0 swaps。测试时段内没有生成 AgentGridBridge/AgentPagerPackageTests 的 macOS Diagnostic Report。

## 模拟器验证

仅使用 `medium_phone` 模拟器，未向 Redmi 发送任何命令。

- Debug APK 成功安装并启动。
- 使用仅监听 `127.0.0.1` 临时端口的脱敏 fixture WebSocket 服务验证横屏布局。
- `GENERAL → SPARK → GLM` 三组顶栏保持单行，未遮挡第一条 ZCode waitingApproval 任务。
- 删除 GLM provider 后只显示 General/Spark，布局正常，第一条任务仍可见。
- 验证后已解除模拟器合成配对、停止 App、关闭临时服务并停止模拟器；临时监听端口已确认释放。

Android Studio 当时没有运行，因此没有在 IDE 内逐个打开 Preview 画布；相关 Preview 由 Debug 编译验证，关键顶栏与任务布局由运行中的 `medium_phone` 验证。

## 根据代码复核

Windows 现有模型和协议测试可解析：

- `AgentSource.ZCode`；
- 可选 `pendingRequestID`；
- 可选 `usageProviders`、GLM provider、额度窗口和未知 provider 的保留转发。

本机没有 `.NET` 工具链，未宣称 Windows 编译或实际运行。继续沿用已批准的 Windows 实际运行豁免。

## TDD 与安全边界

按 TDD 先新增最高层行为测试。初始测试因缺少可注入的 Bridge 运行配置而编译失败；随后为 `BridgeModel` 增加默认保持生产行为、测试可替换的运行配置，并使两条 E2E 转绿。测试超时辅助器也经过一次失败复现后改为不会被 WebSocket 阻塞的竞争门控。

所有敏感值均为明确标记的合成 fixture；测试还验证私有 fixture 内容不会进入共享快照。测试没有读取 ZCode OAuth、Cookie、provider 配置、缓存、Electron RPC、macOS 钥匙串或真实 GLM 响应，也没有占用 49361/49362。

## 未验证项

- Windows 编译与实际运行：本机缺少 `.NET`。
- Android Studio Preview 画布逐态目视：IDE 未运行；由编译、单元测试和模拟器关键布局验收替代，但不将其记录为 Preview 画布实测。
- 真实 ZCode、真实 GLM Key/API、真实钥匙串、已安装 Bridge、真实 49361/49362、Redmi：按 Issue #9 安全边界明确不执行。

## Standards 与 Spec 审查

按固定点 `d7460db740e857f0c69e72538675ec424d12b4c9` 对 Issue #9 工作树改动进行双轴审查：

- Standards 第一轮发现 1 项验证记录缺口：未记录 WebSocket/持久化相关 E2E 进程的 CPU、内存与 macOS Diagnostic Report 观察。补测并记录后，第二轮为 0 项发现。
- Spec 第一轮发现 2 项测试证据缺口：GLM 故障后缺少 deny 裁决、脱敏断言未直接检查合成工具路径。补齐外部行为断言并复跑后，第二轮为 0 项发现。
- 最终结果：Standards 0 项，Spec 0 项。

## 工作区保护

开始前已有的已修改、未跟踪文件及 `.entire/` 元数据均保持原样，不暂存、不覆盖、不回退。最终提交只包含 Issue #9 专属文件。
