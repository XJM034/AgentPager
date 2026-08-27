# 2026-08-25 macOS Agent 开发环境更新

## 结果

本机已经具备 AgentPager macOS Bridge 的默认开发环境：默认命令行工具已切换到 Xcode 27 beta，Swift 6.4 与 macOS 27.0 SDK 可用，首次启动配置完成，iOS 27 Simulator Runtime 与模拟设备已安装。当前仓库使用默认 Swift 6.4 完成了全部 Swift 测试。

本轮只更新开发指引和验证工具链，没有重新打包或替换 `/Applications/AgentPager Bridge.app`，也没有推送、发布或提交 Apple 公证。

## 当前本机证据

### Xcode 与默认命令行工具

- 用户确认安装版本：Xcode 27 beta 6。
- 安装位置：`/Applications/Xcode-beta.app`。
- `xcode-select -p`：`/Applications/Xcode-beta.app/Contents/Developer`。
- `xcodebuild -version`：Xcode 27.0，Build `27A5252f`。
- `xcodebuild -checkFirstLaunchStatus`：退出状态 0，首次启动配置已完成。

### Swift 与 SDK

- 默认 `swift --version`：Apple Swift 6.4，`swiftlang-6.4.0.33.1`。
- 默认目标：`arm64-apple-macosx27.0.0`。
- macOS SDK 路径：`/Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk`。
- `xcrun --sdk macosx --show-sdk-version`：`27.0`。
- 先前安装的 Swift.org 用户级 Swift 6.2.4 工具链仍保留，但不再是普通 `swift` 命令的默认来源；需要复现兼容性差异时才显式调用。

### Simulator

- `simctl` 已识别 iOS 27.0 Runtime：`com.apple.CoreSimulator.SimRuntime.iOS-27-0`，Build `24A5423a`。
- 已有可用的 iPhone 17、iPhone Air、iPhone 17e、iPad Pro、iPad Air、iPad mini 和 iPad 模拟设备，当前均为关机状态。
- 当前 AgentPager 仓库没有 iOS App Target；这些设备不属于 macOS Bridge 或 Android App 的验收面。

## 项目兼容性验证

- `macos/Package.swift` 声明 Swift tools 6.2、最低 macOS 14。
- 在当前默认 Xcode/Swift 6.4 下运行 `cd macos && swift test`：构建成功，86/86 测试通过，0 失败。
- 测试运行目标报告为 `arm64e-apple-macos14.0`，说明 Package 仍按最低 macOS 14 目标构建，而不是被本机 macOS 27 SDK 强制提高部署下限。
- 本轮没有用 Swift 6.4 重新运行 `scripts/package-macos.sh` 或 `scripts/package-dmg.sh`；当前安装的 AgentPager Bridge build 5 仍是此前已经验证并安装的修复版。

## 文档与范围变化

- 根 `AGENTS.md` 与 `CLAUDE.md` 的项目范围从“默认只维护 Android”调整为“Android 与 macOS 都是常规维护范围”。
- 新增 `macos/AGENTS.md` 与 `macos/CLAUDE.md`，单独承载 Swift、SwiftUI、Hook、签名、打包、安装和运行验收规则。
- 新增 `docs/macos-development.md` 作为稳定 Mac 开发入口，并保留 Android 独立指引。
- Windows、协议和站点仍不作为默认单端修改范围；协议变化必须进行跨平台核对。

## 当前缺口

- Xcode 27 beta 与 Swift 6.4 仍可能随 beta 更新发生变化，每次开发都应重新运行版本核实命令。
- 普通分支没有自动 macOS CI；本轮没有在新工具链下复验通用二进制、DMG、Developer ID 签名或 Apple 公证。
- Swift 单元测试不能证明菜单栏 UI、真实 Hook 信任、局域网手机连接和长期性能。
