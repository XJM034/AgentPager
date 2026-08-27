# Product Design QA — Android General + Spark 额度

## Visual truth

- [完整布局对照](docs/assets/2026-08-27-general-spark/compare-full.png)：3692 × 852，SHA-256 `a8c17d4228c17f3d57c06486109997ffb9a5af59a53e342d7f775de5c28d4b6b`；保留额度条与任务列表的整体高度对照。
- [Redmi 真机首页](docs/assets/2026-08-27-general-spark/redmi-home-live.png)：2340 × 1080，SHA-256 `9687a8f76be9a6cd0eb4d31831dbe8f65981d2b0724aae9fefc13ccd1fcd812c`；build 8 真实 General + Spark 数据。
- [Redmi 真机额度页](docs/assets/2026-08-27-general-spark/redmi-dashboard-live.png)：2340 × 1080，SHA-256 `6dd29d003338fc15d09f0ef036f63c02b9be8ab84387742b6f826b8af433dcdc`；build 8 真实 General + Spark 数据。
- [分组更新时间窄栏 Preview](docs/assets/2026-08-27-general-spark/freshness-preview.png)：593 × 126，SHA-256 `c241a26d5de684fb40ae41732176422205335d20f17988cccc205b1c8313a7cb`；226dp 额度栏内完整显示 General 与 Spark 各自的新旧程度。
- 用户确认的关键要求：General、Spark 5h、Spark 7d 三个额度与右侧用量、设置按钮同高。

以上四张关键证据保存在仓库文档资源目录，不再依赖 `/tmp` 或 `/var/folders`。重新验证时，在指定模拟器或 Redmi 安装当前 Debug APK，进入首页与额度页后使用 `android layout --device="$ANDROID_SERIAL" --pretty` 检查布局，再用 `android screen capture --device="$ANDROID_SERIAL" -o <输出路径>` 保存截图；真机截图必须注明 App Build 与 Bridge Build。分组更新时间可用 Android Studio 的 `QuotaFreshnessTextPreview` 在 226dp 宽度下复核。

## States and data

- 模拟器通过本地临时 Bridge 验证 General 7d 与 Spark 5h / 7d 同时存在时的完整渲染。
- Redmi 先用旧 Bridge 验证了只有 General 时的向后兼容，再安装 build 8 完成真实 General + Spark 数据联调。

## Visual comparison

### Fonts

- 保留现有像素字体、全大写 `GENERAL` / `SPARK` 和数字字形。
- 顶部单行额度采用 8sp 标签与 11sp 百分比；在模拟器和 Redmi 上均无截断。

### Spacing and layout

- 每个顶部额度块固定 28dp 高，与右侧用量、设置图标行同高。
- General 使用单窗口 92dp 宽；Spark 使用双窗口 174dp 宽；5h 与 7d 用现有深色分隔线区分。
- 三个额度从两行高卡片压缩为一行：标题、周期、百分比同排，2dp 进度线位于数字下方。
- 任务列表恢复原纵向起点；模拟器与 Redmi 均未出现首条任务被覆盖或整体下移。

### Colors and tokens

- 沿用现有深黑背景、深蓝面板、青色额度、紫色 Spark 标签和灰色辅助文字；未引入新色相或圆角语言。
- 进度轨道、分隔线与现有界面层级一致。

### Images and assets

- App 运行时没有新增图片资源；继续复用现有像素图标与 Compose 绘制的进度线。`docs/assets/` 中的 PNG 仅用于保留 QA 证据，不会打入 APK。

### Copy and content

- 首页只展示扫描所需信息：额度组、周期、剩余百分比。
- 额度页以 General 为主读数，并在下方补充 Spark 5h / 7d 两个窗口。
- 缺少 Spark 数据时不显示空占位，旧 Bridge 仍保持原 General 体验。

## Iteration record

- V1：按初始图制作高卡片，遮挡第一条任务。
- V2：收窄并调整任务位置，解决遮挡但整体仍偏高。
- V4：额度页加入 Spark 双窗口。
- V5：继续压缩高度，仍不满足“与按钮同高”。
- V6：改为固定 28dp 单行额度条，与右侧按钮同高，任务列表恢复原位置。

## Verification gaps

- Windows 源码已同步协议，但本机没有 `dotnet`，未完成 Windows 编译验证。
- Redmi 已完成真实 General + Spark 首页、额度页、窄屏布局与 Bridge 重连验收。

final result: passed
