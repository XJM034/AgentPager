# AgentGrid 领域词汇

## Task

一次可被 AgentGrid 观察和控制的 Codex 会话。Task 的权威运行态位于 Mac，Android 只接收 Task Snapshot。

## Task Event

会改变 Task 的领域事件。来源可以是 Codex Hook、rollout 记录或手机控制，但来源格式进入 Task 演化规则前必须先归一化。

## Task Snapshot

Task 在某一时刻可展示、可传输的稳定投影。它包含生命周期、活动、标题、最近步骤、Token、子代理和允许的控制能力；不代表需要永久保存全部字段。

## Subagent

归属于父 Task 的 Codex 子代理。Subagent 的运行态会影响父 Task 的活动状态，进入终态后只短暂保留。

## Pending Request

等待用户处理的审批或问题。Pending Request 与 Task 的生命周期及控制能力必须保持一致。

## Rollout Observation

对本地 Codex rollout 文件的发现、增量读取、排序和子代理追踪过程。文件位置、轮询节奏和重试规则属于观察过程内部知识。

## Task Catalog

Mac 上持有权威 Task 集合的领域概念。它负责状态变更后的保留期限、容量、标题富化、持久字段、排序与焦点投影。

## Task Dashboard Projection

Android 从原始 Task Snapshot 和前一投影推导出的稳定展示状态，包括排序、焦点、可见 Task、新进入 Task、仪表盘状态和下一次时间跃迁。

## Phone Session

Android 与 Mac 建立的已配对连接。它涵盖配对校验、凭据、连接与重连、控制序号和签名，以及快照和确认消息的接收。

## Hook Configuration

AgentGrid 管理的 Codex Hook 配置及其文件生命周期。安装与卸载必须保留用户已有配置，并支持备份与恢复。
