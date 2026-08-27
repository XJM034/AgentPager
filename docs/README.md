# 项目文档

本目录保存个人定制开发所需的稳定说明和日期化更新记录；上游产品介绍仍以根目录 `README.md` 为准。

## 入口

- [Android Agent 开发环境](android-development.md)：工具、服务、预览、模拟器、真机、构建和调试流程。
- [macOS AgentPager Bridge 开发环境](macos-development.md)：Xcode/Swift、测试、打包、签名、安装、回滚和运行验收。
- [2026-08-25 Android Agent 开发环境更新](updates/2026-08-25-android-agent-development.md)：本轮配置和验证结果。
- [2026-08-25 macOS Agent 开发环境更新](updates/2026-08-25-macos-development-environment.md)：Xcode 27 beta、Swift 6.4、macOS 27 SDK 与 iOS 27 Simulator 的当前证据。
- [2026-08-25 AgentPager Bridge CPU 修复](updates/2026-08-25-agentpager-bridge-cpu-fix.md)：日志轮询性能修复、测试、安装与回滚记录。
- `updates/`：按日期记录单次定制或环境变更，已完成记录不作为活动待办。

## 维护规则

- 稳定、反复使用的流程更新到对应主题文档。
- 单次变更、版本、机器状态和验收证据写入日期化更新。
- 代码与文档冲突时先核实代码和运行结果，再修正文档。
- 需要跨任务连续工作时使用 `handoff/`，不要把临时交接内容长期堆在这里。
