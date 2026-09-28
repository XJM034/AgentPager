# #18：正式配置与整体验收

范围：子票 #18；父规格 #13。长期分支 `alexx_custom`，本 Session 审查固定基准 `2118ffbd54299fea86cba0259aaf555f7c486f18`。
开工回读 #18 OPEN / ready-for-agent / 无评论；原生依赖 #16、#17 CLOSED；父 #13 OPEN。
用户已有规格、研究、拆票、CONTEXT 与 docs/README.md 六行未提交索引保留，不属于本票提交。

## 当前阶段

配置实现、自动化与首轮双轴审查已完成。用户在本 Session 回复“已连接redmi，授权通过”，已按具体方案完成正式 Mac 与 Redmi 升级；真实 Paseo 会话和硬件验收进行中。本文不是完工报告，不构成关闭条件。

- 既有 Bridge 配置页新增 omp/Paseo 启用/恢复、关闭、撤销和脱敏诊断。
- 独立 0600 配置持久化 hostID/token；正式 Bridge 继续使用既有钥匙串手机配对，不使用 #17 开发模式的临时密钥。
- 官方 CLI 只操作 agentpager-omp，变更前保存 0700 目录内的 0600 备份；相同内容备份复用，原配置及第三方插件不重写。
- 检查插件真实 running；源码指纹变化触发显式 reload；指纹只在 running 回读成功后记录。
- 关闭立即停入口并清理 omp 卡片；即使 Paseo 不可用，也先持久化关闭。恢复保留接入身份，权威补齐当前状态。队列旧回调通过入口代次丢弃。
- 应用包内携带插件源码与锁定公开 SDK 的运行依赖，保留依赖许可；不依赖开发仓库长期存在。
- Paseo 全局插件开关会影响其他插件：Bridge 不代改该开关或 omp 权限。用户在 Paseo Settings 开启插件及 omp 是明确前提，不把未满足前提写成启用成功。

## TDD 与证据范围

使用用户指定的实际插件 → 隔离认证入口 → Bridge → 手机 WebSocket 接缝；配置按钮使用同一 Bridge 入口，外部 CLI 响应受控。Android 读取真实 Bridge 输出的配置恢复 fixture。

红灯→绿灯：关闭/恢复入口缺失；跨实例配置缺失；重复操作重复备份；命令返回但未 running 被当成功；同名第三方注册被撤销；Paseo 不可用时关闭未持久化。修复后定向用例通过。

等待恢复组合：等待期间关闭再恢复仍为原等待；离线解决请求再恢复只显示真实运行，不重现等待/虚假能力；权威空目录显示“已连接 · 暂无会话”。上游仍为受控 SDK 数据，不能冒充真实 Paseo 模型或 Redmi。

## 当前安装事实与授权边界

- 已安装日常 Bridge：0.3.0 / Build 20，`com.agentpager.bridge`，Apple Development / Team 2794UM7L67。
- 本机 Paseo CLI/daemon 0.8.0，omp 18.2.8；日常 daemon 的插件清单为空。
- adb 初查无设备；未操作 Redmi。
- 本票本地候选包使用 Build 26。构建、签名检查、安装与运行验收分别记录；当前不把包产出记成安装。
- Xcode 27.0 / Swift 6.4 / macOS SDK 27.0；Android JDK 17 / SDK 36。

## 父规格验收矩阵（本 Session 尚未现场验收）

| 父规格核心场景 | 当前本 Session 证据 | 剩余实际验证 |
| --- | --- | --- |
| 新建未输入自动显示 | 前票已关闭；本票未重复声明实际结果 | 真实 Paseo + Redmi |
| Codex/GLM 运行、活动、完成 | 沿用真实适配实现 | 分别模型调用与手机完成反馈 |
| 同会话继续、模型切换、多会话 | 稳定 ID 的受控恢复用例 | 真实会话和模型切换 |
| 失败、取消、自动续跑 | 前票自动化及既有成果，不冒充本票现场 | 整体验收组合 |
| Bridge 后启动、手机/插件重连 | 配置持久化及实际 Bridge 接缝 | 正式配对与重启 |
| 等待与旧请求解决 | 受控关闭恢复组合通过 | 真实原生问答的断开/恢复 |
| Paseo/omp 异常退出、归档 | 前票恢复能力 | 运行中异常退出、归档现场 |
| 提醒、静音、亮度、卡片 | Android fixture 定向用例 | Redmi 实际听音及亮度 |
| 原来源与 Codex/GLM 额度 | 待最终全套回归 | 正式原来源/额度现场 |
| 隐私、关闭与恢复、撤销 | 本票配置/传输受控用例 | 实际插件安装与撤销、恢复 |

