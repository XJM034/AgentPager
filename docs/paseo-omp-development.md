# Paseo–omp 开发接入

当前阶段：#14、#15、#16 均已完成各票实现、自动化、审查和同 Session 隔离 Paseo / Android 验收。#16 的受控请求全序列、真实原生问答/取消和恢复证据见 [#16 最终记录](updates/2026-09-22-paseo-omp-attention-outcomes.md#最终复验恢复与边界)。#15 已验证两个模型的运行、工具活动、正常完成、同会话模型切换与下一轮，详见 [#15 阶段记录](updates/2026-09-22-paseo-omp-turn-progress.md#同-session-补充真实验收)。

#14 已提供官方 Paseo 插件、公开 SDK 初始目录订阅、带认证的本机 Bridge 入口及 Android 来源展示。已用真实隔离 Paseo daemon、真实 omp 空会话和 Android 模拟器完成 #14 验收；证据见 [阶段记录](updates/2026-09-22-paseo-omp-discovery.md#同-session-补充真实验收)。没有替换日常 Bridge 或通过 Redmi 真机验收。父规格 #13 的全面重连和正式安装管理仍分别由 #17/#18 交付。

## 行为与边界

- 仅导入 Paseo provider 为 `omp` 的有效会话。排除归档、closed 历史和其他 provider；创建回调按 parentAgentId、目录/刷新快照按公开 labels 中的 `paseo.parent-agent-id` 排除子会话；不扫描独立终端 omp。
- 插件同步注册 `agent.created`，通过回调的公开 `agents.ref(id).refresh()` 读取权威状态；独立的公开 SDK 连接负责初始分页清单与目录订阅。只用 `@getpaseo/client` 根入口，不读取私有存储、不接管 omp stdin。
- `Paseo 主机命名空间 + agent ID` 生成不可逆任务 ID；模型、标题、目录不参与身份。命名空间在本地配置生成一次，后续保持不变。
- 新会话沿用 idle / starting / running 语义。#15 在公开 activeTurn 和 timeline 基础上同步活动；同轮 turn_ended 为 completed 且权威刷新为 idle、无 activeTurn 时才显示 succeeded / completedAt。下一轮清除完成标记，保持身份、静音和置顶。目录空闲或单工具结束均不独立判为完成，不提供手机审批能力。
- 项目仅保留最多 48 字符的目录末级名，用户主目录回退为 omp。标题先在插件内映射为有限类别，Bridge 再复用 ZCode 安全标题策略。原始标题、提示词、完整路径、命令、工具内容、模型凭据均不发送。
- Swift、Android、Windows 增加 `omp` 来源；未知来源回退仍保留整份快照。Windows 仅编解码，不采集。
- 首次手机快照沿用提醒基线；空闲会话保持可见，不转换为 ZCode 的“本轮完成”。本票不新增声音设置。

## 信任与故障边界

配置文件必须为 `0600`；Bridge 接入只绑定 `127.0.0.1`，使用独立随机 256 位 token，不复用手机配对密钥。入口限制 4 KiB、16 个连接、2 秒超时；插件串行发送、队列最多 200 条安全摘要、单连接 1.5 秒超时。配置、token 和 Paseo 本地连接认证信息不得进入 Git、手机或诊断。

Paseo 插件本身属于官方定义的“可信、无沙箱”代码。插件异常只记录固定诊断，捕获失败，不阻止模型任务。#14 没有跨断线可靠重放；入口不可用、队列超过限制或订阅连接丢失时可能漏发现，需要重载后重新获取初始清单；完整恢复由 #17 处理。不要把此开发入口当作正式无人值守交付。

## 可重复开发启用

以下步骤用于明确目标后的开发接入。#14 已在临时目录和独立端口启动真实 Paseo daemon/Bridge、安装插件，并在保留备份后临时升级 Android 模拟器，验收后恢复；日常 daemon、/Applications 和 Redmi 未改动，也没有发送模型消息。已核对 Paseo CLI 0.8.0、omp 18.2.8；源码和 npm SDK 锁定 0.8.0。

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

   **必须同时满足 daemon 全局 `pluginsEnabled=true`、本插件 enabled 和 omp provider enabled**。新建隔离 daemon 默认可能关闭前两类功能；`plugin install` 返回 enabled 不等于已运行，必须检查 `plugin ls` 的 `status=running`。可通过官方 SDK 的 `client.config.patch({pluginsEnabled: true, providers: {omp: {enabled: true}}})` 配置已核对的隔离目标；不要顺手更改日常 daemon。

   插件默认读取 `~/.config/agentpager/paseo-development.json`。`AGENTPAGER_PASEO_CONFIG` 仅在它已存在于目标 daemon 环境时覆盖路径，给安装 CLI 临时设置环境变量不会改变既有 daemon 的环境。不要为改变路径擅自重启 daemon。
5. Android 使用本票 Debug 构建，包名 `com.agentgrid.mobile.custom`。实际安装按 Android 开发流程核对设备、版本号及数据保留；测试构建不以低版本覆盖已装版本；完成后的模拟器备份恢复见下节。配对隔离 Bridge 后，在 Paseo 创建 omp 会话但不发送消息，应自动出现 `omp / Paseo` 空闲卡片。分别检查同目录两个会话、不同项目、Codex/GLM 模型选择、重载插件后的重复发现；此阶段不启动模型任务。

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

