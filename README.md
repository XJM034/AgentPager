<p align="center">
  <img src="assets/brand/agentpager-icon.svg" width="160" alt="AgentPager 图标">
</p>

<h1 align="center">AgentPager</h1>

<p align="center"><strong>让闲置 Android 手机，成为 AI Agent 的专属状态终端。</strong></p>

<p align="center">
  不必一直盯着 Mac，也不必再买一块开发板。<br>
  Codex 在做什么、是否完成、何时需要你批准，抬眼就能看到。
</p>

AgentPager 将 Codex Desktop 与 Codex CLI 的运行状态实时同步到旧 Android 手机。把手机横放在桌面上，它就会变成一个常亮、安静，又能在关键时刻提醒你的 Agent 控制台。

## 我为什么构建 AgentPager

我在社交媒体上看到有人用开发板做任务状态栏，于是也去研究了一下。查了一圈才发现，要满足我对屏幕显示、联网、声音、振动和触控操作的需求，还得搭配不同的硬件。

突然我意识到：这不跟手机差不多吗？这些能力它本来就有，屏幕更好、系统更完整，也不需要再买新的设备。

所以有了 AgentPager——让闲置手机重新上岗，成为一块真正好用的 AI Agent 状态终端。

## 为什么用 AgentPager

- **离开 Mac 也不会错过进度**：开始、思考、执行、完成、中断、等待批准、等待回答和离线状态一目了然。
- **多个任务也能快速找到重点**：需要你处理的任务自动置顶并展开，其他任务降低亮度，减少干扰。
- **重要时刻主动提醒**：像素动画、8-bit 音效和振动让完成、中断与等待操作不再悄无声息。
- **手机上直接批准或拒绝**：Codex 发起权限请求时，无需切回电脑即可处理。
- **子代理进度同屏可见**：父任务会展示正在工作的子代理、耗时、最新步骤与 Token 用量。
- **额度还剩多少随时可查**：集中查看 Codex 5 小时与周用量窗口，不必等到触顶才发现。
- **闲置旧手机重新派上用场**：原生横屏界面不依赖浏览器，摆在桌面上就是一块专注的 Agent 信息屏。

**最重要的是：它真的很好看(✧∀✧)！！！**

## 快速开始

### 准备

- 一台运行 macOS 14 或更高版本的 Mac
- 一台 Android 10 或更高版本的手机
- Mac 与手机连接同一 Wi-Fi

### 安装与配对

1. 构建 Mac 与 Android 两端：

   ```bash
   ./scripts/package-all.sh
   ```

2. 打开 `dist/AgentPager Bridge.app`。
3. 点击菜单栏中的像素信号图标，选择“安装 Codex Hook”。AgentPager 会保留原有 Hook 配置并自动备份。
4. 打开“AgentPager 设置 → 连接”，显示配对二维码。
5. 在 Android 手机上安装并打开 `dist/AgentPager-debug.apk`，扫描二维码。
6. 新建一个 Codex 任务，手机会自动显示它的实时状态。

已连接 Android 设备时，也可以直接运行：

```bash
./scripts/install-android.sh
```

## 当前可用的手机控制

| 操作 | 支持情况 |
| --- | --- |
| 批准 / 拒绝权限请求 | 可用 |
| 回答问题 | 可收到提醒，暂不能在手机上回复 |
| 中断 / 重试任务 | 暂不支持 |

AgentPager 只会展示当前确实可执行的操作，避免按钮看似可用却没有效果。

## 隐私与安全

- 手机端不保存任务记录，输入、步骤、问题和审批内容只存在于内存中。
- Mac 端只保留短期运行状态，完成两小时后自动清理，最多保留 20 项。
- 配对密钥保存在 macOS Keychain 与 Android Keystore。
- Bridge 不在线时，Codex Hook 会自动放行，不会阻塞任务。
- 建议仅在可信的局域网中使用。

## 许可

项目代码使用 GPL-3.0。第三方代码与字体归属见 [NOTICE.md](NOTICE.md)，字体许可全文位于 `LICENSES/`。
