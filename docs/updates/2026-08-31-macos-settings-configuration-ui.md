# macOS 设置页：Agent 配置与 GLM 层级调整

## 改动范围

- 设置导航由「连接 / Hook / GLM / 模拟器 / 诊断」调整为「连接 / 配置 / 模拟器 / 诊断」。
- 页标题改为「Agent 配置」，说明改为按 Agent 管理会话监控、手机审批与可选额度连接。
- 保留 Codex、Claude Code、ZCode 分组；GLM 额度连接移入 ZCode 卡片，默认收起并显示连接状态，展开后保留全部原有操作与安全说明。
- 明确区分 ZCode 的「会话监控与手机审批」和「GLM 额度连接（可选）」；审批与备份说明留在会话配置区域。
- 代码只修改 `macos/Sources/AgentGridBridge/BridgeViews.swift`。未改动 BridgeModel、Hook、额度查询、钥匙串、协议、Android 或 Windows。
- 首次 UI 实现与评审阶段保留既有文档改动，未提交、推送、安装或写入真实配置；后续授权安装见下文。

## 自动化验证

- 目标：本机 arm64 macOS；Xcode 27.0（27A5252f）、Apple Swift 6.4、macOS SDK 27.0。
- 最终源码运行 `cd macos && swift test`：Core 163 项、Bridge 8 项，合计 171 项通过，零失败。
- `git diff --check` 通过；旧 GLM 顶层标签和「Agent 生命周期 Hook」页标题已移除。
- 原有 GLM 保存/验证、刷新、删除入口及禁用条件未改；既有自动化继续覆盖协调器、状态呈现、合成 Hook 与 WebSocket 接缝。

## Product Design 视觉验证

本轮为现有原生 SwiftUI 页面调整，复用 PixelTheme、像素字体、PixelPanel 与按钮样式；不新建网页原型。
以下截图来自原生 NSHostingView 离屏窗口，不是已安装 App 的现场截图。
渲染使用临时任务存储和空 GLM 协调器，不调用 `model.start()`，不启动 Bridge 服务，不访问真实 Key。

本地证据保存在 Git 忽略目录 `dist/qa-settings-2026-08-31/`：

- 视觉基线：`baseline-top.png`、`baseline-bottom.png`，由修改前的界面源码渲染，无真实用户配置。
- 最终页面：`final-configuration-top.png`、`final-configuration-bottom.png`。
- 展开 GLM：`final-configuration-expanded-bottom.png`。
- 导航往返：`final-configuration-diagnostics.png`、`final-configuration-returned.png`。
- 最小窗口：`final-minimum-configuration-*.png`。
- 临时渲染入口：`NativeSnapshot.swift`；最终测试输出：`swift-test-final.log`。

对比尺寸：默认窗口 680×520 pt（1360×1040 px，2 倍密度），最小窗口 650×480 pt（1300×960 px）。
对比使用同尺寸、同深色主题、同未配置状态；基线与最终页面同时查看，另检查 ZCode 与 GLM 底部区域。
用户原截图含配对内容，未复制到证据目录；它只用于确认现有导航问题与视觉风格。

- 字体与文案：保留原像素字体与字号体系；页面标题、分组、小节层级清楚，换行无横向溢出。
- 间距与布局：保留卡片边距和按钮布局；导航保持固定，配置内容只有一个滚动容器，GLM 展开后底部按钮与说明可达。
- 颜色：沿用原深色主题和状态色，不新增配色体系。
- 图像与资产：配置页无需新增图片；既有图标与字体复用，无占位图或配对信息泄露。
- 内容：GLM 的原有状态、时间、脱敏错误、输入框、三个操作与安全边界说明全部保留。

交互验证直接向隔离窗口派发鼠标事件：从默认「连接」进入「配置」，滚动至 ZCode，点击展开 GLM，再切至「诊断」并返回。
两种窗口尺寸均能到达 GLM 操作区域；默认尺寸往返前后的展开页截图哈希一致，展开状态保留。
初次 ImageRenderer 不支持滚动区完整截图，已改用 NSHostingView 原生渲染；未因此修改生产界面。
视觉对比未发现本轮新增的 P0/P1/P2 问题，无需视觉修复迭代。

final result: passed

## 首次 UI 验证时的限制

未替换 `/Applications/AgentPager Bridge.app`；未进行已安装 App 的完整现场交互、VoiceOver、真实 Hook、真实额度请求或 Redmi 验收。
截图中的「未安装 / 未启用」来自隔离模型，不代表用户当前安装状态；171 项测试不替代上述现场验证。

## 后续授权安装与收尾（2026-08-31）

用户随后明确要求更新 Mac，并暂存、提交、推送最新修改。安装目标为
`/Applications/AgentPager Bridge.app`，由 `0.3.0 / Build 13` 更新为 `0.3.0 / Build 14`。

- 继续使用 arm64、Bundle ID `com.agentpager.bridge` 和临时签名（runtime 选项）；未配置正式分发签名或公证。
- 安装前使用 `ditto` 备份完整旧 App，并核对全部 10 个文件的 SHA-256 与严格签名验证。
  备份位于 `~/Library/Application Support/AgentPager/Backups/2026-08-31-104402-0.3.0-build13/AgentPager Bridge.app`。
- 正常退出旧进程后替换并重新启动；新 App 的全部文件与打包产物一致，严格签名验证通过。
  主程序 SHA-256：`deb446b7cdb4ef12bf9022005b1e24f1aead973dad105d1ac5c0dd3177d18e1a`。
- 本轮重新运行 Swift 测试：Core 163 项、Bridge 8 项，合计 171 项通过；release 打包通过。
- 已安装 App 的 `49361`、`49362` 均由新进程监听；使用已安装的 `AgentPagerHooks` 运行
  `scripts/e2e-local.mjs`，状态同步、反向审批、结束收敛与关闭帧存活均通过。
- 通过 macOS 原生菜单打开已安装 App 的设置窗口，并进入「配置」；辅助功能树确认
  「Agent 配置」「ZCode」「会话监控与手机审批」「GLM 额度连接（可选）」均可读。
- Codex、Claude Code、ZCode 三处既有 Hook 配置的存在性和文件 SHA-256 在安装前后保持一致；未点击安装、卸载、保存或删除 Key。
- 安装证据保存在 Git 忽略目录 `dist/qa-settings-2026-08-31/install-build14/`；本地 App、备份、Entire 恢复资料和配置指纹不纳入提交。

本轮没有进行 Redmi 真机、VoiceOver、真实 ZCode 新会话审批或真实 GLM 数值对照验收。
应用启动沿用既有额度刷新逻辑；服务端口和合成测试通过不能替代上述验证。
