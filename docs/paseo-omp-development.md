# Paseo–omp 开发接入（#14）

当前阶段：已提供官方 Paseo 插件、公开 SDK 初始目录订阅、带认证的本机 Bridge 入口及 Android 来源展示。此页不代表已安装插件、已替换 Bridge 或已通过 Redmi 验收。父规格 #13 的轮次进度、异常、全面重连和正式安装管理分别留给 #15–#18。

## 行为与边界

- 仅导入 Paseo provider 为 `omp` 的有效会话。排除归档、closed 历史和其他 provider；创建回调排除带 parentAgentId 的子会话事件（SDK 目录快照不提供此字段）；不扫描独立终端 omp。
- 插件同步注册 `agent.created`，通过回调的公开 `agents.ref(id).refresh()` 读取权威状态；独立的公开 SDK 连接负责初始分页清单与目录订阅。只用 `@getpaseo/client` 根入口，不读取私有存储、不接管 omp stdin。
- `Paseo 主机命名空间 + agent ID` 生成不可逆任务 ID；模型、标题、目录不参与身份。命名空间在本地配置生成一次，后续保持不变。
- 新会话沿用 idle / starting / running 语义，不造 completedAt、完成标记或手机审批能力。#14 只发现会话，不连续映射工作轮次；启动阶段允许从 initializing 收敛到创建后的状态；除此之外重复发现不会重置既有卡片、时间、静音和置顶。
- 项目仅保留最多 48 字符的目录末级名，用户主目录回退为 omp。标题先在插件内映射为有限类别，Bridge 再复用 ZCode 安全标题策略。原始标题、提示词、完整路径、命令、工具内容、模型凭据均不发送。
- Swift、Android、Windows 增加 `omp` 来源；未知来源回退仍保留整份快照。Windows 仅编解码，不采集。
- 首次手机快照沿用提醒基线；空闲会话保持可见，不转换为 ZCode 的“本轮完成”。本票不新增声音设置。

## 信任与故障边界

配置文件必须为 `0600`；Bridge 接入只绑定 `127.0.0.1`，使用独立随机 256 位 token，不复用手机配对密钥。入口限制 4 KiB、16 个连接、2 秒超时；插件串行发送、队列最多 200 条安全摘要、单连接 1.5 秒超时。配置、token 和 Paseo 本地连接认证信息不得进入 Git、手机或诊断。

Paseo 插件本身属于官方定义的“可信、无沙箱”代码。插件异常只记录固定诊断，捕获失败，不阻止模型任务。#14 没有跨断线可靠重放；入口不可用、队列超过限制或订阅连接丢失时可能漏发现，需要重载后重新获取初始清单；完整恢复由 #17 处理。不要把此开发入口当作正式无人值守交付。

## 可重复开发启用

以下是待授权现场操作步骤，本票执行时没有安装或重启真实 Paseo、Bridge、Android，也没有发起模型调用。已核对本机 Paseo CLI 0.8.0、omp 18.2.8；源码和 npm SDK 锁定 0.8.0。

1. 核实目标 Paseo daemon 的本机 WebSocket 地址、已有插件与配置。保留其现有配置备份；不更改 Full Access / Key / 其他插件。地址以目标 daemon 为准，不盲用默认值。
2. 在新的私有目录准备配置。例如默认插件路径：

   ```sh
   python3 scripts/prepare-paseo-development.py "$HOME/.config/agentpager" --paseo-url ws://127.0.0.1:6767/ws
   ```

   父目录必须已存在。脚本拒绝覆盖既有目录，生成新命名空间、认证 token 和独立 49461/49462/49463 端口，不安装、重启或改写任何 App。端口被占用时用三个 `--*-port` 参数另选。Paseo 有本机连接认证时，仅在该 0600 配置中补 `paseoPassword` 或 `paseoAuthHeader`；这是本地连接认证，不是模型 Key。不得打印文件正文。
3. 构建并启动隔离开发 Bridge：

   ```sh
   swift build --package-path macos
   AGENTPAGER_PASEO_DEVELOPMENT=1 \
   AGENTPAGER_PASEO_CONFIG="$HOME/.config/agentpager/paseo-development.json" \
   swift run --package-path macos --skip-build AgentGridBridge
   ```

   此模式使用新端口、同目录 `development-tasks.json` 和临时内存配对密钥，关闭真实 Hook 扫描及账号额度读取。重启后须重新配对。不要在开发菜单中操作安装/卸载 Hook。生产模式不受影响；未提供配置时不启用 Paseo 入口。
4. **实际插件安装需要先确认目标及备份**。获准后执行官方命令：

   ```sh
   paseo plugin install /absolute/path/to/AgentPager-0.3.0/integrations/paseo-omp --host localhost:6767
   paseo plugin ls agentpager-omp --host localhost:6767
   ```

   插件默认读取 `~/.config/agentpager/paseo-development.json`。`AGENTPAGER_PASEO_CONFIG` 仅在它已存在于目标 daemon 环境时覆盖路径，给安装 CLI 临时设置环境变量不会改变既有 daemon 的环境。不要为改变路径擅自重启 daemon。
5. Android 使用本票 Debug 构建，包名 `com.agentgrid.mobile.custom`。实际安装按 Android 开发流程核对设备、版本号及数据保留；本票不降级覆盖已装版本。配对隔离 Bridge 后，在 Paseo 创建 omp 会话但不发送消息，应自动出现 `omp / Paseo` 空闲卡片。分别检查同目录两个会话、不同项目、Codex/GLM 模型选择、重载插件后的重复发现；此阶段不启动模型任务。

## 撤销

获得同一目标的操作授权后，用 `paseo plugin disable agentpager-omp --host <原目标>` 停止本插件；需要删除安装记录时用 `plugin remove agentpager-omp`。只处理该插件，保留其他插件与配置。退出本次隔离 Bridge，恢复手机原 Bridge 配对。保留私有配置可沿用命名空间；确认不再需要后自行删除本次新建目录。没有替换 `/Applications`，因此不需要回滚 App。正式安装、恢复与真机完整验收仍按 #18 执行。

## 自动化验证

```sh
npm ci --prefix integrations/paseo-omp --ignore-scripts
npm run check --prefix integrations/paseo-omp
swift test --package-path macos
cd android
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home ./gradlew testDebugUnitTest lintDebug assembleDebug
```

Swift 的 `paseoCreatedSessionReachesPhone` 用受控公开 SDK/生命周期输入运行**实际 JS 适配器、TCP 认证入口、Bridge、任务目录及手机 WebSocket**，不读取真实账号 Key。覆盖初始分页、创建、重复、并发、主机隔离、排除其他来源和历史、认证拒绝及手机/持久化/诊断脱敏。Android 覆盖 PhoneSession 快照接收、看板可见性、标签、未知来源和声音基线。共享 fixture 同时用于三端协议测试。C# 测试需要 .NET SDK；未安装时须明确报告未执行。

这些结果不等于插件在真实 daemon 中已加载、真实 Paseo 创建已验收，或 Redmi 提醒和界面已验收。
