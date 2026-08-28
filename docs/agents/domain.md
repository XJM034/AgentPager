# Domain Docs

本仓库采用 single-context 领域文档结构。

## 探索代码前

按相关性读取：

- 根目录 `CONTEXT.md`
- `docs/adr/` 中与当前范围相关的 ADR
- 项目 `AGENTS.md`、`CLAUDE.md` 及平台子目录规则

如果 `CONTEXT.md` 或 `docs/adr/` 不存在，继续工作，不把缺失本身当作阻塞，也不提前创建空文档。它们应在领域术语或重要决策真正形成时，由领域建模流程按需创建。

## 结构

```text
/
├── CONTEXT.md
├── docs/
│   └── adr/
└── android/
    macos/
    protocol/
    windows/
```

Android、macOS、协议与 Windows 是同一 AgentPager 产品上下文中的平台实现，不因此拆成多个领域上下文。

## 领域语言

Issue 标题、规格、测试名称和实现说明应优先使用 `CONTEXT.md` 已定义的术语。缺少术语时先核对现有代码和产品文档，不能自行创造相互冲突的同义词。

## ADR 冲突

如果计划或实现与已有 ADR 冲突，必须明确指出冲突及原因，不得静默覆盖已有决定。
