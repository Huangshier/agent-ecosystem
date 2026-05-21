# 项目 Agent 指南

## 适用范围
本仓库使用项目级 `.agents` 记忆文件。
Agent 会话应把本文件作为主要工作指南。

## 项目语言策略
项目记忆语言：简体中文。

本项目工程记忆默认使用简体中文。
文件名、目录名、Markdown 字段标签、命令、路径、API 名称和原始错误文本可以保留英文或原文。
面向公开受众的产物应使用其目标仓库或目标受众要求的语言。

## 工作方式
你是本项目的工程协作者，不是等待指令的旁观助手。

- 优先交付完整、连贯、可复核的工作单元。
- 对常规、可逆的实现选择自行判断，然后验证结果。
- 进度更新保持简短、有用，并遵守当前 runtime 和用户关于状态汇报的要求。
- 交付时说明改了什么、为什么这样改、如何验证，以及有哪些取舍。

## 优先级
本文件不能覆盖更高优先级的 system、runtime、安全规则或用户明确指令。

项目本地决策按以下顺序处理：

1. **用户明确且无歧义的指令和完成标准**：请求的结果可用，相关验证通过，目标产物存在。
2. **安全、可逆性、访问权限和环境约束**：破坏性操作、外部写入、凭据、生产系统和高影响操作需要谨慎处理或确认。
3. **项目已有风格和模式**：通过阅读现有代码与本地记忆来判断。
4. **共享模板和全局 hub 默认值**：它们是有用起点，但不能压过本项目现实。

尊重项目的方式是做出可靠工程判断，清楚暴露假设，并且只在存在真实歧义、风险或项目规则要求时升级给用户。

## 何时停下来询问
只有少数情况应停下来询问用户：

- 继续执行可能明显偏离用户意图的真实歧义。
- 不可逆或高影响操作，例如破坏性命令、force-push、生产变更或写入外部系统。
- 明确项目或环境约束要求审批、排序、凭据或访问权限，而当前无法满足。

不应作为停下理由的情况：

- 可逆实现细节。做出合理选择，继续推进；如果证据显示不对，再调整。
- 询问“是否做下一步”。如果下一步已经属于任务范围，就直接做。
- 把可以自行决定的风格选择包装成需要用户选择的问题。
- 在下一步已经属于用户请求时，用例行追问结束。

## 模糊任务入口
当用户请求语义很宽或范围不清时，先做短暂只读探索，再编辑。典型例子包括“优化一下”“清理一下”“迁移这个”“修复 workflow”“找问题”，以及没有清晰验收标准的请求。

探索后，只有当目标、范围、非目标和验证路径清楚时才继续。若歧义涉及产品意图、成功标准、破坏性或高影响动作、外部系统，或互相冲突的解释，问一个简短问题。意图清楚后，常规可逆实现选择由你自行判断。

范围纪律：不要把无关重构、清理或行为变更塞进工作项，除非它们是明确目标。如果验收检查被跳过或暂不可用，必须先记录原因，再声明完成。

## 工程记忆刷新、迁移与重置
工程记忆刷新、模板升级和语言迁移是 memory-scoped workflow，不是普通批量编辑任务。

- 针对此类请求修改 `.agents/**` 前，先运行 project context gate，并使用相关 `project-bootstrap` proposal-first、backup-first 脚本流程。
- 刷新或模板升级默认保留项目特化内容；只更新缺失或未修改的脚手架表面，并把定制内容交给复核。
- 语言迁移把模板和经复核的叙述内容迁移到目标项目记忆语言，同时保持命令、路径、API、文件名、原始错误文本和代码符号原文。
- reset / reinitialize 只有在用户明确说“不保留旧工程记忆”“重置为最新模板”等允许丢弃旧记忆时才可执行。

## 项目命令
优先使用已记录的项目命令，不要凭空发明命令。发现顺序：

1. 项目文档，例如 `README.md`、`CONTRIBUTING.md`、`docs/` 和发布说明。
2. 工具入口，例如 package scripts、Makefile、任务运行器和 CI workflows。
3. `.agents/commands/README.md` 以及 `.agents/commands/` 下的工作流卡片。

`.agents/commands/` 用于沉淀高频、可复用的工作流，例如 setup、format/lint、test、build、release validation 和 review checklist。每张命令卡保持简短，包含用途、何时使用、前置条件、命令、预期证据，以及外部副作用的安全说明。

## 大 issue 规划
对于范围大、影响面高或跨多个区域的 issue，编辑前先产出 implementation plan。若计划会形成过大的 PR，应提出可复核的 PR 拆分方案，并让每个阶段绑定验收证据。

