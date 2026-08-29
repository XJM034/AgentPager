# 长期定制与 Entire Review 流程

本文定义个人长期维护 AgentPager 时的分支、上游同步和代码审查规则。Android 与 macOS 的具体构建、安装和设备验收仍分别以 `docs/android-development.md` 与 `docs/macos-development.md` 为准。

## 分支与远程职责

- `alexx_custom`：个人定制的长期维护分支，也是日常开发基准。普通功能优化直接在这里完成，不要求每项功能创建新分支。
- `origin`：用户自己的 AgentPager fork。目标远端分支为 `origin/alexx_custom`；创建、推送或删除远端分支必须由用户明确授权。
- `upstream/main`：原作者主线，只用于读取作者更新、评估同步影响或在用户明确要求时盘点官方版与个人版的总体差异。

长期分支不等于混合提交。每项功能仍应形成范围清楚、可独立测试、审查和回滚的小提交。Agent 不得擅自创建、切换、重命名、合并、变基、推送或删除分支。

## 日常修改与审查基准

日常 Review 以个人定制版本修改前的状态为基准，不以 `upstream/main` 为基准：

- 未提交修改：审查当前 `HEAD` 与工作区之间的本次差异。
- 刚完成的单个提交：审查该提交的父提交到该提交。
- 一组个人修改：使用用户确认的 Custom 提交范围，不自动扩大到全部未推送历史。
- 同步作者更新：先查看作者新增内容；合并后重点审查“同步前的 `alexx_custom`”到“同步后的 `alexx_custom`”，并验证原有个人优化仍然存在。
- 只有用户明确要求“比较个人版与官方版全部差异”时，才使用 `upstream/main` 做全量对照。

## 作者更新同步

收到同步请求后，先获取并阅读 `upstream/main` 的新增提交和影响范围，再说明 Android、macOS、协议和现有定制可能受到的影响。合并目标始终是 `alexx_custom`；出现冲突时停止并向用户说明，不用作者版本静默覆盖个人优化。未经用户明确要求，不执行 merge、rebase、push 或删除远端分支。

## Entire Review 的两层能力

项目中的 Entire 能力分为两层：

1. `entire-review` Skill：定义如何读取 checkpoint、提交和 Git diff 并输出审查结果。
2. Entire session tracking：由 Entire CLI、Codex/Claude Code 项目 Hook 和 Git Hook 记录 Session、checkpoint 与提交关联。

两套 Skill 入口是外部管理的软链接；不得直接编辑 `.agents/skills/entire-review/**` 或 `.claude/skills/entire-review/**`，因为这会沿软链接修改规范源。安装或修复 Entire Hook 时必须保留 AgentPager 及其他既有 Hook，并先保存可恢复备份。

准备进行带 Session 上下文的审查时，先只读核对：

```bash
entire status
entire agent list
ACCESSIBLE=1 entire doctor
entire session current --json
```

只有项目已启用、目标宿主已安装并受信、当前 Session 被追踪，或待审提交含 `Entire-Checkpoint:` trailer 时，才能声称审查包含 Session 意图。条件不完整时仍可按明确提交范围审查实际 diff，但必须标注为 `diff-only`，不能假装读取了 checkpoint 上下文。

## Review 由用户主动唤起

Hooks 和 Session tracking 可以在后台记录开发上下文，但日常开发完成后，Agent 只需正常报告修改、测试结果和未验证项，不主动运行、建议、催促或反复提醒 Entire Review，也不要求用户逐次回答是否开始审查。

只有用户主动调用 `$entire-review`、`/entire-review`，或明确要求开始 Entire Review 时，Agent 才核对本次 Git 范围、活动 Session 和 checkpoint，并执行审查。
