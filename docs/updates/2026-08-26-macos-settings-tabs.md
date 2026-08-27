# 2026-08-26 macOS 设置标签交互优化

## 用户可见变化

- “连接 / Hook / 模拟器 / 诊断”四个标签的整块区域均可点击，不再只依赖文字和选中线附近的命中范围。
- 标签栏与原生 macOS 窗口标题之间增加垂直间距，避免“AgentPager Bridge 设置”贴近或压住标签文字。
- 标签栏总高度固定为 64pt；切换不同高度的页面时，与标题栏之间的距离不再跟随页面内容变化。
- 设置页根容器固定靠上；较矮页面因最小窗口高度产生的剩余空间统一留在底部，不再把整个标签栏垂直居中。
- 四个标签及其页面均立即切换，不播放移动、缩放或淡入淡出动画；当前标签继续向辅助功能暴露“已选中”状态。

标签选中状态使用禁用动画的 `Transaction` 更新，同时移除选中线的匹配几何动画和页面切换 Transition，避免 Hook 页因内容更高而出现独有动画。设置页根容器的最小高度明确使用顶部对齐，避免页面固有高度不同导致标签栏位置变化。

## 修改范围

- `macos/Sources/AgentGridBridge/BridgeViews.swift`
- 未修改 Bridge 服务、局域网配对、WebSocket、Hook 安装逻辑、协议、端口或 Android 端。

## 验证

- 工具链：Xcode 27.0、Swift 6.4、macOS SDK 27.0。
- `cd macos && swift test`：通过，86 个测试、0 个失败；同时完成 `AgentGridBridge` 产品编译。
- `scripts/package-macos.sh`：通过，重新生成并恢复运行 `dist/AgentPager Bridge.app`；本机未发现 Apple Development 证书，因此使用临时签名。
- `codesign --verify --deep --strict "dist/AgentPager Bridge.app"`：通过。
- Bridge 二进制 SHA-256 为 `633771a37ca51a7e3afc6cc6b516169119cb1fe4413f92313de9c434b79e583d`。
- `git diff --check`：通过。

## 本机安装

- 使用最新代码重新打包为 `0.3.0 (6)`，避免覆盖已安装 `0.3.0 (5)` 时出现 Build 号降级。
- 旧 Build 5 已完整备份到 `dist/backups/AgentPager Bridge-0.3.0-build5-before-settings-tabs-20260826-174115.app`；备份二进制 SHA-256 为 `a0a2e623361f32670ff702f721ac6e0e36c7d3b3f81b4b050b4beef861f7b12b`。
- `/Applications/AgentPager Bridge.app` 已替换为 Build 6；签名验证通过，安装包与 `dist` 二进制哈希一致。
- 已安装进程从 `/Applications/AgentPager Bridge.app` 运行，端口 49361、49362 均正常监听。启动约 50 秒后的单次采样为 13% CPU、约 476 MiB RSS；该短时采样不等于长期性能验收。
- 采样时 49362 没有手机的已建立连接，因此本轮未验证真实手机连接连续性。

## 仍需现场验收

Swift 单元测试不覆盖真实设置窗口的鼠标命中和标题栏视觉效果。设置标签视觉已由用户现场验收通过；真实手机连接与长期性能仍需后续观察。
