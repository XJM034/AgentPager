# 项目文档

本目录保存个人定制开发所需的稳定说明和日期化更新记录；上游产品介绍仍以根目录 `README.md` 为准。

## 入口

- [Paseo–omp 开发接入（#14）](paseo-omp-development.md)：官方插件、隔离启用与撤销、安全边界；[本票验证记录](updates/2026-09-22-paseo-omp-discovery.md)。源码与自动化交付不等于现场安装验收。

- [2026-09-20 Codex 额度同步修复与 Spark 移除](updates/2026-09-20-codex-quota-spark-removal.md)：实时额度来源、刷新频率、两端验证及安装状态。

- [2026-09-15 Mac 轻量化与内存验证](updates/2026-09-15-macos-lightweight-memory.md)：保留剩余额度与核心同步，静态图标、额度缓存和分文件临时内存回收。

- [ZCode / GLM 现行功能与验收边界](zcode-glm-integration.md)：已支持的会话与手机审批、启用步骤、独立 Key 额度、后续免重复 Key 目标及开发 Agent 阅读入口；处理这些功能时先读。
- [ZCode / GLM 本期范围与 Issue 收尾](updates/2026-08-31-zcode-glm-scope-closeout.md)：用户确认的独立 Key 交付范围、#1 / #10 关闭依据和 #12 后续优化边界；当任务涉及完成状态时读取。
- [Android Agent 开发环境](android-development.md)：工具、服务、预览、模拟器、真机、构建和调试流程。
- [macOS AgentPager Bridge 开发环境](macos-development.md)：Xcode/Swift、测试、打包、签名、安装、回滚和运行验收。
- [长期定制与 Entire Review 流程](custom-development-workflow.md)：长期分支、文档同步收尾清单、日常修改基准、上游同步、Session tracking 和人工 Review 门槛。
- [Entire Review 安全流程](entire-review-safety.md)：纯读取入口、命令拦截的实际边界、checkpoint 身份核验与隔离验证。
- [2026-08-25 Android Agent 开发环境更新](updates/2026-08-25-android-agent-development.md)：本轮配置和验证结果。
- [2026-08-25 macOS Agent 开发环境更新](updates/2026-08-25-macos-development-environment.md)：Xcode 27 beta、Swift 6.4、macOS 27 SDK 与 iOS 27 Simulator 的当前证据。
- [2026-08-25 AgentPager Bridge CPU 修复](updates/2026-08-25-agentpager-bridge-cpu-fix.md)：日志轮询性能修复、测试、安装与回滚记录。
- `updates/`：按日期记录单次定制或环境变更，已完成记录不作为活动待办。

## 维护规则

- 稳定、反复使用的流程更新到对应主题文档。
- 大型功能或跨 Session/Ticket 阶段收尾，以及提交后的用户确认/验收反馈，按 [文档同步收尾清单](custom-development-workflow.md)主动更新现行说明和日期化证据。
- 单次变更、版本、机器状态和验收证据写入日期化更新。
- ZCode/GLM 行为变化同步到现行功能说明；历史 PRD、调研和单次验收记录保留当时范围，不替代当前代码与明确批准的需求。
- 代码与文档冲突时先核实代码和运行结果，再修正文档。
- 需要跨任务连续工作时使用 `handoff/`，不要把临时交接内容长期堆在这里。
