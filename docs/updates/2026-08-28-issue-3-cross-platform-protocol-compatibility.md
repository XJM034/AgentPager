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
- Windows：已增加 6 项 Core 回归入口中的协议测试；实际运行状态和验收边界见“用户批准的 Windows 运行验证豁免”。
- `jq empty` 与 `git diff --check` 通过。

## 未验证项

- 未安装或替换 Bridge/APK，未运行真实 ZCode Hook、GLM 请求、模拟器或 Redmi 产品验收；这些均不属于 Issue #3 的协议模型范围。

## 用户批准的 Windows 运行验证豁免

- Windows 协议实现和 6 项 Core 协议测试已经编写，并已完成代码复审；这不代表 Windows 已实际验证通过。
- 当前开发机没有 .NET 工具链或 Windows 运行环境，因此 Windows 项目没有实际编译，6 项测试也没有实际运行。用户明确批准本次不安装临时 .NET SDK，也不新增或触发 Windows CI。
- AgentPager 当前个人定制和使用范围是 macOS 与 Android；在这两个平台的检查已经通过的前提下，上述 Windows 验证缺口不阻塞 Issue #3 的本次验收收尾。
- 如果未来需要构建、安装或发布 Windows 版本，必须在受支持的 Windows/.NET 环境重新执行 Windows 编译、全部测试和实际运行验收；本次豁免不能沿用为未来 Windows 发布依据。
