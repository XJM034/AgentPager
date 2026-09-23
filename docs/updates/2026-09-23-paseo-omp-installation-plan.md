# #18 本 Session 安装与恢复方案（待授权）

本文件是可审查方案，不代表已经执行。用户要求本 Session 对安装、重启和模型调用额外授权；前票授权不沿用。子票只有全部验收满足才关闭，父 #13 保持 OPEN。

## 核实目标

| 目标 | 当前已核实 | 拟操作 |
| --- | --- | --- |
| 工作区 | alexx_custom；origin XJM034/AgentPager；基准 2118ffb | 仅本地提交 |
| 正式 Mac Bridge | /Applications/AgentPager Bridge.app；0.3.0 / Build20；com.agentpager.bridge；Apple Development / Team2794UM7L67 | 同身份 Build26，最终包重验后替换 |
| Paseo | 0.8.0；本机默认 daemon，loopback 6767；omp 已启用，插件总开关关闭；插件清单空 | 在明确授权后满足全局前提；只安装 agentpager-omp |
| omp | 18.2.8 | 保留既有登录与权限模式 |
| Android | 新 APK com.agentgrid.mobile.custom / AgentPager Custom；0.3.0-custom / Build26；SDK36；Debug证书 SHA256 c630ded2d67a812895d0934c6736f894e6dfe96793038482b1171aadbadf7abb | 仅连接后的 Redmi；读回机型/序列号/原版本/签名，匹配才升级 |

当前 adb 无设备；Redmi 型号、设备序列、原 APK 版本和签名尚待连接后核实。未知信息不得填为已验证。若原版本高于26或证书不匹配，停止安装并说明，不卸载清数据。

## 备份与安装

1. Mac 私有备份放在 `~/Library/Application Support/AgentPager/issue18-backups/<时间>/`，目录0700、敏感文件0600，不提交Git。保存旧App、既有任务/偏好、Paseo配置和AgentPager接入配置（如有），记录版本、签名及文件哈希；不导出钥匙串或模型登录凭据。
2. 确认dist当前不在运行，重打最终Build26，签名/Bundle/版本/二进制哈希核实后正常退出旧Bridge、复制新App、再次核对哈希和严格签名再启动。沿用原钥匙串配对与GLM条目；系统授权弹窗由用户处理，不放宽ACL或信任。
3. 全局插件开关当前关闭。Paseo官方文档明确该开关影响所有已启用插件；AgentPager产品不代改。推荐用户在Paseo Settings打开 Enable plugins；此时读回仍无第三方插件后，再点击Bridge一次启用。若希望Agent代操作这个全局前提，须在本Session明确授权该额外动作。
4. 正式启用通过本票Bridge配置入口，安装App内插件；读取running，核对认证入口和手机当前快照。重复启用、关闭、恢复、撤销及再次启用均仅操作agentpager-omp，检查第三方/权限配置未变。源码更新后对获准目标显式reload并回读running。
5. Redmi连接并授权调试后，用Android CLI/adb只读核实明确目标，备份原APK和可读取应用数据，限制权限并记录哈希。若备份不能保证可恢复，暂停设备安装。使用保留数据的升级安装，不卸载、不清数据、不改包名；首次启动核对原配对仍有效。

## 真实验收操作范围

- 最多12轮合成小任务：优先Paseo内Codex与智谱国内版GLM Coding Plan glm-5.3，每轮只操作临时合成目录、不使用业务数据；保留现有登录，不读取/打印模型凭据。原生Codex/Claude Code/ZCode各一个最小任务作为原来源回归。每轮尽量短，若需超出12轮另说明原因。
- Paseo新建无prompt、两模型运行/工具活动/完成、同会话继续/模型切换、多会话；核对当前公开状态、实际手机WebSocket和Redmi呈现。
- 原生问答在Paseo中处理，不增加手机回答/批准/停止能力，不修改Full Access，不自动批准。可对本次合成会话执行Paseo原生取消；真实回答须由用户在Paseo完成或得到对具体合成回答的明确授权。
- 正式Bridge正常退出/重启、Redmi App重连、插件disable/enable/reload、归档本次测试会话，检查原配对、无重复卡/历史完成提醒。
- 运行中异常退出与Paseo daemon重启优先在另建私有home、独立loopback端口的真实Paseo/omp中执行，只终止本次测试进程。隔离手机配对须先备份原数据，完成后恢复；该结果不替代正式配对持久化的单独验证。不重启日常Paseo daemon或终止用户已有会话，除非用户额外明确授权。
- Redmi现场检查提示音开/关、卡片、完成反馈和亮度。Android CLI读取布局、必要时截图并实际查看；用户协助听音和肉眼亮度确认。仅截图、系统数值或模拟器不能宣称物理效果通过。
- 正式Bridge回归原来源及Codex/GLM实时额度；只使用既有正常额度刷新，不兑换reset。没有GLM Key的监控独立性另外用无Key隔离配置/受控接缝验证，不删除用户日常Key来造测试。
- 至少记录开始与结束资源采样，明确它不等于长期性能验收。历史前票结果不替代本次实际安装组合验收。

## 恢复与退出条件

- 成功：保留用户拟日常使用的Build26及接入；恢复为测试临时改过的音量/静音/亮度设置，归档本次合成会话，清理私有测试进程/端口；备份保留可回退。
- Mac失败：正常退出新Bridge，恢复旧App并验证签名和哈希，恢复必要的任务/偏好/接入配置；只撤销本次自己的插件。第三方配置不整份覆盖，以变更前后对比恢复自身项；钥匙串保持原样。
- Android失败：不卸载；在同证书Debug且系统允许时恢复旧APK，再在停止App后恢复已备份应用数据并比较文件集合/哈希，启动核对原配对。若设备不允许安全降级，暂停并说明，不能以清数据方式强行恢复。
- 未获授权、没有Redmi、无法确认实际听音/亮度、恢复失败或必要用例缺证据：保留#18 OPEN，逐项写明当前事实，不宣布父规格通过。继续在当前Session处理，不能虚构完成或把旧验收当新证据。

## 已准备候选的校验值

2026-09-23最终重打：Mac Build26，Team2794UM7L67，严格签名验证通过；主二进制SHA256 `71fa5d3c26dc0b340fb9cff047be48a17d86722e534818be13342668ff89e357`。Android Build26 APK SHA256 `27ef7190df6acb049d468dcab98fd1cddb2b041f0547d9682c16759dcfd7ca95`。安装前仍需再次核对，若后续审查或修改导致产物变化则重新记录。
