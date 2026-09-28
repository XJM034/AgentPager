# Entire 提交同步诊断与防护（2026-09-28）

用户先授权推送本轮 AgentPager 修改，再要求排查并尽量解决 Entire 提交标记与记录不同步。
`alexx_custom` 已推送至 `origin`，回读为 `e0d1b25`；包含此前未同步的24个祖先提交。
原有未提交规格、研究、CONTEXT 与 docs/README 六行改动保持不动。没有推送 Entire refs。

## 已确认事实

- `6419e08` trailer 为 `c0400b94d85d`，本地存储分支没有对应元数据。
- 当日11:18:46本地日志明确记录：`failed to write checkpoint metadata: failed to get commit object: object not found`。
- `e0d1b25` 没有 trailer，是另一个证据缺口，不能自动归因为相同错误。
- Codex 事件使用 PATH 中0.10.6，Git Hook固定0.7.7。旧Hook抑制stderr且以成功退出，Git成功不能证明checkpoint成功。
- 本机会话约23MB，存在3.5MB单条压缩记录；未打印或上传正文。

## 复现与结论边界

纯合成旧版本8种组合、混合版本两种Desktop提交时序、加入大记录、加入现有checkpoint历史、
统一0.10.6两种时序均通过。无远程私有仓库副本也成功归并长会话；没有稳定复现原始对象缺失。
因此版本混用和长会话均不能被认定为已证实的唯一根因，不能宣称所有同步故障已根治。

原仓库没有运行doctor/clean/rewind等维护命令，没有重写历史、重放原会话事件或补造旧checkpoint。
诊断前备份位于 `.git/entire-recovery/20260928T123453-before-sync-diagnosis`；
私有复现使用独立副本，不含远程，不上传转录。现有缺失checkpoint仍按diff-only审查。

## 本次改动

- Codex/Git共用本机固定运行文件及哈希，避免升级后两个入口各用一个版本。
- Git post-commit/post-rewrite检查trailer、根元数据、各Session元数据与转录文件是否齐全。
- 本机按commit保存校验结果；缺失会明确警告，即使Entire自身返回0。存储成功不等于意图已审查。
- 已固定版本消失或哈希变化时不自动选择另一版本；安装器先备份并拒绝覆盖未知第三方Hook。
- pre-push只让代码推送继续，不运行Entire会话上传。

四项新增校验测试先红后绿，与既有保护测试共22项通过。实际0.10.6通过新Codex/Git适配器的
Desktop“先结束再提交”和“轮内提交”两种隔离用例均通过，检查真实trailer、元数据身份与转录存储。
另一次新增测试命令被项目PreToolUse保护拦截，未执行、未换工具重试，不计入覆盖。

claude-agents-bootstrap按受影响流程做范围内核对：根AGENTS/CLAUDE既有路由与安全边界仍有效，
无需修改根规则；更新本主题安全文档。真实仓库新提交的落盘结果须另行回读，不能以隔离测试代替。

## 实际启用与提交回读

本机已安装共享运行版本0.10.6；旧Git Hook及原固定配置的备份位于
`.git/entire-recovery/20260928T124211981655-git-adapters`。安装初次尝试发现只读Git封装
将hooks路径解析成/dev/null，在任何Hook或固定配置写入前失败；修正路径核实后安装成功。

实际修复提交 `cfb72ff` 自动生成 `Entire-Checkpoint: 9ffa3a755f52`。
新post-commit报告 `metadata-present`、CLI退出0。独立只读回读根元数据和Session元数据成功，
Session ID与当前已识别会话一致，Session转录文件存在；这次不是只有提交标记。
元数据files_touched覆盖本提交8个文件中的4个，其余Shell写入没有完整文件归因，
不能据存储完整宣称全部文件都有意图证据。既有旧checkpoint缺失仍未恢复。

这次实测证明新配置下的一次真实提交正常，不是长期零故障保证。后续缺失将明确报告，
若再次出现原始对象错误，应基于新报告及私有日志定位，不能以自动重试或历史重写掩盖。
