# 项目 Specs

项目记忆语言：简体中文。

此目录用于保存需要跨会话延续的长期工作包。

推荐结构：
- `docs/specs/<slug>/spec.md`
- `docs/specs/<slug>/tasks.md`
- `docs/specs/_templates/`

规则：
- `spec.md` 是权威工作定义。
- `tasks.md` 只在多步骤工作需要时创建。
- 不要在这里创建 `plan.md`；`.agents/plan.md` 已经承担会话级计划。
- 当工作需要循环直到某个条件满足时，先在 `spec.md` 中定义 watched variable、check command、pass predicate、limits 和 abort conditions，再执行循环。
