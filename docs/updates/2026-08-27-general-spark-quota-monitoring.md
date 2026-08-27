# 2026-08-27 Android General 与 Spark 额度监测

## 产品效果

- Android 首页同时支持 General 7d、Spark 5h 与 Spark 7d 三个额度窗口。
- 首页额度改成与右侧用量、设置按钮同高的 28dp 单行条，不再占用第一条 Agent Session 的空间。
- 额度页保留 General 主读数，并在下方增加 Spark 5h / 7d 双窗口。
- 旧 Bridge 只有 General 数据时保持原体验，不显示空的 Spark 占位。

## 原因与数据处理

Codex rollout 中 General 与 Spark 是两个独立额度组：General 使用 `limit_id=codex`，Spark 使用 `limit_id=codex_bengalfox`。旧实现只取最后一个额度快照，因此界面会随最近更新的会话在 General 和 Spark 之间切换。

macOS Bridge 现在按额度组分别保留最新快照，即使同一个 rollout 文件交替出现 General 与 Spark 也能正确归并。为兼容旧客户端，协议根层的 `windows` 仍固定优先发送 General；新增的 `quotaGroups` 承载完整额度组。

读取范围继续受控：只扫描 8 天内的候选 rollout，找到 General 与 Spark 后停止，不增加云服务、遥测或外部上传。

## 涉及范围

- macOS Bridge：额度组归并、协议模型与单元测试。
- Android：协议模型、首页紧凑额度条、额度页双组展示、兼容回退与单元测试。
- Windows：同步新增协议字段与额度组归并，避免跨平台协议分叉。
- 未改变配对、审批、任务状态、Token 历史用量、通知、亮度、包名和签名策略。

## 验证结果

- Android：`testDebugUnitTest lintDebug assembleDebug` 通过，55 个任务中 7 个执行、48 个命中缓存。
- macOS：`swift test` 通过，共 88 个测试；新增用例覆盖同一文件中 General / Spark 交替出现。
- Android 模拟器 `medium_phone`：通过本地模拟 Bridge 验证 General + Spark 三窗口首页和额度页。
- Redmi Note 7 `bab1b5c`：已安装并启动 `com.agentgrid.mobile.custom`；连接 build 8 后真实显示 General 91%、Spark 5h 100% 与 Spark 7d 100%，确认 28dp 额度条与右侧按钮同高，任务列表无覆盖。
- Bridge 端到端：`node scripts/e2e-local.mjs` 通过状态同步、反向审批、结束收敛与关闭帧存活。
- `git diff --check` 通过。
- Windows：本机缺少 `dotnet`，未完成编译验证。

设计对照与截图路径记录在仓库根目录 `design-qa.md`。

## 安装结果

- 新 macOS Bridge 已按 build 8 打包到 `dist/AgentPager Bridge.app`，临时签名严格校验通过，二进制 SHA-256 为 `7ebc86304eb40a6827d73b7e25bedf6e84fa4fa696359d292c8ae4a6673f3852`。
- 已将 build 8 安装到 `/Applications/AgentPager Bridge.app`，安装后哈希与 `dist` 产物一致，进程 PID 6161，端口 49361 / 49362 正常监听。
- Redmi 已重新建立到 `192.168.10.73:49362` 的局域网连接，并完成真实三额度验收。
- 原 build 7 完整备份在 `dist/backups/AgentPager Bridge-0.3.0-build7-before-spark-20260827-142545.app`，二进制 SHA-256 为 `835578768a39f30006b66b8563c310098aa48f37c07525cc897d4823564b41ef`。

## 回滚

- Android UI 可回退顶部额度组展示与 `quotaGroups` 解析，旧根层 `windows` 仍可继续工作。
- macOS Bridge 可停止 build 8 后，将上述 build 7 备份移回 `/Applications/AgentPager Bridge.app` 恢复。
