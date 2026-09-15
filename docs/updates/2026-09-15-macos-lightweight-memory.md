# 2026-09-15 Mac Bridge 轻量化

## 用户确认的范围

- 只精简 Mac，Android 代码和安装保持现状。
- 保留会话监控、手机批准/拒绝、配对与局域网同步。
- 特别保留 Codex General / Spark 和 GLM 剩余额度、重置时间、手动及既有自动刷新；这是用户经常观察的指标。
- 用户同意取消 Mac 持续像素动画、90 天历史用量统计及费用估算。手机不再收到新的历史统计，已有空态可处理，无需修改协议或 Android。

## 证据与原因

截图显示 AgentPager Bridge 3 个进程合计 544.6 MB。现场仅观察到一个主进程，运行约 27.5 小时；`sample` 记录当前 physical footprint 129.9 MiB、峰值 549.9 MiB，`ps` 约 20.5% CPU。截图统计口径、主进程 footprint 与 RSS 不相同，不能直接混算。

- 当前主进程采样有大量 PixelCoreView、SwiftUI 更新和 RenderBox 模糊纹理调用。代码中空闲图标每秒 30 帧，其他活动状态每秒 60 帧，每个亮格有三层模糊光晕。
- 旧版默认额度加载同时遍历历史用量并尝试调用 CodexBar。独立 Release 探针在本机真实日志上连续调用两次，footprint 达 432.2 / 812.3 MiB，复现扫描临时对象累积。
- 该探针没有 AppKit 自动事件循环回收，不能把探针数字解释为已安装 App 的固定常驻值；它验证后台同步扫描缺少显式回收边界的峰值风险。
- 过去日志轮询的 2 MiB 分块修复仍保留；本轮未改任务归约、审批权限、WebSocket 协议或 GLM 凭据链路。
- 截图另外两个进程的身份未现场捕获；CodexBar 调用来自代码证据，不能认定截图中的进程就是它。

## 实现

- `PixelCoreView` 去掉 TimelineView、逐格多层模糊、过渡帧缓存，使用既有状态颜色和 reduced-motion 固定帧；仅状态变化时重绘。菜单与设置调用同步更新。
- `CodexUsageLoader` 默认只生成当前额度快照；历史解析通过 `includeHistory: true` 显式调用保留测试兼容，生产默认路径不启动 CodexBar。
- 额度扫描逐文件建立自动释放边界，整次扫描结束也回收目录枚举等临时对象；单文件尾部读取严格限制在 512 KiB。
- 每个 `BridgeRuntimeConfiguration` 持有并复用同一 loader，未修改日志命中缓存；已变化日志仍重新解析。
- 添加默认轻量额度回归测试，覆盖剩余比例、重置时间、General / Spark 双组及无历史输出；原有历史测试改为显式启用历史。

## 已验证

工具链：Xcode 27.0（27A5252f）、Apple Swift 6.4、macOS SDK 27.0、arm64；最低运行系统仍为 macOS 14。`xcodebuild -checkFirstLaunchStatus` 返回 69，Swift 实际构建和测试成功，未修改系统工具链或初始化配置。

| 检查 | 结果 |
| --- | --- |
| 新测试修改前 | 失败：默认路径仍生成 90 天历史 |
| `swift test --package-path macos` | 171 个 Core + 12 个 Bridge 测试全部通过；含真实本地端口的合成同步、审批与 GLM 故障隔离 |
| `swift build -c release --package-path macos` | 通过；已有钥匙串旧 API 警告 |
| 空闲图标隔离测试，预热 2 秒后测 8 秒 | 修改前 71.4 MiB / 6.2% CPU；修改后 18.5 MiB / 0.0% CPU（显示精度） |
| 真实日志额度探针，连续两轮 | 修改前 432.2 / 812.3 MiB、2.95 / 1.80 秒；修改后 20.8 / 21.1 MiB、0.67 / 0.11 秒 |
| 新版连续 20 次额度刷新 | 约 21.1 MiB 稳定，后续约 0.10 秒；两组额度保留、历史数组为空；低于 80 MiB 且增长低于 20 MiB 的探针断言通过 |
| 静态图标渲染检查 | 8 类状态图标均实际渲染并检查 PNG |
| 本地打包与签名 | `dist/AgentPager Bridge.app`，0.3.0 (19)、arm64、`com.agentpager.bridge`；沿用当前 Apple Development 团队签名，严格签名校验通过 |

本地诊断产物均位于被忽略的 `dist/diagnostics/memory-lightweight/`，不提交真实日志或账号数据：`run-pixel-probe.sh`、`run-usage-probe.sh`、探针 Swift 源码、测试/构建日志和静态状态截图。探针编译路径对应本次 Swift 构建输出；它们是标明用途的本机诊断工具，不是跨机器 CI。

## 安装与真实验收

- 用户明确授权“现在备份并安装”，已于 14:10 安装并启动 `/Applications/AgentPager Bridge.app` Build 19。
- 旧安装原件已备份至 `dist/backups/AgentPager Bridge-installed-build18-20260915-141036.app`；备份与原件主二进制哈希相同。安装后 App / Hook 二进制与构建产物哈希一致，严格签名检查通过。
- 打包前的 dist Build 18 另存于 `dist/backups/AgentPager Bridge-build18-before-lightweight-package.app`。
- 新包主二进制 SHA-256：`60a92b112b71b3907a777f2e7e5c4d1bfc79dc6c67f70ed4db2e87b9d2329a57`。
- 新版实际主进程 PID 19850：启动约 54 秒时 physical footprint 44.5 MiB、峰值 47.7 MiB；约 93 秒时 44.7 MiB、峰值仍 47.7 MiB。`ps` CPU 观察值 0.1%–1.7%；RSS 与 footprint 口径不同，不把它们混写为同一指标。
- 后续 `top -l 7 -s 10` 连续约 60 秒采样：内存从约 43 MB 回落至 34 MB，后续 CPU 0.1%–0.7%，未观察到持续增长。原始脱敏指标保存在 `dist/diagnostics/memory-lightweight/installed-top.txt`；属于约数分钟的短时验收。
- 49361 / 49362 监听正常。使用已安装 Hook 运行 `node scripts/e2e-local.mjs`：状态同步、反向审批、结束收敛及关闭帧存活通过。
- 实际 WebSocket 快照中 Codex General / Spark 的剩余比例与重置时间字段保留；GLM 状态 `available`，捕获时间 14:11:29，5H / WEEK 窗口均包含剩余比例。历史数组为空。Codex 来自既有本地日志，窗口存在不代表最近发生过该模型的额度更新。
- 用户现场明确确认“连接和额度显示都正常”，作为本轮手机实际连接和额度画面的验收证据。Android 未修改或重新安装。
- 原生界面自动读取未完成：Computer Use 按完整 App 路径读取超时，按 Bundle ID 恢复时因多个本地备份产生歧义，已停止这条验证路径。静态图标已独立渲染检查；不把它等同于完整设置窗口自动验收。
- 尚未验证：数小时/全天内存、真实 Agent 发起的审批全过程以及两个十分钟 GLM 自动刷新周期。短时实测、用户手机反馈、合成端到端和真实 GLM 新数据分别记录，不互相替代。
- 回滚：正常退出新版，再用上述 installed-build18 备份恢复 `/Applications/AgentPager Bridge.app`，核对签名后重新启动；不要修改 Hook 配置或钥匙串权限。
- 本轮只修改 Mac 源码/测试及说明文档，保留会话开始时的既有文档改动。按用户授权形成本地提交，未推送或发布。
