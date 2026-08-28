# 2026-08-28 Codex Session 生命周期收敛修复

## 用户可见问题

Android AgentPager 会把已经归档或结束的 Codex Session 长期显示为“运行中”。本次现场证据包括：

- `qwe` 的最后一轮已经中断且 Session 已归档，但 Bridge 持久状态仍为 `running`。
- Codex 内部的 `Memory Writing Agent` 已不在可读取任务列表中，Bridge 持久状态仍为 `running`。

内部任务仍允许显示；本次修复只纠正生命周期，不按任务来源过滤。

## 根因

`CodexRolloutReader` 原先把已经消失的 rollout 文件当成大小为零、暂时没有新增内容。它会永久保留追踪记录，但不会生成结束信号。与此同时，Bridge 重启会直接恢复 `tasks.json` 中的活动态，因此缺少终态事件的任务可以无限保持“运行中”。

## 修复范围

- 已观察到活动态的 rollout 文件消失后保留 5 秒宽限期；文件仍未恢复且同一 Session 没有其他续接 rollout 时，生成 `interrupted` 信号。
- 已经成功或中断的 rollout 消失后不改变终态。
- 同一 Session 仍有时间更新且处于活动态的续接 rollout 时，不因旧文件归档而中断正在继续的任务；旧终态文件或只含 Token 用量的文件不能阻止当前 Session 收敛。
- Bridge 重启恢复持久任务时，按持久化 Session 的启动日期检查前后各一天的目录并回放生命周期，不受常规 10 分钟发现窗口限制，也不遍历完整的 16 GB Session 目录；确认仍在运行或等待的任务保持活动，找不到活动证据的旧状态才收敛为 `interrupted`。
- 常规 10 分钟发现只读取该时间窗口涉及的日期目录和根目录平铺文件，不再每 3 秒递归枚举全部历史 Session。
- 已经进入终态且不在 `session_index.jsonl` 中的任务沿用持久化标题，不再每 750 毫秒重复解析标题索引；活动任务仍会同步 Codex 标题。
- Codex Hook 提供的初始生命周期会同步给 rollout 追踪，覆盖“Hook 已启动但日志尚未写入事件就消失”的情况。

未修改 Android、Windows、协议字段、配对、权限、额度、Hook 安装配置或任务执行方式。

## 验证

- 原始回归命令：
  `cd macos && swift test --filter missingRunningRolloutBecomesInterruptedAfterGracePeriod`
- Entire Review 后新增并通过：新 rollout 消失而旧终态文件保留、只剩 Token 用量文件、超过 10 分钟仍在等待的 Session 启动对账、远日期目录不扫描、常规发现窗口目录约束、终态缺失索引标题不重复刷新，以及缺少活动证据的持久状态收敛。
- 完整 Swift 测试：101 项全部通过。
- 最终安装后的本地 E2E：状态同步、反向审批、结束收敛与关闭帧存活通过。
- `git diff --check` 通过。
- 没有遗留 `[DEBUG-...]` 临时日志。
- Redmi Note 7（序列号 `bab1b5c`）上的 `com.agentgrid.mobile.custom` 保持前台运行；截图人工核对当前会话仍活动，`qwe` 与 `Memory Writing Agent` 均显示“已中断”。MIUI 因缺少 `/data/system/theme_config/theme_compatibility.xml` 无法生成 Android CLI layout，本次按规范使用截图作为次级证据并完成视觉检查。
- 性能复测：目录发现的周期 CPU 峰值由约 13% 降至约 2–3%，稳定采样约 0–0.4%；当前物理占用约 33 MiB。回放最近 2 MiB JSONL 时仍会出现约 401 MiB 的瞬时历史峰值，随后约 352 MiB malloc 区域为空；这是现有 2 MiB 防截断回放边界，不是持续物理内存占用，本次未冒险缩短回放窗口。

## 安装状态

已安装 `/Applications/AgentPager Bridge.app`：

- 版本：`0.3.0 (11)`
- 架构与签名：arm64、临时签名（ad-hoc），Bundle ID `com.agentpager.bridge`
- 最终二进制 SHA-256：`139f9764d4e8fdfadb6ce587fbf648db819b2b4957482570e55f8315745b2435`，与 `dist/AgentPager Bridge.app` 一致
- 最终进程 PID：`40528`；端口 `49361`、`49362` 均监听
- Build 10 完整回滚备份：`dist/backups/AgentPager Bridge-0.3.0-build10-before-lifecycle-fix-20260828-132823.app`，二进制 SHA-256 `e2fda6b72d13419f224300bbba7f4e90f0c76c8ffe39a67156ea5dccf76e6816`
- 调优过程中每次替换前也保留了对应 Build 11 完整备份，位于 `dist/backups/`

没有重装 Android APK，没有提交、推送、发布或创建 Release。
