# 2026-08-25 AgentPager Bridge 日志轮询性能修复

## 现象与定位

- macOS `cpu_resource` 诊断确认 AgentPager Bridge 0.3.0 在一次 111 秒窗口内平均占用 81% CPU，内存峰值约 924 MB。
- 最重调用栈为 `BridgeModel.handleRolloutObservation()` → `CodexRolloutReader.poll()` → `Data.replaceSubrange`。
- 原实现每解析一行都会删除缓冲区开头，较大日志会反复搬移剩余数据；同时一次轮询可读到文件末尾，子代理历史回放也没有大小上限。

## 修改

- 每次轮询最多读取 2 MB，剩余内容由后续轮询继续处理。
- 先用索引遍历所有完整行，最后一次性删除已消费前缀，避免逐行搬移整个缓冲区。
- 子代理历史日志只回放最近 2 MB，与普通会话发现的安全边界一致。
- 增加分段行、超过 2 MB 的增量读取和子代理回放上限测试。

## 当前验证

- 安装 Swift.org 官方用户级 Swift 6.2.4 工具链；系统默认 Swift 和 `xcode-select` 保持不变。
- `swift test --filter CodexRolloutReaderTests`：13/13 通过。
- `swift test`：86/86 通过。
- release 构建、临时签名和 `codesign --verify --deep --strict`：通过。
- 本机安装为 arm64 AgentPager Bridge `0.3.0 (5)`，监听端口 49361、49362 正常。
- 安装后连续约两分钟采样：单核平均 CPU 约 4%，`ps` 口径的驻留内存没有增长；随后三轮 `top` 显示 0%–6.2% CPU、约 42 MB 内存。没有复现旧版约 95% CPU 和持续内存增长，也没有生成新的 `cpu_resource` 报告。
- 用户已在 Redmi 真机确认 Android 手机端没有离线；真机连接未受新版 Bridge 安装影响。
- `git diff --check`：通过。

## 尚未完成

- 两分钟现场观察不能替代更长时间复发监测；若再次出现 ChatGPT 转圈，应先采样再做单变量退出实验。
- 未发布、推送或创建 Release。

## 回退

替换前的官方 build 4 已保存在 `dist/backups/AgentPager Bridge-0.3.0-build4-before-cpu-fix-20260825.app`。如修复版出现新问题，可正常退出 build 5 后恢复该备份。
