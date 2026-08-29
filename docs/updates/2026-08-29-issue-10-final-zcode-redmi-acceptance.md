# Issue #10：最终真实 ZCode、默认无 GLM Key 与 Redmi 验收

日期：2026-08-29

## 结果与范围

本次严格限定在 GitHub Issue #10，以 `alexx_custom` 分支提交
`c35faf88ac16a45de10e84b3a789eee539cfd4ee` 作为 Build 13 的构建与验收基线，完成：

- macOS AgentPager Bridge Build 13 的打包、签名与哈希核对、Build 12 备份、安装和真实端口验收；
- Android Debug 定制版 Build 13 的构建、保留数据安装、官方版共存和 Redmi Note 7 现场验收；
- 通过正式 Bridge 设置界面安装、验证并恢复 ZCode Hook；
- 真实 ZCode 桌面 Session 的七类事件、工具失败、超时回退、手机 approve/deny 和 `Stop → idle`；
- 默认不向 AgentPager 配置第二份 GLM Key 的隐私模式。

没有访问真实 GLM 额度接口，没有读取 GLM Key、ZCode OAuth、Cookie、provider、缓存、配对密钥或认证头；没有推送、评论或关闭 Issue、创建 PR/Release、配置正式签名或公证，也没有运行 Entire Review。

## 基线与门禁

- 构建提交：`c35faf88ac16a45de10e84b3a789eee539cfd4ee`。
- 构建时本地、tracking 与 GitHub `origin/alexx_custom` 一致，分歧为 `0 / 0`，暂存区为空。
- Issue #11 为 `CLOSED / COMPLETED`；Issue #10 在收尾取证时仍为 `OPEN`。
- macOS 全量测试：AgentGridCore `163/163`、AgentGridBridge `8/8`，0 失败。
- 两个 Local Bridge E2E 均通过：默认无 Key 场景约 0.031 秒，可选合成 Key 场景约 0.050 秒。
- Android 单元测试、Lint 和 Debug 构建全部通过；55 个 Gradle task 中 23 个执行、32 个复用，0 失败。

## macOS Bridge 安装结果

安装目标：`/Applications/AgentPager Bridge.app`

- Bundle ID：`com.agentpager.bridge`
- 版本：`0.3.0`
- Build：`13`
- 架构：arm64
- 签名：有效的 ad hoc 签名，启用 runtime；无 Team ID
- Bridge 二进制 SHA-256：`cd8f98c0d354746bc9b9ca33d40b26e6e4a78b41133cf3c7edae221df0b23102`
- 运行 PID：`31544`
- 实际二进制路径：`/Applications/AgentPager Bridge.app/Contents/MacOS/AgentPagerBridge`
- 49361、49362：均由 PID `31544` 监听

本地打包产物 `dist/AgentPager Bridge.app` 同为 `0.3.0 (Build 13)`，签名有效，Bridge 二进制哈希与已安装副本一致。

安装过程中没有出现钥匙串阻塞，没有触发失败回滚。默认无 Key 验收完成后，Bridge 仍由相同 PID 在两个生产端口正常运行。

## Bridge 备份与回滚

已安装 Build 12 的恢复副本：

`/Users/minxian/Library/Application Support/AgentPager/Backups/issue-10/2026-08-29-build12-before-c35faf88/AgentPager Bridge.app`

原 `dist` Build 12 的恢复副本：

`/Users/minxian/Library/Application Support/AgentPager/Backups/issue-10/2026-08-29-dist-build12-before-c35faf88/AgentPager Bridge.app`

两个备份均为 `0.3.0 (Build 12)`，签名有效，Bridge 二进制 SHA-256 均为：

`9b1c542b379898f60c9b51737fd3546c8390bf802bb55bae2b3586f1623f2583`

如需回滚，应只终止当前精确 Bridge PID，将 Build 13 移到独立隔离位置，再复制上述已安装 Build 12 备份回 `/Applications`；随后复核 Build 12 哈希、签名、实际进程路径和两个端口。不得宽泛清理或删除备份。

## Android Custom 安装结果

APK：`android/app/build/outputs/apk/debug/app-debug.apk`

- APK SHA-256：`373e903ff5ea4f5b4f05681d83e95df22648e3e28a8e0051e9f66e72aa3820ad`
- application ID：`com.agentgrid.mobile.custom`
- 应用名：`AgentPager Custom`
- versionCode：`13`
- versionName：`0.3.0-custom`
- Debuggable：是
- 安装目标：序列号 `bab1b5c`，`Redmi Note 7`，设备代号 `lavender`
- 验收时定制版进程 PID：`1941`

安装采用保留数据的同包替换。定制版首次安装时间保持为 `2026-08-24 17:43:42`，安装后更新时间为 `2026-08-29 19:19:57`，支持用户数据被保留的结论；没有清除数据或重新配对。

官方版 `com.agentgrid.mobile` 仍独立存在，版本为 `0.3.0 (versionCode 4)`，首次安装和更新时间均未变化，因此没有被定制版覆盖。

安装前定制 APK 备份：

`/Users/minxian/Library/Application Support/AgentPager/Backups/issue-10/2026-08-29-redmi-bab1b5c-custom-before-c35faf88/base.apk`

备份 SHA-256：`01fc98988104680f90b3e2670ca8d45b458c99a552d6b2587fcb1a4d3f6773bf`。如需回滚，只对同一序列号和 `.custom` 包执行保留数据的同签名替换安装，不清除数据、不操作官方版；回滚后复核包名、版本、首次安装时间、进程和 Bridge 连接。

## ZCode Hook 安装、真实 Session 与恢复

