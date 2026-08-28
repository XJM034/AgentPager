# Issue #4：首次贯通 ZCode 会话监控

日期：2026-08-28

分支：`alexx_custom`

可靠远端基线：`13887f33b0331fd7cbb5123722d2c8c6c2aef3f8`

## 结果

Issue #4 已完成一条最小但完整的 ZCode 会话监控路径：macOS Bridge 可以检查 ZCode Hook 是否按当前 Bridge 路径配置，并提供“安装或修复”入口；五类核心事件通过本地 Hook Bridge 归约为共享 `TaskSnapshot`；Android 沿用现有任务列表、排序、自动展开、PixelCore、声音、振动和亮度策略显示 ZCode 任务。

该路径不依赖 GLM Key。实现没有读取或修改真实用户 ZCode 配置，没有安装 Bridge 或 APK，也没有连接真实 ZCode 会话。

## Gate 0 语义修正

Issue #4 早期草案中的 `starting → running → succeeded` 已明确废弃。本实现选择共享生命周期中已有的 `idle` 作为最保守的非终态表达：

`starting → running → idle`

`Stop` 仅清除当前活动和步骤，保留任务但不设置 `completedAt`、未读完成态或成功终态。后续同一 Session 的 `UserPromptSubmit` 会从 `idle` 返回 `running`。原因是 Gate 0 只能证明当前模型轮次结束，不能证明会话正常完成、被中断或已经进入终态。

未知事件不改变已有生命周期。首版识别到 `Agent` 或 `Task` 工具时只复用现有“正在协作”活动，不创建子代理层级。

## 实现范围

### macOS Bridge 与共享模型

- 新增 ZCode Hook payload 解码，兼容 `session_id` / `sessionId`、`hook_event_name` / `hookEventName`、`tool_use_id` / `toolUseId` 等 Gate 0 字段别名。
- 新增五类核心事件的 reducer：`SessionStart`、`UserPromptSubmit`、`PreToolUse`、`PostToolUse`、`Stop`。
- 标题仅由首个 prompt 生成稳定短标题，先脱敏再截断；完整 prompt、命令、源码、工具输入输出和真实路径不进入快照或普通日志。
- 工具活动只投影为固定安全文案，例如读取、搜索、编辑、执行、测试、浏览和协作。
- `Agent` / `Task` 工具只映射到现有 `delegating` 活动，不生成 `SubagentSnapshot`。
- Hook 安装器仅管理带有 `Managed by AgentPager (ZCode)` 标记的五个事件组，保留根配置、其他 Hook 字段和第三方事件组；结构异常时拒绝覆盖。
- 安装已有配置前创建时间戳备份；本票不提供卸载或恢复入口。
- Bridge 菜单和 Hook 设置页提供安装状态及“安装或修复”操作。
- 合成 Hook 通过真实 TCP `HookBridgeServer`、`TaskCatalog` 和共享快照编解码完成最高层接缝验证。

### Android

- 复用 Issue #3 已加入的 `zcode` 来源解码和共享任务模型。
- 任务行显示 `ZCODE` 徽标、项目名、稳定短标题、启动/思考/核心工具活动和非终态空闲状态。
- 新增合成数据 Compose Preview，同时展示启动、思考、工具活动和非终态空闲任务行。
- 没有新增第二套生命周期、列表排序、声音、振动、亮度或动画策略。

### Windows

Windows 继续沿用 Issue #3 的协议解析和转发兼容。本票没有新增 Windows Hook，也未进行 Windows 实际运行验证。

## TDD 接缝与验证

实现按 payload、reducer、配置、真实 Bridge 接缝和 Android 投影依次完成红灯到绿灯：

- ZCode payload 解码测试先因类型不存在失败，再实现别名和稳定 `tool_use_id` 解码。
- reducer 测试先因 reducer 不存在失败，再实现 starting、running、核心工具活动和 `Stop → idle`。
- Hook 配置测试先因配置器不存在失败，再实现状态检查、安全合并、幂等、备份和异常结构拒绝覆盖；复审发现混合事件组风险后，又以红灯测试锁定“只替换本方 Hook、保留同组第三方 Hook”。
- Bridge 接缝测试先因 ZCode envelope/catalog 输入不存在失败，再接通真实 TCP Bridge 到共享快照。
- Android 展示测试先因展示接缝不可测试失败，再调整可见性并验证徽标、来源、活动和空闲文案；复审发现任务行未消费 `activity` 后，又以红灯测试锁定启动显示“正在启动”、运行思考显示“正在思考”。

实际运行结果：

- `cd macos && swift test`：115 个测试通过，0 失败。
- `cd android && JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home" ./gradlew testDebugUnitTest lintDebug assembleDebug`：65 个 JVM 单元测试通过，Lint 与 Debug APK 构建通过；共 55 个 Gradle task，构建成功。
- 新增 JSON fixture 使用 `jq` 解析通过。
- `git diff --check` 和候选改动敏感信息扫描通过。

## 未验证与明确延期

本次未执行：真实 ZCode Hook 配置安装或修复、真实 ZCode 新 Session、Bridge 菜单人工验收、模拟器、Redmi 真机、Bridge/APK 安装、真实手机局域网连接、长期性能、Windows 实际运行。

留给 Issue #5：全部七类事件的稳定化、未知事件与失败降级、完整备份恢复、安全卸载和第三方 Hook 的更完整故障场景。

留给 Issue #6：手机端 ZCode 权限批准或拒绝、`pending request` 回传、超时与断线回退。本票即使收到权限事件也不会把它转成手机审批。

留给 Issue #7/#8：GLM Key、网络查询、额度、详情和错误降级。

## 开场时已有的用户内容

以下内容在本 Session 开始前已经存在，未被本票修改、暂存或提交：

- `.agents/skill-profile.json`
- `AGENTS.md`
- `CLAUDE.md`
- `docs/README.md`
- `.claude/agents/`
- `.claude/settings.json`
- `.codex/`
- `.entire/`
- `docs/custom-development-workflow.md`
- `docs/updates/2026-08-28-glm-coding-plan-quota-monitoring-research.md`
- `docs/updates/2026-08-28-zcode-glm-session-quota-prd.md`
- `docs/updates/2026-08-28-zcode-session-monitoring-research.md`
