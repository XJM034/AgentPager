# 2026-08-27 额度审查后续修复

## 背景

针对 General 与 Spark 额度功能的提交审查，本轮修复跨文件快照选择、重复读取日志、分组更新时间显示，以及视觉证据依赖本机临时路径的问题。

## 修改

### macOS 与 Windows：选择最新快照并缓存文件结果

- 不再因为某个文件同时出现 General 和 Spark 就提前停止；所有近期候选文件都会参与比较，最终按每个额度组自己的 `capturedAt` 选择最新快照。
- 解析结果按“文件路径、修改时间、文件大小”缓存。刷新时只重新读取新增或变化的文件，避免 Spark 缺失时每十分钟重复解析全部近期日志。
- 读取 JSON 前先过滤不含 `token_count` 的行，减少无关解析。
- macOS 增加跨文件乱序与缓存失效测试；Windows 增加对应的无第三方依赖回归测试程序。

### Android：分别显示 General 与 Spark 更新时间

- 额度页底部从单一根快照时间改为分别显示每个已展示额度组的新旧程度，例如 `GENERAL 刚刚 · SPARK 2 小时前`。
- 旧 Bridge 没有分组数据时继续使用原有根快照时间；离线提示保持不变。
- 新增不同分组时间戳测试，并用 226dp 窄栏 Compose Preview 验证单行完整显示。

### 文档：保存可复核的视觉证据

- 关键对照图、Redmi 真机截图和本轮更新时间 Preview 均保存到 `docs/assets/2026-08-27-general-spark/`。
- `design-qa.md` 记录尺寸、SHA-256、复现步骤与长期路径，不再依赖 `/tmp` 或 `/var/folders`。

## 验证

- macOS：`cd macos && swift test`，90 个测试全部通过。
- Android：`scripts/android-doctor.sh` 通过；`testDebugUnitTest lintDebug assembleDebug` 通过；模拟器安装启动后，旧 Bridge / 离线状态仍显示 `等待用量数据 · Bridge 离线`。
- Android Preview：226dp 宽度下完整显示 `GENERAL 刚刚 · SPARK 2 小时前`，无截断。
- Windows：本机没有 `dotnet`，已补充测试源码但未执行编译；需在 Windows 或具备 .NET 8 SDK 的环境补验。

## 范围

- 未修改 WebSocket 协议、额度字段、Hook、包名、签名或发布配置。
- 未安装或发布新的 macOS / Android 版本，未推送远程仓库。
