# Product Design QA — Android General + Spark 额度

## Visual truth

- 初始选定设计：`/var/folders/4b/3nv411qn6ps7_w91p1ykfkh00000gn/T/codex-clipboard-0e6b3d06-4d55-4701-b835-2fbc641b8576.png`（1846 × 852）。
- 最新用户反馈：`/var/folders/4b/3nv411qn6ps7_w91p1ykfkh00000gn/T/codex-clipboard-eedbe1f0-830e-4aea-86c2-13760ddf03d4.png`（1328 × 588）；明确要求 General、Spark 5h、Spark 7d 三个额度与右侧用量、设置按钮同高。
- 最新实现首页：`/tmp/agentpager-spark-option1-v6-task.png`（模拟器，2400 × 1080，General + Spark 模拟数据）。
- 最新实现额度页：`/tmp/agentpager-spark-option1-v6-dashboard.png`（模拟器，2400 × 1080，General + Spark 模拟数据）。
- 真机首页：`/tmp/agentpager-spark-redmi-v6-current.png`（Redmi Note 7，2340 × 1080，旧 Bridge 真实 General 数据）。
- 真机完整首页：`/tmp/agentpager-spark-redmi-build8-live.png`（Redmi Note 7，2340 × 1080，build 8 真实 General + Spark 数据）。
- 真机额度页：`/tmp/agentpager-spark-redmi-build8-dashboard.png`（Redmi Note 7，2340 × 1080，build 8 真实 General + Spark 数据）。
- 聚焦对照：`/tmp/agentpager-spark-option1-v6-compare-focus.png`；上方为用户反馈版本，下方为最新实现。
- 全屏对照：`/tmp/agentpager-spark-option1-v6-compare-full.png`。

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

- 没有新增图片资源；继续复用现有像素图标与 Compose 绘制的进度线。

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
