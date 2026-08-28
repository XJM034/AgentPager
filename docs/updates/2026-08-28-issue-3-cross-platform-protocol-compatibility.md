# Issue #3 跨平台协议兼容扩展

日期：2026-08-28

范围：GitHub Issue #3，仅扩展 macOS、Android、Windows 和共享 fixtures 的协议模型；未实现后续 ZCode Hook、GLM 网络查询、Key 设置、Android GLM 界面或手机审批产品逻辑。

## 用户可见与协议结果

- 状态快照可表达 `zcode` 来源；未来未知来源会降级为通用 Agent，而不会让整条快照失败。
- 新增可选 `usageProviders`，同时保留原 `usage` Codex 读取路径。未知提供方、额度组和额度类型使用开放字符串承载。
- 新增可选 `pendingRequests[].requestID` 与控制载荷 `pendingRequestID`；旧消息缺少字段时保持现有任务级处理路径。
- Android 对 ZCode 使用现有青色来源强调，对未知来源显示通用 `Agent / 未知来源`，没有增加专属页面或 GLM 额度 UI。
- Windows 本票只增加解析、序列化、转发和签名兼容，没有增加 Hook 或网络能力。

## Gate 0 约束

- 时间继续使用 Unix 整数毫秒。
- `usedPercentage` 表示已使用比例；`remainingAmount` 保存服务端独立 `remaining`，不由总量减已用量重算。
- `quotaType` 当前样本为 `CREDIT_LIMIT`，但协议使用开放字符串以兼容未来类型。
- `planLevel` 可选且不透明；样本的展示回退名为 `GLM Coding Plan`，没有把 `lite` 推断成套餐名称。
- `Stop` 仍只代表模型轮次结束；本次没有增加把 ZCode 会话直接标记成功的状态归约。

## 兼容样本与测试

- `protocol/fixtures/task-snapshot.json`：旧 Codex 快照。
- `protocol/fixtures/task-snapshot-v2.json`：ZCode、多提供方额度、旧 `usage` 和请求标识并存。
- `protocol/fixtures/task-snapshot-unknown.json`：未知来源、未知提供方/额度组和缺失可选字段。
- macOS：`swift test` 通过，共 105 项 Swift Testing 测试。
- Android：`testDebugUnitTest lintDebug assembleDebug` 通过；协议测试经过真实 `PhoneSession` 接收与签名路径。
- Windows：已增加 6 项 Core 回归入口中的协议测试，但当前 macOS 开发机没有 `dotnet` 或其他 C# 编译器，因此本次未实际运行 Windows 测试。
- `jq empty` 与 `git diff --check` 通过。

## 未验证项

- 未在 Windows/.NET 环境编译或运行新增测试。
- 未安装或替换 Bridge/APK，未运行真实 ZCode Hook、GLM 请求、模拟器或 Redmi 产品验收；这些均不属于 Issue #3 的协议模型范围。