安装前 `~/.zcode/cli/config.json` 不存在，父目录为普通目录且不是软链接，因此没有现有第三方配置字段需要合并或覆盖。Hook 通过 Build 13 的正式设置界面“安装或修复”安装，没有直接手写配置。

安装后：

- 配置为普通文件，权限 `0600`；
- 配置 SHA-256：`a10e371cdcaf3713f4d1580de324c165b760a9ebed4244ec4cca433d3f538aee`；
- 安装前“配置不存在”恢复标记为：
  `/Users/minxian/.zcode/cli/config.json.agentpager-zcode-backup-1788002715.absent`；
- 恢复标记权限 `0600`，SHA-256：
  `057c804ebc6630bc19f25ccd5a69b6eb8e15012aba653dbed4ff9756489197ad`。

真实 ZCode 桌面 Session 验证了：

- `SessionStart`
- `UserPromptSubmit`
- `PreToolUse`
- `PostToolUse`
- `PermissionRequest`
- `PostToolUseFailure`
- `Stop`
- `Stop → idle`
- 工具失败时任务仍保持 running，随后工具和同一 Session 后续输入可以继续；
- 手机审批超时后正确回到 ZCode 本地审批；
- 手机 approve 只产生对应批准结果；手机 deny 不产生被拒绝结果；
- deny 后同一 Session 继续运行；
- 手机活动信息没有展示完整 prompt、命令、工具输入、响应或错误正文。

真实验收使用 ZCode 桌面 App。内置 headless CLI 的帮助与参数解析存在不一致，且该路径要求显式 ZCode model provider；根据凭据边界没有读取或修改 provider，也没有运行登录，因此 headless CLI 不作为本次通过证据。

验证完成后，通过正式 Bridge 设置界面的“检查最近备份 → 确认恢复最近备份”恢复。最终 `~/.zcode/cli/config.json` 不存在，界面状态为“未安装”。恢复前安装态另行备份为：

`/Users/minxian/.zcode/cli/config.json.agentpager-zcode-before-restore-1788007227`

该备份权限 `0600`，SHA-256 与安装态一致：

`a10e371cdcaf3713f4d1580de324c165b760a9ebed4244ec4cca433d3f538aee`

恢复期间当前配置指纹未变化，测试期间没有新增第三方字段，因此恢复没有覆盖并发用户配置。

## 默认无 GLM Key 模式

本 Session 没有选择 GLM opt-in。仅通过不读取值的元数据检查确认 AgentPager 预期 GLM 钥匙串项目不存在；没有询问、读取、保存、复制或验证真实 Key，也没有访问真实 quota endpoint 或 BigModel.cn 页面。

真实运行与现场结果：

- Bridge 持续正常运行，没有出现可见 GLM 鉴权错误；
- Android 顶栏只显示 GENERAL 和 SPARK，没有 GLM 空占位、`--%`、0% 或额度耗尽；
- ZCode Session、手机 approve/deny、Codex 和 Claude 监控均由用户现场确认正常；
- 用户不启用第二份 GLM Key 不影响 Issue #10 的默认隐私模式验收。

没有进行网络包级观测，因此不宣称通过抓包证明“零请求”。无 Key 下不访问真实 GLM 的结论由钥匙串项目缺失状态、真实运行表现和默认无 Key 自动化共同支持。

**真实可选 GLM 额度路径未复验。**

## Redmi 现场人工验收

以下项目均由用户在 Redmi Note 7 上人工确认通过，工具没有替代用户判断听觉、触觉或肉眼体验：

- ZCode 状态与活动文案
- waitingApproval 自动置顶
- approve / deny
- Stop 后 idle
- 顶栏无 GLM 空占位
- 声音
- 振动
- 常亮
- 亮度
- MIUI 前后台行为
- 第一条任务无遮挡
- Codex / Claude 原有功能无明显回归

## 证据边界

### 已由真实运行或现场验证

- Build 13 的安装版本、签名、二进制哈希、实际 PID 和两个端口；
- Android Custom 的包名、版本、数据保留、进程和官方版共存；
- ZCode 桌面真实 Session、七类 Hook、超时本地回退、approve/deny 隔离、失败后继续和 Hook 恢复；
- Redmi 的状态、布局、声音、振动、常亮、亮度和 MIUI 前后台体验；
- 默认无 Key 下手机无 GLM 空占位，Codex/Claude 现场无明显回归。

### 由代码或自动化支持，未提升为现场网络证明

- 默认无 Key Local Bridge E2E 断言 GLM provider 不进入快照且 fake provider 请求数为 0；
- 可选合成 Key E2E 覆盖 GLM 成功与诚实降级，但没有使用真实 Key或服务；
- 标题、活动、错误与工具信息的脱敏由真实手机表现和自动化共同支持；
- 未抓包，因此真实环境“零 GLM 请求”不是包级证明。

### 未验证

- 真实可选 GLM Key、真实额度接口、真实官网同时间对照及真实删除流程；
- headless ZCode CLI 的完整 Session 路径；
- 正式 Developer ID 签名、Apple 公证、DMG、Release 或公开分发；
- Windows 编译与真实运行。

## 工作区与外部状态保护

验收前已有的已修改、未跟踪文件没有被覆盖、回退或暂存；tracked dirty diff 指纹在安装、测试、Hook 和 Redmi 阶段始终为：

`b96cee81c480dc8267987fbdb7f91c4993f06b7c337b1b3283917769ad7694dc`

`.entire/` 没有被手工编辑、清理或回退；当前活动 Session 的元数据由 Entire 自身继续追加。除本记录外，不暂存用户原有文件。

Issue #10 保持 `OPEN`。本次不修改 GitHub Issue、标签或状态，不推送、不发布、不创建 PR/Release，也不运行 Entire Review。