父 #13 保持 OPEN，子票完成不能自动代表父规格通过。长期性能、原生 fork/import 等没有新证据时继续标未验证。

## 当前自动化检查

2026-09-23：Swift 全量串行 180 Core + 19 Bridge = 199 项通过；Android 94 项单元测试、Lint、Debug 构建通过；SDK 类型检查通过。Android 生产代码与手机共享协议字段未变，新增配置恢复 fixture 与呈现验证。`git diff --check`、根 AGENTS/CLAUDE 镜像检查通过。

首次 Build 26 本地 Mac 包已生成，8 个 SDK 运行依赖随包携带，Apple 团队签名及严格签名验证通过；源代码修订后仍需重打最终包，当前不作为最终安装产物。

bootstrap 核对：根/平台规则已覆盖安装、备份、签名及配对边界，无需重写 AGENTS/CLAUDE；新增打包资源入口写入现有 macOS 开发说明，领域术语和协议未变，无新 ADR/CONTEXT 修改。

## 双轴审查与候选包（等待本 Session 现场授权）

实现提交 `31b0399`。按 code-review 两路独立审查固定 `2118ffb...31b0399`：Standards 0硬性问题/1项P3判断性建议；Spec 0确认实现问题，保留现场验收门槛。已将连接诊断改为枚举，UI不再按中文前缀判断状态；同时重复启用相同配置不会重启现有入口。两路增量复核均0剩余问题。

修改后再跑完整Swift：180 Core + 19 Bridge，199项通过。Android94/Lint/Debug及SDK类型检查通过，之后没有Android/JS修改。共享手机协议字段、枚举和各端编解码没有新增变更，因此没有新增Windows实现或兼容分支。

最终待安装候选：Mac 0.3.0/Build26，com.agentpager.bridge，Team2794UM7L67，严格签名通过，二进制SHA256 `71fa5d3c26dc0b340fb9cff047be48a17d86722e534818be13342668ff89e357`；Android0.3.0-custom/Build26，com.agentgrid.mobile.custom/AgentPager Custom，APK SHA256 `27ef7190df6acb049d468dcab98fd1cddb2b041f0547d9682c16759dcfd7ca95`，Debug签名已验证。

日常Bridge仍为原Build20进程；未安装、未重启、未发起模型调用。官方SDK当前只读查询：pluginsEnabled=false、ompEnabled=true、pluginIDs=[]。Redmi仍未连接。

[具体安装、备份、恢复与验证方案](2026-09-23-paseo-omp-installation-plan.md)已准备并提出本Session授权问题。该计划及本地提交不是实际验收。等待用户授权与连接Redmi后继续本Session现场阶段；#18/#13均不关闭、不推送、不发布。


## 本 Session 实际安装与初步回读

授权后备份目录：`~/Library/Application Support/AgentPager/issue18-backups/20260923-100233/`，权限0700；保存旧Mac Build20 App、任务/偏好、Paseo配置、Redmi Build21 APK及四个应用数据文件，敏感内容不提交。旧App签名已验证。

正式Mac已替换并启动0.3.0/Build26；安装后二进制SHA256与上列最终包一致，严格签名通过。Redmi Note7（lavender）已以相同Custom包名/Debug证书升级至0.3.0-custom/Build26；安装成功后、首次启动前，原四个应用数据文件集合和SHA256完全一致。没有卸载或清数据。

Redmi启动后直接恢复原配对，实际屏幕显示既有Codex/ZCode卡片与Codex/GLM额度。正式Bridge WebSocket回读Codex额度1个窗口，GLM状态available、1个额度组。该证据仅证明安装、旧数据保留与现有状态可见，不替代各原来源新任务或真实omp验收。

Paseo日常daemon未重启。当前插件总开关仍关闭、无模型调用，已请用户依方案手动打开全局插件开关，并打开Bridge配置页供界面验收。纯菜单栏App的电脑控制读取曾超时；Redmi布局工具因MIUI框架文件缺失失败，已按Android CLI规范使用截图并实际查看。物理听音/亮度尚待现场确认。


