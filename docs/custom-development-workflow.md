# 长期定制与 Entire Review 流程

本文定义个人长期维护 AgentPager 时的分支、文档同步收尾、上游同步和代码审查规则。Android 与 macOS 的具体构建、安装和设备验收仍分别以 `docs/android-development.md` 与 `docs/macos-development.md` 为准。

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

## 大型功能的文档同步收尾

这是项目协作规则，由处理该阶段的 Agent 主动执行，不要求用户再次提出“更新文档”。
目前没有 Hook 或 CI 自动检查这项规则；写入规则不等于所有 Agent 已实测遵守。

### 触发时机

- 大型功能完成，或跨多个 Session/Ticket 的功能完成一个阶段时。跨端行为、协议、权限、配置或数据来源发生变化，也按此清单收尾。
- 代码已提交后，收到用户明确确认、真实测试反馈或有限豁免时，补录对应证据；不因代码已提交而漏掉文档。
- 用户确认需求变化，或阶段因阻塞暂停时，及时记录差异、已完成部分和恢复条件，不等整个功能结束。

### 收尾清单

1. 对照最新确认的目标、相关规格/Ticket、代码和验证记录，列出“已实现、已验证、未验证、阻塞/下一步”。
   区分原始目标与临时降级方案；需求缩减需有用户明确批准记录，不能由实现结果反向改写验收目标。
2. 按下表同步受影响文档，优先更新已有主题；无需更新的类别说明理由，不创建空文档。

   | 内容 | 记录位置 |
   | --- | --- |
   | 当前功能、入口、使用前提、安全边界及限制 | 现有功能说明；ZCode/GLM 使用 [现行功能与验收边界](zcode-glm-integration.md)。其他大功能没有入口时新增最小主题说明，并加入 [文档索引](README.md)。 |
   | 平台开发、测试、安装或恢复流程 | [Android 开发文档](android-development.md)、[macOS 开发文档](macos-development.md)；仅在 Agent 阅读路径或稳定守则改变时更新根/子目录规则。 |
   | 本阶段进度、验收证据、用户确认与遗留风险 | `docs/updates/YYYY-MM-DD-*.md`：记录范围、已知提交/版本、验证命令和结果、证据来源、未验证项、豁免范围及关联 Ticket。 |
   | 领域术语与长期架构取舍 | 按 [领域文档规则](agents/domain.md)维护；`CONTEXT.md` 仅作术语表，ADR 仅记录真正重要的取舍，均不存放任务进度。 |
   | Ticket 状态与依赖 | 以 [GitHub Issue Tracker](agents/issue-tracker.md)为准；仓库记录日期化状态与链接，不另建重复的永久待办。实际外部写入仍需授权。 |

3. 证据注明来源与范围：自动化测试、Agent 实测、用户反馈、代码推断分别记录。
   “代码已提交”“已安装”“真机验证”“用户批准豁免”“Issue 已关闭”是不同状态。
   使用已知的实现提交，不为补写同一文档所在提交的 SHA 反复改写历史；未知版本或测试细节标为未提供。
   历史报告保留当时事实，新增后续结果并链接现行说明；记录中只留脱敏证据。
4. 核对链接可达、现行说明与代码一致、历史记录未被伪装为新验收；运行 `git diff --check`。
   根规则有改动时运行 `cmp -s AGENTS.md CLAUDE.md`；确认本阶段修改未夹带其他任务的未提交内容。
5. 最终总结列出文档路径及同步状态，并分别报告代码、验证、文档和外部收尾状态。
   文档待补或待提交时明确指出；阻塞阶段只报告阶段结论，不能宣称整个功能完成。
   所有子票关闭也不能代替父规格的逐项验收。

### 与提交、交接的关系

- 尽量在本阶段的代码提交前完成事实性文档更新，并纳入同一审查范围。
  提交后收到的新反馈可形成独立文档补充，不为此自动 amend、rebase 或修改既有验收结论。
- 本规则授权任务范围内的本地文档同步，不新增 commit、push、GitHub 评论/关票、安装或发布权限。
  有相应授权时只提交指定范围并核验结果；无授权时报告“文档已本地同步，待提交/推送”，不重复询问普通文档编辑。
- 换 Agent 时按项目约定使用 `handoff/`，交接仅引用现有规格、进度记录和证据；长期事实先写回仓库文档。
  新 Session 从根规则 → 文档索引 → 相关功能说明/阶段记录和 Ticket 继续，不以用户复制聊天记录为前提。

### 与 Matt Pocock Skills 的分工

`ask-matt` 是流程路由；`implement` 负责实现、测试、代码审查和提交，但其当前文本没有上述文档同步收尾要求。
本项目清单补充这一环，不改写外部 Skill 源，也不要求每个 Ticket 重新运行规格拆分。
`domain-modeling` 负责术语与关键决策，`writing-for-agents` 负责 Agent 文档结构；
Matt 的 `handoff` 用于可携带上下文，不能替代仓库现行文档，也不与本项目实际加载的同名 Skill 混用。
需要调用 Skill 时使用当前加载的准确入口，不能只凭简称假设它已安装。

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
