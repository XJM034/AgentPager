# 2026-08-27 代码审查修复

## 背景

对 `custom/brightness` 分支执行 entire-review（基准 `upstream/main`，共 6 个提交、82 个文件），发现 2 个中危、5 个低危问题。本轮修复其中 6 项；「2 MB/次轮询读取的积压消费速率受轮询频率限制」确认为已文档化的刻意取舍，仅记录不改动。

## 修改

### macOS：rollout 未完成行缓冲上限

- `CodexRolloutReader` 新增 `maximumPartialLineBytes = 8 MB`：轮询追加数据后立即截断 `partialLine` 头部。被截断的行 JSON 解析失败会被 `signal(from:)` 安全跳过，因此超长行既不会跨轮询驻留内存，也不会被整体解析。
- 新增测试「单行超过缓冲上限时丢弃该行并继续解析后续行」：9 MB 的超长 user_message 行被丢弃，后续正常行照常产生信号。

### 仓库：技能符号链接退出版本库

- `.agents/skills/` 与 `.claude/skills/` 下 48 个指向本机 `~/Projects/agent-skill-sources/...` 的绝对路径符号链接退出 Git 跟踪；磁盘文件保留，本机技能加载不受影响，其他克隆不再出现悬空链接。
- `.gitignore` 新增规则：技能目录只保留 `android-cli` 项目副本。
- `skill-profile.json` 与两份 android-cli 副本继续入库，与 AGENTS.md 声明一致。

### 低危项

- `scripts/install-android.sh`：`自定义包名` 上方增加与 `build.gradle.kts` 中 debug `applicationIdSuffix` 的同步注释。
- `android/app/build.gradle.kts`：`buildTypes` 上方注明定制共存标识仅覆盖 debug，构建 release 前必须先调整包名。
- 删除无引用的 `res/values/strings.xml`（`app_name` 已被 `${appLabel}` 占位符取代）。
- `design-qa.md` 移入 `docs/updates/2026-08-26-android-usage-gauge-design-qa.md`，符合日期化记录约定。

## 验证

- `cd macos && swift test`：87/87 通过（含新增缓冲上限测试）。
- Android：`cd android && JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home" ./gradlew testDebugUnitTest lintDebug assembleDebug`：BUILD SUCCESSFUL in 36s，55 个任务（23 执行、32 命中缓存）；JVM 单元测试、Android Lint、Debug APK 构建均通过。

## 范围

- 本轮未修改协议、Hook 安装逻辑、Bridge 服务与 Android 业务逻辑；`strings.xml` 删除仅移除死资源。
- 所有修改尚未提交，等待确认后按功能分组提交。
