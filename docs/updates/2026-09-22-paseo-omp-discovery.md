# #14：Paseo 新建 omp 会话发现

日期：2026-09-22。范围：[开发票 #14](https://github.com/XJM034/AgentPager/issues/14)，父规格 [#13](https://github.com/XJM034/AgentPager/issues/13)。现行入口：[开发接入说明](../paseo-omp-development.md)。

## 已实现

- Paseo 0.8.0 官方 `agent.created` + 公开 SDK 目录订阅、分页初始清单；创建事件读取公开 ref.refresh 权威快照。
- 仅 Paseo omp：排除其他 provider、归档/closed 历史；创建回调排除带 parentAgentId 的子会话事件，SDK 目录快照不提供该字段。模型不参与来源或身份。
- 独立认证的 loopback 入口、大小/连接/超时/安全摘要队列上限；Bridge 实际启动接线与目录持久化。
- 主机命名空间 + agent ID 的 SHA-256 身份，同目录并发、多项目、重复事件、跨主机不冲突。
- 有限标题类别、末级项目名；idle 保持非完成语义、无虚假审批能力。Android 使用现有卡片、排序、焦点与声音基线，新增 omp / Paseo 来源标记。
- Swift/Kotlin/C# 来源编解码和混合未知来源共享 fixture；Windows 不增加采集。
- 独立开发启动模式和只准备配置的脚本，不自动安装、覆盖运行 App、修改 Paseo 配置或调用模型。

## 验收与证据

| #14 验收项 | 结果 |
| --- | --- |
| 尚未输入即可自动显示，空闲可见 | 真实 Bridge WebSocket + Android 投影测试通过；真实 Paseo/Redmi 待验收 |
| 真实 idle/starting、无伪造完成、首次提醒基线 | 自动化通过 |
| 只接 Paseo omp | 受控官方边界测试通过；独立终端无采集入口 |
| 安全标题、项目、明确来源且模型不影响身份 | 两端测试及实际适配器链路通过；不读取模型 Key |
| 同目录/多项目/跨主机/重复创建 | 实际适配器 → 本地 TCP → Bridge → WebSocket 测试通过 |
| 初始分页清单 + 创建，忽略归档和 closed 历史 | 测试通过；全面断线恢复留后续票 |
| 原有来源、额度、配对 | 完整回归通过；未改额度来源与配对协议 |
| 本地认证与敏感数据不进入手机/持久化/诊断 | 错误 token 拒绝及合成敏感标记检查通过；监听明确绑定 loopback |
| 三端协议与未知来源兼容 | Swift/Android 测试通过；C# 源码与测试已补，当前无 .NET SDK，未执行 |
| 开发启用、撤销、演示 | 已提供可重复步骤；未安装到真实 Paseo/Android 或替换 Bridge |

TDD 记录：先添加隔离 WebSocket 验收并看到缺少接入接口的编译失败；实现后通过。再接实际 JS 适配器，缺少模块时失败，实现后通过。补 closed 历史用例后发现错误导入，过滤后通过。补目录 initializing → 创建完成 idle 的测试后发现启动状态未收敛，修正后通过。Android 来源测试先因 `omp` 回退未知失败，补来源与标签后通过。测试输入是受控 SDK/生命周期数据，不能宣称真实 Paseo 已验收。

检查：

- `swift test --package-path macos`：177 项 Core + 13 项 Bridge，共 190 项通过。提交前复跑曾遇到未修改的 accountUsageStdioHandshake 2 秒超时；额度组 5 项和该用例单独复测通过，最终全量复跑通过。本票没有修改额度实现或放宽该测试。
- `JAVA_HOME=...openjdk@17... ./gradlew testDebugUnitTest lintDebug assembleDebug`：88 项 Android 单元测试通过，Lint 与 Debug 构建通过。
- `npm ci --prefix integrations/paseo-omp --ignore-scripts` / `npm run check --prefix integrations/paseo-omp`：固定 0.8.0 官方 SDK 类型检查通过。
- 工具链：Xcode 27.0 (27A5252f)、Swift 6.4、macOS SDK 27.0；Android JDK 17.0.19、Gradle 8.13。
- 实际隔离开发可执行程序已启动并接收生产适配器的受控输入，随后只终止该隔离进程。启动瞬时 RSS 约 87 MiB、CPU 28.2%，仅启动观察，不是稳态或长期性能验收。
- 设备检查：本轮 adb 无连接设备。构建保持 `.custom` 包名；没有安装或版本覆盖。
- 基线提交 `8440cd0c41ce06bec8a2bcaa80b91a6192c0b1cc`，分支保持 `alexx_custom`。本轮不推送、不发布、不关闭父 Issue。

## 审查与文档

按 code-review 分别审查 Standards 与 Spec。首轮 Standards 提出订阅/并发测试证据和子会话过滤说明两项，已补 SDK upsert、Promise.all 创建用例并缩窄说明；Spec 未发现确认的需求偏差。最终复核：Standards 两项均关闭，无剩余发现；Spec 0 项发现。按 claude-agents-bootstrap 核对入口，现有根规则已覆盖协议、安装与验证边界，只增加文档索引及 macOS 开发入口，不重写根规则。保留用户已有的 CONTEXT、规格、研究、拆票文档与索引改动，只暂存本票新增索引段落。

## 后续与未验证

真实 Paseo 插件安装/加载、Codex/GLM 各创建真实会话、Redmi 卡片与提醒、签名升级以及长期资源占用未验收。未做模型调用，未替换 `/Applications`，未改真实 Paseo daemon 或审批模式。本票只做发现，连续轮次状态、归档后清理、异常和跨连接恢复都不在此阶段。

#15 已具备代码接线、稳定身份、来源和测试接缝基础；GitHub 上 #14 尚未关闭，因此按现行票据规则，#15 尚未进入正式可开发前沿。须先完成本票验收/获准豁免并按授权处理 #14 状态；本轮不继续实施 #15–#18。
