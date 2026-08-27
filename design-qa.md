# Design QA：顶部剩余用量增强

## 对比目标

- 用户视觉参考：`/var/folders/4b/3nv411qn6ps7_w91p1ykfkh00000gn/T/codex-clipboard-c589328f-1db7-484e-b902-d402d1c44977.png`
- 同设备修改前基线：`/tmp/agentpager-usage-before.png`
- 修改后实现：`/tmp/agentpager-usage-after-v1.png`
- Redmi 真机实现：`/tmp/agentpager-redmi-usage.png`
- 全屏并排对比：`/tmp/agentpager-usage-compare-full.png`
- 右上角聚焦对比：`/tmp/agentpager-usage-compare-focus.png`
- 状态：AgentPager Custom 已配对、任务列表可见，当前 Agent 会话活跃

## 视口与归一化

- 用户参考图：1164 × 484 px，来自 Android Studio 中的横屏运行画面缩放截图。
- 修改前与修改后：均为 `medium_phone` 模拟器直接截图，2400 × 1080 px、420 dpi、横屏。
- Redmi 真机：Redmi Note 7 直接截图，2340 × 1080 px、440 dpi、横屏。
- 全屏与聚焦对比均使用同一设备、同一密度、同一横屏方向；没有额外缩放。用户参考只用于确认原有像素终端设计语言，精确布局判断以同设备前后截图为准。

## 全屏对比证据

- 用量区仍位于右上角，并继续与状态切换和设置入口组成同一组顶部控件。
- 新增的固定宽度浅色阶表面没有遮挡任务标题、按钮或列表内容，也没有改变任务行密度。
- 当前会话处于活跃状态时，用量读数仍持续可见，符合“非休眠时也能一眼看到”的目标。

## 聚焦区域对比证据

- 修改前：`7d 95%` 使用 9sp 弱化文字，56dp × 3dp 进度条，远看容易与顶部辅助信息混在一起。
- 修改后：`7d` 保持次级灰色，`95%` 使用 15sp 粗体语义色，进度条扩展到容器宽度并加厚到 4dp。
- 112dp 固定宽度避免百分比变化导致控件左右跳动；直角背景、像素字体、青色进度和既有 `Surface` / `Divider` 色值保持原设计语言。

## 必查视觉面

- 字体与层级：继续使用项目 Pixel 字体；标签 10sp，关键百分比 15sp 粗体，层级清晰且未出现截断。
- 间距与节奏：内部水平 10dp、垂直 6dp、文字与进度条间隔 5dp；与右侧 28dp 图标仍保持清楚分组。
- 颜色与令牌：只复用 `Surface`、`Muted`、`Cyan`、`Orange`、`Red`、`Divider`；未引入新色或圆角。
- 图像与资产：本次没有新增、替换或近似重画任何图像、图标或品牌资产。
- 文案与内容：可见内容仍为额度周期和剩余百分比；无业务文案变化。无障碍描述更新为“周期 + 剩余百分比”。

## Findings

- 没有 P0、P1、P2 或遗留 P3 问题。
- Redmi 真机截图确认额度仪表未遮挡任务列表或右侧控制区，字号、对比度和进度条在 2340 × 1080 横屏下保持清晰。

## Comparison History

### V1

- 调整：将横向小字与短进度线改为固定宽度的两级数字仪表，并保持原有像素终端色彩和直角语言。
- 结果：聚焦和全屏对比均未发现遮挡、溢出、层级冲突或设计语言漂移。
- 构建验证：`testDebugUnitTest lintDebug assembleDebug` 通过；安装后进程正常，未发现该进程的 FATAL EXCEPTION 或 ANR。
- 真机验证：`0.3.0-custom` 已安装并启动在 Redmi Note 7；截图确认右上角用量仪表和任务主页正常显示，官方包仍保留。

## Final Result

final result: passed