### 正式首次启用发现并修复的 CLI 差异

用户手动打开Paseo插件总开关和Bridge配置页后，从正式UI点击“启用 / 恢复”，出现脱敏连接不可用提示。现场官方CLI证据：`plugin ls agentpager-omp --json --host localhost:6767` 在插件尚未注册时退出1，报 `Plugin is not configured`；全量 `plugin ls --json --host localhost:6767` 返回空数组。此前受控响应遗漏此差异。

新增 `paseoFirstInstallUsesPluginCatalog`：修复前捕获unavailable红灯，改为全量清单后筛选自身ID后转绿，保留路径冲突保护。全量Swift复验200项（180 Core + 20 Bridge）通过，两路增量审查各0新增问题。Android/SDK源码未变。

已将当前Build26 App另存私有备份，再安装修复后的同版本/同签名App，二进制SHA256 `2469064cb38dc2fa9a878d01c8e2177422a279bd49392d09ef4604b6bae4050d`，严格签名通过。正式Bridge重启后配对端点完整内容哈希与重启前一致。当前已创建1个真实Paseo空闲Codex测试会话用于后启动补齐，尚未发送提示词或模型调用。


## 真实 Paseo / Redmi 进展与 0.9.1 升级

本节为最新事实；前文“待授权/未安装/仅0.8.0”等属于开工时记录，不代表当前状态。

- 用户手动开启插件总开关后，正式App资源内插件成功安装。初次配置后曾停在连接不可用；增加两条固定无数据启动日志并重启Bridge、显式reload后恢复，初次恢复原因尚未完全归因，后续关闭/恢复仍须复验。
- Paseo 0.8.0真实Codex `openai-codex/gpt-5.5` 与国内Coding Plan `zhipu-coding-plan/glm-5.3`：新建不发prompt自动显示；两会话并行运行，手机实际显示“执行工具”；WebSocket记录思考/读取/执行/完成。各自正常完成，Codex同会话继续完成。累计3轮模型调用。
- 原生Full Access保持原值，未变更模式。Redmi截图已实际查看；只存私有临时路径，因含用户其他任务不提交截图。提示音初测用户未听清，后续听音和物理亮度仍未确认；不得记通过。手机原任务/空闲亮度均100%，测试设任务45%，随后读取55%；收尾需与用户核实并恢复偏好。
- 用户自行重启Paseo，daemon由0.8.0更新为0.9.1（非Agent重启日常daemon）。官方plugin ls回读failed，原因是manifest精确要求0.8.0。此为版本门槛拒绝加载，不能用自动重连掩盖。
- 在独立临时目录安装官方0.9.1 SDK，现有插件严格类型检查通过；运行依赖仍锁0.8.0。官方assertPluginCompatibility回归测试先红后绿，manifest仅允许0.8.0或0.9.1，拒绝未知0.10.0。配置诊断新增固定版本不兼容提示，不展示原始上游错误。Swift补测含CLI非零退出分支。
- 已备份并实际安装0.9.1适配Build26，Bundle/Team保持相同、严格签名通过，安装二进制SHA256 `8268f6d19f4e196acff19a9201c4775954601861b19d56ff1751a01468d75107`。显式reload后插件running，正式配对哈希不变，GLM额度available。后续诊断分支源代码修订尚需最终重打，不能混同安装版本。
- 0.9.1第4轮真实Codex同会话请求原生Blue/Green问答；用户自行选Green。完整手机通道日志：02:36:49Z running → 02:37:05Z waitingAnswer → 02:37:20Z running → 02:37:25Z succeeded；能力数组为空。最初读单次快照时误以为未更新，完整记录已纠正。该轮证明问答状态同步，不证明等待期间断开恢复。
- 0.9.1重启后GLM测试会话公开状态closed，适配层移除其卡片，不把已关闭会话永久呈现为运行。

当前仍缺：等待断开/恢复与旧请求已解决、正式配置关闭/恢复/撤销完整实测、模型切换、隔离daemon与运行中omp异常退出、手机重连和硬件听音/静音/亮度确认、全原来源新任务回归及清理恢复。#18与#13保持OPEN。


最终诊断分支修订后Swift全量180 Core + 21 Bridge测试通过（版本错误测试另含2个参数化场景）；SDK0.8.0与独立0.9.1类型检查、2项manifest兼容性检查通过。双轴增量复核均无剩余确认问题；Spec提出的CLI非零退出诊断分支已补红绿用例并复核。

