# #18 非活跃会话显示修复（Build28，尚未安装）

用户确认的新规则：OMP 无活跃状态不应持续占据 Android 列表；参照 Codex 一并自查并修复。该要求优先于 #14 时“空闲新会话也显示”的历史验收描述。本节不宣称 #18 或父 #13 完成。

## 修复与证据

- 现场只读快照有3条OMP offline，Paseo官方CLI为0.9.2、agentpager-omp状态failed；明确错误为已安装manifest仅允许0.8.0/0.9.1。
- Android按ID取最新状态后、排序/焦点/空闲判断前，过滤offline和普通idle；保持现有ZCode Stop-idle转换为完成反馈的特例。启动、运行、等待审批、等待回答不受新增过滤影响，既有ZCode启动过滤保留。
- 所有来源的完成/中断按completedAt（缺失时updatedAt）保留90秒，随后退出展示。即使其他任务运行或用户手动切换Dashboard，仍按绝对到期时间调度刷新；同会话新轮次重新显示，不用伪造完成或删除Paseo会话。
- 保留现有前五条与活跃优先排序，不采用上次“直接取消五条限制”的建议。非活跃记录不占这五条。
- Bridge对OMP idle/offline缓存应用现有一小时过期，容量不足时先清这些非活跃记录，再清终态；运行与等待任务不为凑数被驱逐。因此20仍为保护活跃任务的软上限，不能宣称全部任务硬限制20。
- manifest精确增加0.9.2；不开放所有未来版本。锁定运行SDK仍为0.8.0，独立安装官方0.9.2 SDK后严格类型检查通过。真实0.9.2公开目录→实际JS适配层→隔离loopback接收器成功获得空的权威快照；不等于插件reload或真实新轮次通过。

## 回归与审查

新增Android五项测试先5/5红灯，修复后转绿，覆盖离线占位、阻止空闲、挤掉Codex完成行、空闲隐藏而等待保留、完成/中断反馈90秒到期及手动切换。继续使用实际JS插件→隔离Bridge→手机WS捕获的历史协议fixture，按本次新规则更新Android期望；未修改fixture数据来迎合实现。Swift缓存测试先验证过期不清与错删完成卡两处红灯，再修复。

最终Swift183 Core +22 Bridge通过，Android100项通过，lintDebug及assembleDebug通过；SDK0.8.0与独立0.9.2类型检查通过，manifest2项测试通过。共享协议没有变化；没有宣称重新执行Windows桌面或真机硬件验收。

沿用固定总审查基准2118ffbd54299fea86cba0259aaf555f7c486f18，本次增量基于62d5be2。code-review Standards与Spec独立复核均0剩余发现；已补Spec建议的中断与手动切换定向断言并重新通过Android检查。

## 可审查安装与恢复方案

候选已构建，**没有安装**。Mac当前仍Build27；Android当前没有连接设备，不能推定手机当前版本。

| 项目 | 已核实候选 |
|---|---|
| 分支/远程 | alexx_custom；origin XJM034/AgentPager；不推送发布 |
| macOS | 0.3.0 / Build28；com.agentpager.bridge；Team2794UM7L67；严格签名通过 |
| Mac二进制SHA256 | 9dbba4847c62b8c00d4cca4bcae2546860f290f168dc0f07b49dc2fa7886d363 |
| Android | 0.3.0-custom / Build28；com.agentgrid.mobile.custom；AgentPager Custom；SDK36 |
| APK SHA256 | e4fd767a8e0ae9af8cfb2da8ee70e58de79c9262b1c65ce59577453477b41c9e |
| Debug证书SHA256 | c630ded2d67a812895d0934c6736f894e6dfe96793038482b1171aadbadf7abb |

获当前明确授权且Redmi连接后执行：

1. 重新核实分支、设备身份、原APK版本/签名；版本高于28或签名不一致即停止，不卸载清数据。将当前Mac App、相关配置、Redmi APK和可读应用数据备份到新的私有时间戳目录（0700/0600），记录哈希；保留已有备份，不输出配对/模型凭据。
2. 正常退出并替换正式Bridge，核对签名和二进制后启动；保留Keychain与原配对。保留数据升级Redmi Custom，比对升级前后数据并确认原配对连接。手机未连接时不把Mac安装当作两端安装完成。
3. 对获准日常目标仅显式reload自身agentpager-omp，官方CLI回读running；不重启日常Paseo、不改权限模式或第三方配置。
4. 最多两轮临时合成OMP任务（Codex模型/国内GLM各一轮）验证活跃显示、完成90秒隐藏及再运行恢复；等待状态先用已通过受控接缝确认，实际若产生问答由用户处理、不自动批准。Redmi观察离线/空闲不占位、Codex完成反馈不被挤掉和空闲界面；物理声音/亮度仍需用户确认。
5. 若失败，停止继续替换；正常退出新Bridge后恢复本次备份App并核验。Android仅在系统支持同签名保留数据降级时回退，否则说明阻塞，不以卸载清数据强行回退。配置仅恢复自身管理项，Paseo自身session不删除。

本次回滚尚未执行；备份方案不是恢复成功证据。#18其它尚缺现场用例继续沿用9月23日交付记录，不把这次局部修复当整体验收。
