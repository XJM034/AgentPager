# ZCode 支持说明与开发阅读入口补齐

日期：2026-09-14。按用户指定的 `claude-agents-bootstrap` 做局部核对与补充。

## 核对结果

分支为 `alexx_custom`，HEAD 为 `99a7a46`。开始时已有四个未提交文档：现行 ZCode/GLM 说明、Issue #10/#12 历史记录的补充，以及 2026-08-31 范围收尾记录。这些内容已写入本地，但尚未随代码提交。现有根与 Android/macOS 的 AGENTS/CLAUDE 入口已指向功能说明，协议文档也已包含 ZCode 与多提供方额度。

代码核对覆盖 `ZCodeReducer.swift` 的 Stop → idle、`BridgeModel.swift` / `BridgeViews.swift` 的 ZCode Hook 安装与可选 GLM 设置、`GLMQuotaProvider.swift` 的独立 Key 查询，以及 Android `UsagePresentation.kt` 的 CODEX / GLM 分区与状态表达。

2026-09-14 通过 GitHub CLI 重新读取：#1、#10 均 CLOSED；开放列表仅 #12，标签为 `enhancement`。8 月 31 日用户批准的本期独立 Key 方案继续作为现行范围；未重新调查上游免重复 Key 接口能力。

## 本次补齐

- 根 `AGENTS.md` / `CLAUDE.md` 增加一句已支持 ZCode 的概述，详情仍路由至现有功能文档。
- 镜像检查发现 `android/CLAUDE.md` 遗漏了已有于 `android/AGENTS.md` 的 ZCode/GLM 阅读入口，本次补齐。
- README 中英文入口补充个人定制分支能力，标明下方支持表和发布说明属于上游基线。
- 文档索引增加范围收尾入口；Android 开发文档补充 ZCode 阅读路径。
- 现行说明集中给出配对、安装 Hook、新建 Session、可选 Key 连接与手机控制范围；提示以当前 Bridge 界面核实是否启用。
- 增加开发 Agent 接手时的显式阅读路径。没有把 ZCode 产品支持、文档存在、项目指令自动加载和 Skill 发现当成同一项验收。

## 验证与范围

检查 Markdown 本地链接、根和平台 AGENTS/CLAUDE 镜像、差异格式及改动范围。保留开场已有四个文档修改，产品源码、协议、Hook 配置和 Skill 安装均无新增修改。

本次不运行 App 构建或设备测试。Build 18 / Redmi Build 14 的结果仍属于 2026-08-31 历史验收；未重新确认今日安装版本、手机连接或 ZCode 自动加载指令。最新版官网同时间对照、真实故障隔离及长期运行的既有缺口继续保留。

本次文档补齐后仍待 Git 提交及推送。
