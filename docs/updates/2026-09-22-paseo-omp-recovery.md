# #17：Paseo–omp 恢复与可信状态补齐

范围为子票 #17，父规格 #13；固定审查基准 `1181482b50fdbb838dfa3a1774d0ea2a7f673a65`，长期分支 `alexx_custom`。#14–#16 已完成，不补办前票。开工回读 #17 为 OPEN / ready-for-agent / 无评论，原生依赖仅 #15 CLOSED。

## 当前实现

- 公开目录更新与权威分页清单共同发现恢复、导入和独立分支，不再依赖 created。身份仍为主机命名空间与 Paseo agent ID。
- 每 15 秒重新读取公开清单，单次清单请求 5 秒超时；SDK 连接使用 1.5–30 秒退避，清单或 Bridge 失败亦退避。不重放断线积压的完成事件。
- 每个快照查询记录期间发生变更的会话，跳过这些会话的旧快照，同时保留其他恢复会话。目录代次切换重置序号；归档墓碑抑制迟到更新，权威恢复可重新接纳身份。
- 生命周期回调同步返回，最多 200 个异步任务、200 条待发摘要、200 个监控会话；原生请求刷新每次最多读两次。源文本不进入手机，仍使用公开 API 和认证 loopback 入口。
- Bridge 仅对启用的 Paseo 接入每 5 秒检查状态；45 秒未收到有效摘要时变为 offline，不写完成时间、不发成功提醒。归档清理和传输序号共用顺序门禁，旧适配进程的摘要不能覆盖较新进程。
- 重复恢复快照不延长完成时间。Android 每次连接的首个有效快照建立声音基线，防止离线期间的完成被重连补播；后续轮次、静音和总开关仍按原规则工作。
- 没有新增共享手机字段/枚举、手机控制动作或模型 Key；不改审批模式、不批准、不回答。#16 等待/失败与全面恢复的组合验收仍属 #18。

## TDD 与受控证据

既有实际插件 → 认证 TCP → 隔离 Bridge → 手机 WebSocket 接缝验证后启动、无 created 的导入/分支、归档、漏事件后的当前事实、同步竞态、旧代次、快速回调、资源压力和手机重连。归档迟到消息测试曾明确复现两张卡；繁忙会话使整批快照丢弃的问题也先超时失败，改为逐会话保护后通过。

TaskCatalog 公开接缝用受控时间验证 45 秒失联、同身份恢复、旧归档、重复完成基线和旧进程消息。Android PhoneSession 先复现重连历史完成音，增加首快照代次后通过。

`protocol/fixtures/paseo-omp-recovery.json` 由真实隔离 Bridge 的 WebSocket 输出捕获；上游是受控 SDK 数据，不是模型实测。

```sh
AGENTPAGER_CAPTURE_OMP_RECOVERY="$PWD/protocol/fixtures/paseo-omp-recovery.json" \
  swift test --package-path macos --filter paseoRecoveryReachesPhone
```

当前自动化：SDK 0.8.0 类型检查通过；Swift 最终 180 Core + 16 Bridge 通过；Android 93 单元测试、Lint、Debug 构建通过（临时 Build 25；实际安装与恢复见下文）。工具链为 Xcode 27 / Swift 6.4 / macOS SDK 27，JDK 17 / Android SDK 36。

Context7 未检索到 Paseo；依据本机锁定的官方 SDK 公共类型及实现核对连接、清单 timeout、生命周期签名。官方网页本次读取未返回并已取消，不将其冒充成功获取。

## 首轮双轴审查修复

Standards 报 2 项、Spec 报 1 项（共同 P1）：丢失的归档在适配重启后不能清理；周期 idle 抢先于正常完成回调，导致真完成消失。两路独立用实际适配器与隔离 TCP 回执复现。

增加真实 Bridge 回归：适配器重启后权威空清单清掉旧卡；暂停完成刷新并先执行周期快照；周期快照先于完成回调发起。后两者均先超时失败。补齐有序完整成员清单（每块最多 20 个 ID，最多 10 块，全部到齐才清理），并区分健康周期同步与恢复基线，保护在途 outcome。保持认证入口 4 KiB 上限，不增加手机协议字段。修复后 6 项 Paseo 定向测试与 SDK 类型检查通过；Windows Core 7/7 通过。

## 最终双轴审查（2026-09-23）

固定基准始终为 `1181482`；实现 `50b475f`，首轮修复 `f5842e3`，主机授权修复 `02f3959`。Standards 复查另发现未知归属持久化卡片可能被其他主机的完整清单删除：入口现强制核对配置 hostID，删除未知归属记录的授权只由 Bridge 本地配置提供，旧配置无 hostID 时保守保留。该测试先失败再通过。

- Standards：最终 **0 项剩余发现**。独立复跑主机授权测试通过。
- Spec：最终 **0 项剩余发现**。独立复跑主机授权与完整恢复链路通过。
- 最终全量 Swift：180 Core + 16 Bridge = **196**；Android **93** 单测、Lint、Debug 构建通过；SDK 类型检查通过；Windows Core **7/7**。源码修复后完整 Swift 已重跑，Android/共享协议未再改动，不重复无关构建。

## 本 Session 隔离实测

