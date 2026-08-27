# 2026-08-27 Bridge build 7 与 Android 定制版安装记录

## 背景

代码审查修复（未完成行缓冲上限等）合入 `custom/brightness` 后，重新打包并安装 macOS Bridge，同时把 Android 定制版更新到已连接的 Redmi 真机。

## macOS Bridge：0.3.0 (7)

- `AGENTPAGER_VERSION_CODE=7 scripts/package-macos.sh`：BUILD complete 12.64 秒；本机无 Apple Development 证书，使用临时签名（与 build 5/6 一致）。
- 新二进制 SHA-256：`835578768a39f30006b66b8563c310098aa48f37c07525cc897d4823564b41ef`。
- 替换前核对：`/Applications` 中的 build 6 哈希 `633771a37ca51a7e3afc6cc6b516169119cb1fe4413f92313de9c434b79e583d`，与 2026-08-26 安装记录一致，未被改动。
- 备份：`dist/backups/AgentPager Bridge-0.3.0-build6-before-buffer-cap-20260827-124125.app`，备份哈希与安装时一致。
- 旧进程 SIGTERM 正常退出后替换；已安装二进制与 `dist` 哈希一致，`codesign --verify --deep --strict` 通过。
- 新进程从 `/Applications` 运行，端口 49361、49362 均监听；`node scripts/e2e-local.mjs` 通过（状态同步、反向审批、结束收敛、关闭帧存活）。

## Android 定制版：0.3.0-custom

- `scripts/install-android.sh`：Gradle 构建通过（45 任务全部命中缓存），标准安装 33.63 MB APK 到 Redmi Note 7（`bab1b5c`），启动并确认 `com.agentgrid.mobile.custom` 进程存活，crash 缓冲区无该包记录。
- 配对与设置完整保留：`terminal-mode=false`、任务亮度 100%、空闲亮度 76%。
- App 显示 LINK 已连接，实时展示任务终端（任务名、token 用量、剩余额度）。

## 重要发现：lsof 验证盲区

- `lsof -nP -iTCP:49362` 只列出 IPv6 监听套接字，**不显示** Bridge 已接受的 IPv4 连接，会误判为「手机未连接」。
- 正确核对方式：`netstat -an | grep 49362`，实测可见 `192.168.10.73.49362 ← 192.168.10.69.40150 ESTABLISHED`（手机 → en0）。
- 2026-08-26 设置标签文档中「采样时 49362 没有手机的已建立连接」应按此修正：当时的检查方式可能漏看了已建立的 IPv4 连接。

## 未验证项

- 缓冲上限对真实超长 rollout 行的效果、Bridge 长期 CPU/内存表现需后续观察。
- 手机端在 MIUI 后台限制下的长期连接稳定性、Hook 真实信任与配对二维码全流程未在本轮复验。