同身份Build26再次备份、安装并严格签名核验，当前正式二进制SHA256 `9de0297f0fc790243c52ffb0f2b9e5605f88f778186a28a65edec94f5a927a79`。这次仅Swift诊断分支变化，插件源码未再变化；未重启日常Paseo daemon。


## 用户追加来源标签：Build27（当前安装）

用户纠正范围后实现：仅 Paseo 原生 Codex/GPT 卡片显示 `Codex · Terminal · Paseo`；OMP保持 `omp · Paseo`，包括选择GPT模型时。新增向后兼容 `isPaseoSession`，三个平台模型及协议文档已同步；仅内存来源关联，不写任务持久化、不改变时间/生命周期/控制能力。通过公开SDK的原生provider sessionId关联，不读私有库或推测来源。

TDD：缺字段编译红灯后实现；实际JS适配器→隔离Bridge→手机WS覆盖原生关联、普通Codex/子会话排除、归档撤销、OMP保持。真实WS输出录为协议fixture，由Android与Windows解析。双轴审查分别发现native容量溢出阻断OMP、旧格式host可绕过长期字典容量限制，均先复现红灯再修复；复审Standards 0、Spec 0。边界明确为前200原生身份、最多200宿主；正式入口绑定唯一配置宿主。

验证：Swift最终182 Core +22 Bridge通过；一次全量运行遇到既有GLM接缝临时端口连接竞态（-1004），重跑全套通过，未隐藏该次失败。Android95单元测试、Lint和Build27 Debug构建通过；SDK0.8.0/独立0.9.1类型检查通过；manifest两项测试通过；临时.NET8.0.425运行Windows Core兼容8/8通过，不代表Windows桌面运行。

实际安装：按本Session已授权方案，先备份当前Mac Build26、Redmi Build26 APK及4个当前数据文件到私有备份子目录 `before-origin-build27`。随后安装Mac 0.3.0/Build27、Redmi 0.3.0-custom/Build27（Custom包名和原证书不变）。Mac严格签名通过，Team2794UM7L67；主二进制SHA256 `cfedd77a0bc7103a4cfd04bf92f8d3826d76de08b574ac68143e7d89d9a7ed04`。Android APK SHA256 `797180a8abdf1bccf1e250c2715adb928ca79f0a2a6a903734f517aa6f2fbcc4`；安装后首次启动前4个数据文件集合/哈希一致，启动后原配对自动恢复，Bridge `/pairing`完整内容哈希与先前相同。目录插件对日常获准目标显式reload，再plugin ls回读running；没有重启日常Paseo。

真实验证：新建Paseo原生codex/gpt-5.5合成会话，读取测试文件、sleep15、回复NATIVE-DONE，真实完成且pending=0；累计第5轮模型调用。Redmi运行中截图已实际查看，同屏普通Codex为 `Codex / Terminal`，该测试为 `Codex / Terminal · Paseo`，OMP为 `omp / Paseo`，文案无遮挡。WS记录原生running/executing→thinking→succeeded，能力为空；手机同时可见Codex/GLM额度。截图含用户其他会话，仅保存在私有临时路径。

本节仅完成新增来源显示与这次实际升级。听音问题已询问用户、尚未收到现场确认；既有#18剩余等待恢复、正式配置关闭/撤销/恢复、隔离进程异常、原来源组合、物理亮度等仍按前节记录继续，不能以该UI修复替代整体验收。#18与父#13均未关闭。未推送或发布。

## 2026-09-28 非活跃会话规则修订

用户进一步明确“没有活跃状态就不显示”，已实施过滤、完成反馈90秒到期、OMP缓存清理及Paseo0.9.2兼容。详细测试、两轴审查、Build28实际安装与恢复方案见[本次修复记录](2026-09-28-inactive-session-visibility.md)。9月28日经当前授权，Mac与Redmi已升级Build28，原数据和配对保留；Paseo0.9.2自身插件reload后running。两轮真实OMP Codex/GLM完成，Redmi确认离线/空闲隐藏、完成卡到期退出且不影响其它Codex卡片。上文Build27为历史安装事实；声音、等待恢复等完整矩阵仍有缺口，#18与父#13均OPEN。