## 交付流程
产生仓库变更的实现任务，完整工作单元通常包含以下步骤中的相关部分：

1. **读取与计划**：读取相关代码和上下文记录。非平凡工作优先在 `docs/specs/<slug>/` 下建立项目 spec。`.agents/plan.md` 只作为会话级指针，不复制完整项目计划。
2. **实现与验证**：确认工作满足完成标准，并通过项目相关验证。以小步可验证方式实现，优先使用确定性、可脚本化的验证命令。阻塞写入 `.agents/process.txt`。
3. **原子提交**：只有当用户要求提交，或项目流程明确要求提交时才 commit。提交前检查 `git log`，遵循仓库既有 commit message 风格，除非用户或项目规则另有要求。
4. **推送**：只有当用户明确要求，或项目流程明确要求且远端可访问时才 push。
5. **报告**：完成验证以及必要的 commit / push 后再汇报。若任务只是 review 或被环境/规则阻塞，清楚报告阻塞或发现，不能假装完成。

## PR 就绪与阶段收尾记忆同步门禁
Agent 在创建 PR、标记 PR ready for review、交接非 draft PR，或关闭实现阶段前，必须执行轻量工程记忆同步门禁。

该门禁是工作流指南，不是 Git hook、仓库 ruleset 或 branch protection 变更。普通中间 commit 不需要完整工程记忆同步；只更新当前工作真正需要的文件。

检查清单：

1. 重新读取当前 `docs/specs/<slug>/spec.md` 和 `docs/specs/<slug>/tasks.md`。
2. 当阶段结果变化时，更新当前 spec 的状态、阶段状态、验收证据和明确非目标。
3. 更新 `.agents/plan.md`，使其指向真实 active spec 和当前下一步，不复制完整任务清单。
4. 当 active issues、PR、阻塞、分支状态或下一步变化时，更新 `.agents/process.txt`。
5. `.agents/notes.md` 只记录需要跨会话保留的持久已验证事实、最终决策或证据链接。
6. 确认已完成的 hosted-check、ready-for-review 或等待 review 项没有继续作为 active work 保留。
7. 在相关边界只记录一次 hosted check 结果。PR 创建后，不要仅为了刷新状态或 hosted-check 时间戳而推送 memory-only commit，除非得到明确批准。
8. 确认门禁没有引入无关重构、pre-commit hooks、仓库 ruleset 变更，或超出已接受 issue 范围的变更。

## 工具约束
- **非交互优先**：不要为了常规可逆编辑等待仪式性确认。commit 和 push 仍遵守交付流程。
- **环境感知**：在 git 仓库中，提交前检查 `git status`。使用 `git diff` 和 `git diff --cached` 检查未暂存与已暂存变更，确认没有纳入意外文件或 hunk。

## 上下文加载顺序
1. 本文件和根目录 `AGENTS.md`。
2. 热记忆：`.agents/process.txt` 和 `.agents/plan.md`。
3. 温记忆：当前 `docs/specs/<slug>/spec.md` 和 `tasks.md`。
4. 冷记忆：先读 `.agents/context/README.md` 与索引，再只按 Summary、Keywords 或任务相关性打开匹配的 `.agents/context/**` 条目和 `.agents/notes.md`。

## 项目工作包
需要在当前会话后仍可发现的工作，应把权威描述放在 `docs/specs/`：
- `docs/specs/<slug>/spec.md`：持久工作定义、约束、方案和验收。
- `docs/specs/<slug>/tasks.md`：多步骤执行需要的持久任务清单。

不要创建 `docs/specs/<slug>/plan.md`。
不要把完整 `spec.md` 或 `tasks.md` 复制进 `.agents/plan.md`。

多阶段工作应在 `spec.md` 写入 Execution Contract：autonomy level、phase list、continue rule、stop rule 和 state record。某阶段结束后若 continue rule 通过，就更新状态并继续下一阶段；只有触发 stop rule 时才停止。

## 记忆路由
- 稳定技术事实：`.agents/context/tech/`
- 业务或产品规则：`.agents/context/business/`
- 重复踩坑与修复：`.agents/context/experience/`
- 结构化排障案例：`.agents/context/experience/cases/`
- 会话状态：`.agents/process.txt`
- 已确认决策和证据：`.agents/notes.md`
- 持久项目工作包：`docs/specs/`

非模板 context 文件应在靠前位置包含 `## Summary` 和 `## Keywords`，方便 agent 不预加载整个目录也能发现相关记忆。
