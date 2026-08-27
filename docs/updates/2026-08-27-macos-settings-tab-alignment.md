# 2026-08-27 macOS 设置标签顶部对齐优化

## 用户可见变化

- “连接 / Hook / 模拟器 / 诊断”标签栏由 64pt 收紧为 52pt，减少标题栏下方的空悬感。
- 移除标签文字额外的 10pt 顶部偏移，使文字在标签栏内垂直居中，并让四个标签更贴近窗口顶部边界。
- 整块标签区域仍可点击，底部选中线、无动画切换和辅助功能选中状态保持不变。

## 修改范围

- `macos/Sources/AgentGridBridge/BridgeViews.swift`
- 未修改 Bridge 服务、Hook、局域网连接、协议、端口、安装包或 Android 端。

## 验证

- `cd macos && swift test`：通过，88 个测试、0 个失败，并完成 `AgentGridBridge` 产品编译。
- `AGENTPAGER_VERSION_NAME=0.3.0 AGENTPAGER_VERSION_CODE=9 scripts/package-macos.sh`：通过，生成 arm64 Release App；本机没有 Apple Development 证书，因此使用临时签名。
- `codesign --verify --deep --strict`：`dist` 与 `/Applications` 中的 App 均通过。
- 安装后的 Bridge 二进制与 `dist` 哈希一致，SHA-256 为 `da408b546005443c498bd9162cbb4fb4bdbdf462beae4fc14afd6c56c194ad2a`。
- `/Applications/AgentPager Bridge.app` 已更新为 `0.3.0 (9)`；启动路径正确，端口 49361、49362 均正常监听。
- 启动约两分钟后的单次采样为 0.3% CPU、约 110 MiB RSS；49362 当时只有监听，没有已建立的手机连接。
- `git diff --check`：通过。

## 本机备份与现场边界

- 安装前的 `0.3.0 (8)` 已备份到 `dist/backups/AgentPager Bridge-0.3.0-build8-before-tab-alignment-20260827-1507.app`。
- 原 `/Applications` App 已移动到 `dist/backups/AgentPager Bridge-0.3.0-build8-installed-original-20260827-1507.app`，可直接用于回滚。
- 顶部间距已由用户通过 Xcode 实际窗口确认；真实 Hook 信任、手机重连和长期性能仍未在本轮验证。