用户明确授权本票私有目录、127.0.0.1 的 52072–52075、最多四次 Codex/GLM 合成小任务，以及 medium_phone 的可恢复临时安装。未沿用前票授权。实际版本：Paseo **0.8.0**、omp **18.2.8**、Bridge **0.3.0 / 临时 Build 25**（ad hoc 签名私有 App，独立 Bundle `com.agentpager.bridge.issue17`）、Android **0.3.0-custom / Build 25**（`com.agentgrid.mobile.custom`）、medium_phone Android 16。未替换 `/Applications`，未接触日常 daemon 或 Redmi。

1. 先启动真实 Paseo、创建 Codex/GLM 两条无 prompt 会话并安装插件，再启动真实 Bridge；公开目录补齐两条 idle 卡片。未将 idle 记为成功。
2. 四次实际调用：第一次 Codex 在旧已加载插件上完成但手机只见 idle，**该次不算当前实现通过**；显式 reload 后 GLM 正常完成；重启 Paseo 后原 Codex 正常完成；同目录独立新会话正常完成。后三次手机 WebSocket 都记录 running / 工具活动 / succeeded。directory 插件不会自动加载磁盘新代码，已在开发说明补充 reload 要求。
3. 隔离 Paseo 停止后，未完成事实的卡片过期为 offline，完成卡片不制造新结果。重启后公开清单将未恢复会话标为 closed，Bridge 清理；继续原 Codex 会话后同 ID 自动恢复。这里使用的是公开事实，不把 closed 历史重新展示。
4. 插件停用期间建立同目录新会话、归档原会话；启用后补入新身份并删除漏掉的归档。真实快照核对原 ID 已不存在、新 ID 存在。真正的 Paseo 原生分支操作没有实测；新 ID 分支行为由受控接缝覆盖，真实同目录独立会话验证了不合并。
5. Android 通过真实 Bridge 配对，实测两张同目录卡片、运行工具活动、完成后绿态、App 强制关闭再启动重连、Bridge 重启后恢复及漏归档后的呈现。插件停用后 idle 卡片显示“离线”，再启用恢复 idle；完成卡片的 completedAt 保持原值。截图见下面证据。
6. 对本次创建的 omp 进程执行异常终止时，该轮已完成；因此不把它记作“运行中异常退出”实测。运行中异常退出、不重播历史音、重复快照计时、乱序、快照竞态、资源压力的确定性证据来自受控自动化。没有实际听音/Redmi 硬件验收。
7. 单次 Bridge 资源采样 CPU 1.2%、RSS 26,272 KiB；有界队列与退避由受控压力测试验证。跨夜中断和机器休眠不算连续长期性能验收。

**证据**：[实际手机状态序列](assets/2026-09-23-paseo-omp-recovery/actual-phone-transitions.json)、[同目录两卡及工具活动](assets/2026-09-23-paseo-omp-recovery/two-independent-cards.png)、[补齐与归档后的呈现](assets/2026-09-23-paseo-omp-recovery/recovered-after-missed-archive.png)、[停用后离线](assets/2026-09-23-paseo-omp-recovery/adapter-stopped-offline.png)。状态序列包含早期旧加载进程采样，不单独将这些样本解释为最终实现。只存安全任务字段，不存配对凭据、原请求或完整路径。

## 恢复与验收边界

Android 已恢复原 **Build 20**；APK SHA256 `3f226425ccabad95cb9483f331a560aebb6f003a186d7d4247a9b29b3a432e8f`，两份原数据文件的哈希及文件集合全部一致，见 [恢复结果](assets/2026-09-23-paseo-omp-recovery/restoration.json)。只移除隔离 daemon 的本插件并停止该 daemon、私有 Bridge、观察进程和模拟器。临时配对密钥随私有 Bridge 停止失效。私有备份不提交。

#17 最新验收标准以受控权威快照/连接/时间验证为主，全部实现并通过；实际接线另以以上 Paseo/Android 实测交叉核对，没有用模拟数据冒充实际模型调用。真实运行中杀进程、原生 fork/import 操作、听音、Redmi 亮度/振动/通知、长期性能、Windows 桌面、正式安装、原来源与账号额度的现场全组合尚未验证。原来源、额度模块与协议兼容由现有自动化回归；开发模式不读取真实额度。#16 等待/失败与恢复、正式启用/关闭和上述日常全体验证按最新 #18 整体验收，本票没有扩做。

本阶段无需改 CONTEXT（领域术语未变）、ADR、AGENTS 或稳定平台安装规则；Paseo 特有 reload/恢复说明归入现有开发接入文档。用户原有未提交规格、研究、拆票、CONTEXT 与索引六行全部保留。#13 保持 OPEN；#18 原生依赖为 #16、#17，不自动关闭父规格。

## 票据状态收尾

2026-09-23 09:23（Asia/Shanghai），在最终 Standards / Spec 文档证据复查均无阻止关闭问题后，按用户授权关闭 [#17](https://github.com/XJM034/AgentPager/issues/17)。GitHub 回读 `CLOSED`，closedAt `2026-09-23T01:23:12Z`；父 #13 回读仍 OPEN。#18 最新正文、评论（无）、ready-for-agent 标签与原生依赖已核对，依赖 #16、#17 均 CLOSED。没有推送、发布或实施 #18；不留 #17 收尾给下一 Session。