Swift 的 `paseoTurnProgressReachesPhone` 进一步覆盖 #15 的轮次全链路、工具失败仍运行、重复/乱序/同毫秒旧轮保护、初始及新建子会话过滤、快速连续轮次、订阅回收及安全摘要；Android 接收其实际手机快照验证呈现、声音、静音和亮度策略。

Swift 的 `paseoCreatedSessionReachesPhone` 用受控公开 SDK/生命周期输入运行**实际 JS 适配器、TCP 认证入口、Bridge、任务目录及手机 WebSocket**，不读取真实账号 Key。覆盖初始分页、创建、重复、并发、主机隔离、排除其他来源和历史、认证拒绝及手机/持久化/诊断脱敏。Android 覆盖 PhoneSession 快照接收、看板可见性、标签、未知来源和声音基线。共享 fixture 同时用于三端协议测试。C# 测试需要 .NET SDK；未安装时须明确报告未执行。

自动化测试中的 SDK 输入仍是受控数据；真实 daemon、真实创建和 Android 渲染的补充验收另见阶段记录。Redmi 振动、通知、后台和长期运行不由模拟器结果替代，属于 #18。

## 本轮隔离演示的复现要点

- 给 Paseo 使用独立 `--home <私有临时目录>/paseo-home`，监听空闲的 `127.0.0.1:<端口>`；通过 `daemon start --foreground --no-relay --no-mcp --no-inject-mcp --no-web-ui` 启动。启动进程前传入 `AGENTPAGER_PASEO_CONFIG`，SDK URL 使用 `/ws`。不要停掉默认 home 的 daemon。
- 按上面的准备脚本选择独立 Hook/手机/接入端口，启动隔离 Bridge，安装并确认插件 running。测试中还将隔离 daemon 的 `metadataGeneration.providers` 设为空，避免标题生成触发额外推理。
- 从仓库 `integrations/paseo-omp/node_modules/@getpaseo/client/dist/index.js` 导入 `createPaseoClient`，连接该 `/ws`，使用公开 `client.agents.create({config: {provider: "omp/openai-codex/gpt-5.5"}, cwd: <测试目录>, title: <测试标题>})`；GLM 对应 `omp/zhipu-coding-plan/glm-5.3`。实际可用模型先用 `client.providers.listModels("omp")` 核对。**省略 prompt**；不调用 sendMessage。随后 ref.refresh 检查 provider=omp、status=idle、lastUserMessageAt=null。
- 同项目创建两条、另一项目创建一条；Android 配对后应显示三张卡。保持 Android 连接，再创建另一项目会话，应自动出现第四张卡。重载插件两次，对照 WebSocket 快照检查数量、ID、startedAt/updatedAt 不变。关闭插件后创建第五条，再启用检查初始清单补入，而前四条不变。
- Android 模拟器用 `10.0.2.2` 访问主机 Bridge；仅对测试设备配对，不打印 pairing JSON。安装前备份 APK 和应用数据、核对签名及版本；本轮使用临时 Build 22，完成后恢复模拟器原 Build 20 及数据，并核对备份文件哈希一致。此恢复不作为 Redmi 降级流程。
- 撤销时只 remove 本插件、stop 该临时 `--home` 的 daemon、终止自己启动的 Bridge 和模拟器；不修改默认 daemon 或正式 App。私有备份和配置不得提交。

## #15 真实正常轮次复现补充

沿用上述独立环境和恢复方式；实际模型调用必须取得当次目标及验证目的的授权。通过公开 `ref.timeline.subscribe` 观察活动，用 `ref.send` 在合成测试目录执行最小读取、写入及短暂执行，`ref.waitForFinish` 后核对公开状态与手机快照。分别核对 Codex / GLM；通过 Paseo 原生模型选择器切换同会话，再发送下一轮，核对卡片 ID / startedAt 不变。需要原生模型选择器时，仅对隔离 home 开启本地 Web UI，不改变日常 daemon。

#15 使用临时 Build 23、两条会话与四轮真实调用；总开关、任务静音、重复内容更新和亮度设置的具体证据与限制见阶段记录。模拟器恢复 Build 20 后已逐文件校验；旧 #14 的 Build 22 / 无模型调用记录仍是其当时的事实。

## #16 原生请求与异常结果

公开 pendingPermissions 以 request.id 集合为当前事实；permission_requested / permission_resolved 触发合并刷新，重叠刷新仍读取最新权威状态。只要仍有请求就保持等待：全为 tool 使用工具审批提示，question / plan / mode / other / 未知类别统一保守提示。仅发送安全类别，手机不获得审批或回答能力。

请求清空时仅在实际运行中恢复；已 idle/error 且无 activeTurn 的已知轮次等待 turn_ended，统一发送门禁同时阻止迟到 timeline 伪造运行。failed/canceled 映射既有 interrupted，分别显示失败和取消文案；单次工具错误仍只是活动。新轮次恢复正常跟踪，重复/旧结束不能覆盖新状态。

`paseoAttentionReachesPhone` 在实际插件 → TCP Bridge → 手机 WebSocket 覆盖请求并发、过期/重复事件、刷新竞态、迟到工具与结束；Android 使用实际 Bridge fixture 验证呈现及提醒。受控全序列另经真实模拟器渲染；真实模型问答与取消另行记录。#16 临时 Build 24 已恢复 Build 20。设备、模型调用与目标安装授权不跨票复用，详见最终记录的已验证与未验证边界。
