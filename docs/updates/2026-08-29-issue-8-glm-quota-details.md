# Issue #8 GLM 额度详情与诚实降级

日期：2026-08-29

范围：GitHub Issue #8。补齐 Android 同页 GLM 额度详情、Bridge 数据健康状态、错误分类、最后可信读数与指数退避；没有开始 #9/#10，没有使用真实 Key、真实接口、钥匙串、安装或设备操作。

## 用户可见结果

- Android 现有额度详情增加直角 `CODEX / GLM` 选择器，默认仍是 Codex；Codex 的 General、Spark、Token 历史和顶部额度路径保持原数据源。
- GLM 详情使用上游套餐原值或 `GLM Coding Plan` 回退名，并将可选 `level` 作为不透明原值单独展示；同时显示 5 小时/每周窗口、剩余比例、重置时间、最后成功时间、最后更新时间和数据健康状态。
- 剩余低于 20% 使用橙色并显示“额度偏低”，低于 10% 使用红色并显示“额度告急”；每个窗口提供完整无障碍描述。
- 未配置 Key 时显示中性的“未启用”和一次克制的 Mac 可选连接说明，不显示警告、`--%`、0% 或额度耗尽；顶部继续不显示 GLM 空占位。
- 已配置但从未成功读取时显示“鉴权失效”“套餐已过期”或“暂不可用”，不伪造百分比。临时错误会保留最后可信窗口并标记“数据陈旧”。
- macOS 设置继续使用“GLM 额度连接（可选）”，并显示连接状态、最后成功时间、最后更新时间、固定脱敏错误、手动刷新和删除 Key。

## 数据健康与恢复

- provider adapter 分开识别 HTTP/业务 401、403、429、5xx、超时、非 JSON、缺失字段、未知 Schema、明确套餐过期和明确额度耗尽；已批准研究记录中的业务码 `1308`、`1310` 归为耗尽，`1309` 归为过期。
- 套餐过期和额度耗尽只接受结构化状态白名单；未知错误正文不会被猜测为耗尽，也不会进入日志或协议。
- 429、超时、5xx、非 JSON、鉴权、Schema 和临时网络错误在存在历史时保留最后成功快照，并同时标记陈旧或鉴权失效；从未成功时不展示百分比。套餐过期不携带旧窗口。
- 自动刷新保持 single-flight。失败后从 10 分钟开始指数退避，首轮失败延长到 20 分钟，最大 4 小时；成功后恢复 10 分钟。
- 删除 Key 会先删除存储、取消调度和在途任务、清除最后可信值并立即发布“未启用”；旧请求即使稍后返回也不能恢复数据。
- `remainingAmount` 继续原样保留服务端 `remaining`，`percentage` 继续按已使用比例解析，Android 展示 `100 - percentage` 的剩余比例。

## 协议与平台边界

- 没有新增或删除 JSON 字段，也没有提升协议版本；复用开放的 `usageProviders[].status`、provider `capturedAt` 与 group `capturedAt` 表达健康、最近尝试和最后成功时间。
- 旧客户端仍可忽略未知 `status`；旧 Bridge 不发送这些状态时 Android 保守显示“暂不可用”或继续读取 Codex。
- 协议结构未变化，因此 Windows 无需修改；继续沿用已批准的 Windows 实际运行豁免。
- 没有读取 ZCode OAuth、Cookie、provider 配置、私有缓存或 Electron RPC；没有展示模型、MCP、工具、每日明细或趋势图。

## TDD 与自动化覆盖

按公开接缝执行红绿循环：

1. provider adapter：合成 401、403、429、5xx、超时、非 JSON、字段缺失、未知 Schema、套餐过期、明确耗尽和未知错误。
2. 刷新协调器：未启用不查询、single-flight、成功/陈旧、指数退避恢复、首次失败不伪造 0%、候选 Key 保护和删除竞态。
3. Android 呈现：Codex 默认回退、正常、低额度、明确耗尽、陈旧、未启用、鉴权失效和未知 Schema。
4. macOS 设置：数据健康文案、固定脱敏错误和既有 Bridge 非阻塞接线。

Compose Preview 已覆盖 GLM 正常、低额度、陈旧、未启用、鉴权失效和未知 Schema。

## 已运行验证

- `scripts/android-doctor.sh`：通过；JDK 17、Gradle 8.13、Android SDK、`medium_phone` 可用。检测到 Redmi Note 7，但未操作。
- `cd macos && swift test`：Core 163 项、Bridge 6 项通过，失败 0 项。
- Android `testDebugUnitTest lintDebug assembleDebug`：通过。
- `protocol/fixtures` 与 `docs/contracts` JSON 解析、`git diff --check` 和敏感信息扫描：首轮通过，修订提交前再执行最终复验。
- Standards / Spec 双轴首轮审查共发现 7 项：3 项重复或未使用实现、4 项最后可信读数、业务码、`level` 语义和顶部健康提示问题；均已修复。首次复审又发现 3 项重复映射，以及“首次明确耗尽”误用失败尝试时间作为最后成功时间；补充失败回归测试后均已修复。最终 Standards 0 项、Spec 0 项。

## 未验证项

- 真实 Coding Plan Key、真实额度接口和官方页面同时间对照。
- macOS 钥匙串保存/删除、菜单栏设置交互、最终 App 打包、签名、安装和回滚。
- Android Custom APK 安装、Redmi 真机选择器布局、无障碍朗读和 Bridge 联调。
- 真实 401、403、429、套餐过期、耗尽、5xx、超时和 Schema 漂移；本次只用合成响应验证产品降级。
- 长时间退避与真实 Bridge 进程的 CPU、内存和网络行为。

这些项目按要求留给 #10 的用户明确 opt-in 验收；本次没有扩大授权。
