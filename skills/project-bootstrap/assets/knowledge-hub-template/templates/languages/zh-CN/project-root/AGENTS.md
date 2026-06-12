# AGENTS.md

项目级 agent 入口。

主要说明位于 `.agents/AGENTS.md`。每次非平凡任务开始时，先读取该文件，再计划或编辑。若 runtime 没有自动加载嵌套说明，本根文件就是 fallback contract。

项目记忆语言：简体中文。

每次实质会话的最低读取顺序：
1. `.agents/AGENTS.md`
2. `.agents/process.txt`
3. `.agents/plan.md`，仅非平凡任务需要
4. `.agents/context/README.md`，然后只按 Summary、Keywords 或任务相关性打开匹配的 `.agents/context/**` 条目

启动时不要预加载完整 `.agents/context/` 目录。

即使 `.agents/AGENTS.md` 未加载，也适用以下核心规则：
- 系统、runtime 和用户明确指令优先于项目默认值。
- 常规可逆实现选择由 agent 自行判断；遇到真实歧义、破坏性动作、外部写入、缺失凭据或 policy / safety 风险时停止。
- 对宽泛或范围不清的请求，先做只读探索；必要时再澄清目标、范围和验证方式。
- 工程记忆刷新、模板升级和语言迁移不是普通批量文件编辑。执行前必须先检查并使用相关 skill / script workflow：刷新或升级默认保留项目特化内容；语言迁移处理模板替换和经复核的叙述内容，并保持命令、路径、API、文件名、错误文本和代码符号等受保护字面量原文；reset / reinitialize 只有在用户明确允许丢弃旧记忆时才可执行。
- 非平凡工作优先在 `docs/specs/<slug>/` 下建立 lightweight work package。
  使用 `workflow-spec-lite` routing criteria 作为是否需要 spec 的决策规则：
  目标窄、验收清晰、验证路径明确且没有长期设计价值的 quick path 任务可以不创建 spec。
- `.agents/plan.md` 保持会话本地，不要复制完整项目 specs 或任务清单。
- 只有用户或项目策略要求时才 commit。只有用户明确要求，或既有项目流程明确要求时才 push。

需要在当前会话后保留的非平凡工作，使用：
- `docs/specs/<slug>/spec.md`：持久目标、约束、方案和验收。
- `docs/specs/<slug>/tasks.md`：多阶段工作需要的长期执行步骤。
- `docs/specs/_templates/`：可复用项目模板。

多阶段工作应在 spec 中使用 Execution Contract，使 agent 在 stop rule 触发前持续推进到下一个已验证阶段。
