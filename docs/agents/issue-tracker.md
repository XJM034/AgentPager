# Issue Tracker：GitHub

本仓库的需求、规格和开发票据记录在：

- Repository：`XJM034/AgentPager`
- Tracker：GitHub Issues
- `origin` 是个人定制仓库；不要把 Issue 发布到 `upstream`。

## 访问方式

优先使用当前环境已安装并获授权的 GitHub 集成。集成缺少所需能力时，可以使用已认证的 `gh` CLI。

读取 Issue 时必须读取完整正文、标签和评论。写入、评论、关闭、分配或修改标签属于外部操作，必须处于用户明确授权的任务范围内。

## 常用操作

- 创建：`gh issue create --repo XJM034/AgentPager`
- 读取：`gh issue view <number> --repo XJM034/AgentPager --comments`
- 列出：`gh issue list --repo XJM034/AgentPager`
- 评论：`gh issue comment <number> --repo XJM034/AgentPager`
- 添加标签：`gh issue edit <number> --repo XJM034/AgentPager --add-label "<label>"`
- 关闭：`gh issue close <number> --repo XJM034/AgentPager`

多行正文应使用文件或安全的 heredoc，避免 shell 插值泄露敏感内容。

## 发布规则

当 Skill 要求“发布到 Issue Tracker”时，在 `XJM034/AgentPager` 创建 GitHub Issue。

当 Skill 要求读取 Ticket 时，读取对应 Issue 的完整正文、评论、标签、状态和阻塞关系。

父规格 Issue 不应因拆票被自动关闭或改写。`to-tickets` 产生的每张开发票应：

- 引用父 Issue；
- 写明验收标准；
- 声明 `Blocked by`；
- 应用 `ready-for-agent`；
- 由一个独立开发 Session 处理。

## 阻塞关系

GitHub 原生 Issue Dependencies 可用时优先使用原生阻塞关系。工具不支持时，在正文中使用：

`Blocked by: #<number>, #<number>`

只有所有阻塞 Issue 都关闭后，该票才进入可开发前沿。不能因为存在 `ready-for-agent` 标签就忽略仍然打开的阻塞票。

## Pull Requests

PR 不作为默认的需求或 Triage 入口。未经用户明确要求，不创建、推送或处理 PR。
