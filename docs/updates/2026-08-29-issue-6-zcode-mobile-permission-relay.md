# Issue #6：贯通手机端 ZCode 单次权限批准与拒绝

日期：2026-08-29

## 结果

Issue #6 在既有 ZCode 七类事件监控和安全 Hook 管理之上，增加了单次
`PermissionRequest` 的手机裁决链路。Android 可以同时展示同一 ZCode Session
内的多个请求，并把批准或拒绝精确送回所选 `tool_use_id`。裁决只作用于本次请求，
不会修改工具输入、写入永久权限、启用 Yolo，或绕过 ZCode 自身的 Plan 与工具限制。

Bridge、手机或连接不可用时，Hook 返回空 stdout，把审批交还 ZCode 本地界面；
不会自动批准。等待时间按 Bridge 45 秒、Hook 客户端 50 秒、ZCode 外层 60 秒分层，
并为外层超时保留安全余量。

## 实现范围

- pending request ID 由来源、Session ID 和 `tool_use_id` 形成稳定 SHA-256 标识，
  不在共享协议中泄露原始标识。
- Bridge 维护 `pending → approved / denied / expired / cancelled` 一次性生命周期，
  同一 Session 支持多个连续或并发请求；重复、未知、过期和已完成请求返回明确结果。
- ZCode Hook 只输出 Gate 0 契约允许的 allow / deny 精确 JSON；fallback stdout 为空，
  日志和诊断不进入 stdout。
- Android 延续 waitingApproval 的置顶、自动展开、声音、振动和 PixelCore 视觉，
  每个按钮绑定自身 request ID；签名覆盖 request ID，并复用既有时间窗、序号、nonce
  与重放保护。
- 协议快照新增请求级标识后，macOS、Android 和 Windows 的兼容解析同步更新；
  Windows 只更新协议夹具断言，不增加 Hook 或 UI。
- Hook TCP 客户端把本机回环连接的 `.waiting` 视为 Bridge 不可用，先取消连接再
  fallback，避免连接恢复后迟发 Hook 形成双审批通道。

## 自动化验证

以下检查通过：

- Android 环境体检；
- macOS Swift 完整测试：144 项通过；
- macOS Release 构建；
- Android Debug 单元测试、lint 和 APK 构建；
- 协议夹具与 ZCode / GLM 契约 JSON 解析；
- Git 空白错误检查；
- Issue #6 差异与新增文件敏感信息扫描；
- Bridge 不可用快速 fallback 回归：修复前会等满测试超时，修复后约 0.003 秒返回；
- Gate 0 精确 stdout、approve、deny、同 Session 并发、所选请求、重复/未知/过期/
  已完成、登记失败、手机离线与中途断线、等待超时、pending 清理、签名与重放、
  脱敏摘要，以及 Codex、Claude Code、既有 ZCode 会话监控回归。

最终 code-review 结果：Standards 0 findings；Spec 0 findings；scope creep 0。

## 真实 Redmi / ZCode 验证

真实验收使用 Redmi Note 7（Android 10）、`com.agentgrid.mobile.custom`、
`0.3.0-custom`、versionCode 12，以及 ZCode Desktop 3.10.1 / CLI 0.16.5。
APK 采用保留数据的覆盖安装，安装后包名和数据目录未变。

真实验证结果：

- 手机出现单次请求后批准，ZCode 继续执行，预期的无敏感测试标记产生；
- 手机拒绝后 ZCode 不执行对应工具，测试标记不存在；
- 同一 Session 的两个请求可以同时出现在手机端并分别完成；
- 两个并发请求中只批准所选请求、拒绝另一个后，最终恰好一个测试标记存在；
- 快速重复点击在 Android UI 层只登记一次，卡片随首次裁决收起；
- 手机在线但不裁决时，请求有界退出并回到 ZCode 本地审批，文件未产生且 pending 清理；
- 等待中停止手机 App 后，Hook 在 1 秒内退出，本地审批接管，重连后旧请求没有复用；
- Bridge 完全不可用的首次真实测试暴露连接 `.waiting` 延迟；经 TDD 修复和最终审查后
  重新验证，Hook 在首次检查前退出，ZCode 立即出现本地审批卡，且未自动执行工具；
- 手机重连后 ZCode Session 任务仍可保留显示，但已取消请求不再带批准/拒绝按钮。

真实验收没有执行登录，没有读取 OAuth、Key、Cookie、钥匙串内容、配置正文或其它凭据，
也没有使用临时 Swift/JIT/标准输入恢复程序。测试使用隔离目录，目录与恢复证据按要求保留。

最终产物哈希：

- Android Custom APK：`09c4f9a64780f62896d614052e20a343d44eb13b0e1138172f4cde37d3550eb6`
- 调试 Bridge：`d9f31988e8f769daecc2f84ba4144779b5e83af96ac6be46d5bf61ab6691590d`
- 调试 Hook：`4b263eb4eaba6ff5e0001d7c87ebeefac729461fb27804de141ac1fbf70b4800`

## 恢复结果

- ZCode Hook 通过正式设置界面安装，并通过“检查最近备份 / 确认恢复最近备份”双确认恢复；
- 测试前 ZCode 配置不存在，恢复后再次确认不存在；恢复证据均保留且权限为 0600；
- 最终调试 Bridge 已停止，原安装版 Bridge 按测试前哈希恢复并监听原端口；
- Redmi Custom v12 保留安装和应用数据，已重新连接原 Bridge；
- 隔离目录、Hook 备份和验收证据未删除。

## 根据代码与自动化推断

- 稳定 `.ready` 连接路径不经过新增 `.waiting` 快速失败分支，因此修复后无需重做此前
  已通过的批准、拒绝、并发选择、超时和中途断线真实场景；最终只重验了受影响的
  Bridge 不可用路径。
- 重复、未知、过期、已完成和控制重放的明确错误结果由真实 TCP / 签名控制自动化接缝
  验证；真实 UI 的快速收起行为无法稳定制造第二个重复控制包。

## 用户批准的豁免

Windows 实际编译和运行继续使用此前批准的环境豁免。本次只核对并更新兼容协议测试，
不得据此宣称 Windows 已实际运行通过。

## 未验证项

- 真实超时场景的精确 45 秒起止没有独立计时；精确常量和安全余量由确定性测试验证。
- 未在真实手机上稳定制造未知 request ID、已完成 request ID、登记失败和签名重放；
  这些路径由自动化测试覆盖。
- Redmi 上的提示音、振动和 MIUI 长时间后台行为没有单独重复验收。
- Windows 实际运行仍未验证。
