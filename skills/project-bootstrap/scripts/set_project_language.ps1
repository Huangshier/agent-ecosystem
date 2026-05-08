[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ProjectDir = (Get-Location).Path,
    [Parameter(Mandatory = $true)][string]$ProjectLanguage,
    [switch]$OverwriteScaffold
)

$ErrorActionPreference = "Stop"

function Join-PathParts {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(ValueFromRemainingArguments = $true)][string[]]$Children
    )

    $path = $Root
    foreach ($child in $Children) {
        if ([string]::IsNullOrWhiteSpace($child)) {
            continue
        }
        foreach ($segment in @($child -split '[\\/]+')) {
            if (-not [string]::IsNullOrWhiteSpace($segment)) {
                $path = Join-Path $path $segment
            }
        }
    }
    return $path
}

function Ensure-Dir {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Resolve-ProjectLanguage {
    param([string]$Language)

    $normalized = $Language.Trim().ToLowerInvariant()
    if ($normalized -in @("en", "en-us", "english")) {
        return [ordered]@{
            code = "en"
            label = "English"
            marker = "Project memory language: English."
        }
    }

    if ($normalized -in @("zh", "zh-cn", "zh-hans", "chinese", "simplified-chinese", "simplified chinese", "中文", "简体中文")) {
        return [ordered]@{
            code = "zh-CN"
            label = "Simplified Chinese"
            marker = "项目记忆语言：简体中文。"
        }
    }

    throw "Unsupported project language: $Language. Supported values: en, en-US, English, zh-CN, zh-Hans, Chinese, 中文, 简体中文."
}

function Set-TextFile {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $path = Join-PathParts $ProjectDirFull $RelativePath
    $parent = Split-Path -Parent $path
    Ensure-Dir -Path $parent

    if ((Test-Path -LiteralPath $path) -and -not $OverwriteScaffold.IsPresent) {
        return "skipped"
    }

    if ($PSCmdlet.ShouldProcess($path, "Write localized project memory scaffold")) {
        Set-Content -LiteralPath $path -Value $Content -Encoding UTF8
    }
    return "written"
}

function Get-EnglishScaffold {
    $files = [ordered]@{}

    $files["AGENTS.md"] = @'
# AGENTS.md

Project-level agent entrypoint.

Primary instructions are in `.agents/AGENTS.md`. At the start of any non-trivial task, read that file before planning or editing. If the runtime does not automatically load nested guidance, this root file is the fallback contract.

Project memory language: English.

Minimum read order for each substantive session:
1. `.agents/AGENTS.md`
2. `.agents/context/`
3. `.agents/process.txt`
4. `.agents/plan.md` (for non-trivial tasks)

Core rules that apply even if `.agents/AGENTS.md` was not loaded:
- Follow system, runtime, and explicit user instructions before project defaults.
- Make routine reversible implementation choices yourself; stop for genuine ambiguity, destructive actions, external writes, missing credentials, or policy/safety risk.
- For broad or underspecified requests, do read-only exploration first, then clarify goal/scope/validation before editing when needed.
- For non-trivial work, prefer a lightweight work package under `docs/specs/<slug>/` before implementation.
- Keep `.agents/plan.md` session-local; do not duplicate full project specs or task lists there.
- Commit only when the user or project policy asks for it. Push only when explicitly requested or when established project workflow clearly requires it.

For non-trivial work that should survive the current session, use:
- `docs/specs/<slug>/spec.md` for durable goals, constraints, approach, and acceptance.
- `docs/specs/<slug>/tasks.md` for long-lived execution steps when the work is multi-stage.
- `docs/specs/_templates/` for reusable project templates.

For multi-stage work, use an Execution Contract in the spec so the agent continues to the next validated phase until the stop rule is triggered.
'@

    $files[".agents/AGENTS.md"] = @'
# Project Agent Guide

## Scope
This repository uses project-level `.agents` memory files.
Use this file as the primary working guide for agent sessions.

## Project Language Policy
Project memory language: English.

Project engineering memory for this project should be written in English by default.
Keep file names, directory names, Markdown field labels, commands, paths, API names, and raw error text in English or in their original form.
Keep public-facing artifacts in the language required by their target repository or audience.

## Working Philosophy
You are an engineering collaborator on this project, not a standby assistant.

- Prefer complete, coherent, reviewable units of work.
- Make routine reversible implementation decisions yourself, then validate them.
- Keep progress updates concise and useful, following the active runtime and user instructions for status reporting.
- At delivery time, explain what changed, why, how it was checked, and any tradeoffs.

## What You Submit To
Do not let this file override higher-priority system, runtime, safety, or explicit user instructions.

For project-local decisions, use this priority order:

1. **The user's explicit, unambiguous instructions and completion criteria** - the requested outcome works, relevant validation passes, and the requested artifact exists.
2. **Safety, reversibility, access, and environment constraints** - destructive operations, external writes, credentials, production systems, and high-impact actions require care or confirmation.
3. **The project's existing style and patterns** - established by reading the existing code and local memory.
4. **Shared defaults from this template and the global hub** - useful starting points, not hard constraints over local project reality.

Respect is shown by making sound engineering decisions, surfacing assumptions clearly, and escalating only when ambiguity, risk, or project policy requires it.

## On Stopping to Ask
There are a small number of legitimate reasons to stop and ask the user:

- Genuine ambiguity where continuing would produce output contrary to the user's intent
- Irreversible or high-impact actions such as destructive operations, force-pushes, production changes, or writes to external systems
- Explicit project or environment constraints that require approval, sequencing, credentials, or access you do not have

Illegitimate reasons include:

- Asking about reversible implementation details. Make a reasonable choice, proceed, and adjust if evidence shows it was wrong
- Asking "should I do the next step" - if the next step is part of the task, do it
- Dressing up a style choice you could have made yourself as "options for the user"
- Ending with routine follow-up questions when the next step was already part of the requested work

## Ambiguous Task Gate
When the user's request is semantically broad or underspecified, do a short read-only exploration pass before editing. Examples include "optimize this", "clean this up", "migrate this", "fix the workflow", "look for problems", or requests without clear acceptance criteria.

After exploration, proceed only when the goal, scope, non-goals, and validation path are clear. Ask a concise question when ambiguity is about product intent, success criteria, destructive/high-impact actions, external systems, or incompatible interpretations. Make reversible implementation choices yourself once intent is clear.

Scope discipline: do not fold unrelated refactors, cleanup, or behavior changes into a work item unless they are explicit goals. If acceptance checks are skipped or unavailable, record that before claiming completion.

## Delivery Protocol & Working Loop
For implementation tasks that produce repository changes, a complete unit of work may include the relevant parts of the following sequence:

1. **Read & Plan**: Read relevant code and context notes. For non-trivial work, prefer a project spec under `docs/specs/<slug>/` before implementation. Keep `.agents/plan.md` as a session-local pointer, not a second project plan.
2. **Implement & Verify**: Confirm the work meets the completion criteria and passes relevant validation for this project. Implement in small validated steps. Prefer deterministic, scriptable verification commands. Record blockers in `.agents/process.txt`.
3. **Atomic Commit**: Commit only when the user asks for a commit or project policy clearly requires one. When committing in a git repository, inspect recent history with `git log` and match the repository's prevailing commit message format unless the user or project policy says otherwise.
4. **The Push**: Push only when the user explicitly asks, or when established project workflow unambiguously requires it and remote access is available.
5. **The Report**: After validation and any required commit/push steps, provide your report. If the task is review-only or blocked by environment or policy, report the blocker or findings clearly instead of pretending the task is complete.

## Tooling Constraints
- **Non-Interactive**: Do not wait for ceremonial approval before routine reversible edits. Commit and push rules still follow the Delivery Protocol.
- **Environment Aware**: When the project is a git repository, check `git status` before committing. Inspect unstaged changes with `git diff` and staged changes with `git diff --cached` to ensure no unintended files or hunks are included.

## Context Load Order
1. This file and root `AGENTS.md`
2. Hot memory: `.agents/process.txt` and `.agents/plan.md`
3. Warm memory: active `docs/specs/<slug>/spec.md` and `tasks.md`
4. Cold memory: `.agents/context/*` and `.agents/notes.md`, opened only by matching summary/keywords or task relevance

## Project Work Packages
For work that should remain discoverable after the current session, store the canonical description under `docs/specs/`:
- `docs/specs/<slug>/spec.md`: durable work definition, constraints, approach, and acceptance
- `docs/specs/<slug>/tasks.md`: durable implementation checklist when multi-step execution is needed

Do not create `docs/specs/<slug>/plan.md`.
Do not duplicate full `spec.md` or `tasks.md` contents into `.agents/plan.md`.

For multi-phase work, write an Execution Contract in `spec.md`: autonomy level, phase list, continue rule, stop rule, and state record. If the continue rule passes after a phase, update state and continue to the next phase. Stop only when the stop rule is triggered.

## Memory Routing
- Stable technical facts: `.agents/context/tech/`
- Business or product rules: `.agents/context/business/`
- Repeated pitfalls and fixes: `.agents/context/experience/`
- Structured troubleshooting cases: `.agents/context/experience/cases/`
- Session status: `.agents/process.txt`
- Confirmed decisions and proof: `.agents/notes.md`
- Durable project work packages: `docs/specs/`

Non-template context files should include `## Summary` and `## Keywords` near the top so agents can discover relevant memory without preloading the full directory.
'@

    $files[".agents/process.txt"] = @'
Current State
- Project memory language: English.
- Update this at session end.
- Keep this focused on active status and blockers.

Completed
- Add completed milestones here.

Next Actions
- Add immediate next steps here.

Blocking Issues
- Add only active blockers.

Last Updated
- YYYY-MM-DD
'@

    $files[".agents/plan.md"] = @'
# Active Plan

Project memory language: English.

Active Spec
- `docs/specs/<slug>/spec.md` or `none`

Current Task
- `Txx` or `none`

This Session
- [ ] Add 3-5 immediate session steps here
'@

    $files[".agents/notes.md"] = @'
# Confirmed Notes

Project memory language: English.

- Record verified facts only.
- Include evidence source where possible.
'@

    $files[".agents/commands/README.md"] = @'
# Commands Folder

Project memory language: English.

Use this folder for reusable high-frequency workflows.

Examples:
- build workflow
- review checklist
- release checklist
'@

    $files[".agents/context/README.md"] = @'
# Context Routing

Project memory language: English.

Use this folder as the long-term memory base.

- `tech/`: architecture, modules, build/deploy details, environment notes
- `business/`: product logic, state machines, domain rules
- `experience/`: pitfalls, incidents, fixes, and reusable playbooks

Progressive disclosure rule: keep non-template context files discoverable with `## Summary` and `## Keywords` near the top. Agents should read README/index files first, then open only matching context entries.
'@

    $files[".agents/context/tech/README.md"] = @'
# Tech Context

Project memory language: English.

Store durable technical knowledge here.

Suggested sections:
1. Background
2. Constraints
3. Decision
4. Verification
'@

    $files[".agents/context/business/README.md"] = @'
# Business Context

Project memory language: English.

Store product rules and domain behavior here.

Suggested sections:
1. Rule
2. Inputs
3. Expected behavior
4. Edge cases
'@

    $files[".agents/context/experience/README.md"] = @'
# Experience Context

Project memory language: English.

Store recurring pitfalls and proven fixes here.

Keep each entry concise:
1. Problem
2. Root Cause
3. Fix
4. Verification
5. Prevention rule
'@

    $files[".agents/context/experience/cases/README.md"] = @'
# Troubleshooting Cases

Project memory language: English.

Structured case files for complex or recurring issues.

## When to Use
- Issue required significant root cause analysis
- Fix involved non-obvious steps or workarounds
- Issue is likely to recur in this or similar projects

## Format
Use `case_template.md` for new cases. Each case file should have:
- **Keywords** for index search matching
- **Symptoms** with exact error text
- **Root Cause** with code/config references
- **Prevention Rule** that can be checked automatically

## Searching
When troubleshooting, scan filenames and Keywords sections in this directory for matches against error text or module names.
'@

    $files[".agents/context/experience/cases/case_template.md"] = @'
# [Problem Title]

Project memory language: English.

## Summary
[One or two sentences describing the reusable lesson and when it applies]

## Keywords
[keyword1], [keyword2], [keyword3]

## Symptoms
- **Error message / observable behavior**: [exact error text or phenomenon]
- **Trigger condition**: [when / how it occurs]

## Root Cause
[Analysis referencing specific code locations or configurations]

## Fix
[Steps or changes applied to resolve the issue]

## Verification
[Commands or methods to confirm the fix works]

## Prevention Rule
[Actionable rule that can prevent recurrence]

## Scope
- **Scope**: Project-specific
- **Global candidate**: No
- **Date**: YYYY-MM-DD
'@

    $files["docs/specs/README.md"] = @'
# Project Specs

Project memory language: English.

Use this directory for long-lived work packages that should survive the current agent session.

Recommended structure:
- `docs/specs/<slug>/spec.md`
- `docs/specs/<slug>/tasks.md`
- `docs/specs/_templates/`

Rules:
- `spec.md` is the canonical work definition.
- `tasks.md` is optional and should exist only for multi-step work.
- Do not create `plan.md` here; `.agents/plan.md` already covers session-local planning.
- When work must repeat until a condition is satisfied, define the watched variable, check command, pass predicate, limits, and abort conditions in `spec.md` before running the loop.
'@

    $files["docs/specs/_templates/spec-lite.md"] = @'
# Work Spec

Project memory language: English.

- **Title**:
- **Slug**:
- **Status**: Draft / Active / Done / Archived
- **Owner**:
- **Updated**:

## 1. Summary
- What is being built, changed, or investigated?

## 2. Current Context
- Relevant code paths, binaries, documents, artifacts, or observed behavior
- Existing implementation facts already confirmed

## 3. Goals
- Clear completion outcomes

## 4. Non-Goals
- Explicit boundaries for this work item

## 5. Constraints
- Environment, compatibility, tooling, time, safety, or interface constraints
- Scope control: do not include unrelated refactors, cleanup, or behavior changes unless they are explicit goals.

## 6. Assumptions
- Assumptions being made pending proof

## 7. Risks
- What may fail or require fallback

## 8. Proposed Approach
- Planned direction, implementation outline, or analysis method

## 9. Acceptance / Evidence
- How the result will be validated
- What proof or output should exist when done
- How skipped or unavailable acceptance checks will be recorded before claiming completion

## 10. Loop Contract
- Use only when execution must repeat until a variable or condition is satisfied.
- **Variable**:
- **Source of truth**:
- **Check command**:
- **Pass predicate**:
- **Iteration action**:
- **State record**:
- **Limits**:
- **Abort conditions**:

## 11. Execution Contract
- Use for multi-phase work where the agent should continue after each validated phase.
- **Autonomy level**: ask-before-each-phase / autonomous-until-blocked / bounded-autonomous
- **Phase list**:
  - P01:
  - P02:
  - P03:
- **Continue rule**:
- **Stop rule**: include scope drift, unrelated refactor pressure, skipped acceptance checks, safety/permission blockers, and unresolved ambiguity.
- **State record**:

## 12. Open Questions
- Unresolved issues that may block or reshape execution
'@

    $files["docs/specs/_templates/tasks-lite.md"] = @'
# Task Plan

Project memory language: English.

- **Spec**:
- **Status**: Draft / Active / Done
- **Updated**:

## Tasks

- [ ] T01: Describe the first concrete step
  - Scope:
  - Validation:
  - Notes:

- [ ] T02: Describe the next concrete step
  - Scope:
  - Validation:
  - Notes:

## Task-to-Spec Notes
- Record any important mapping, assumptions, or dependencies here.

## Conditional Loop Tasks
- Use only when the active spec includes a Loop Contract.
- [ ] L01: Check current variable value before acting
  - Source of truth:
  - Observed value:
  - Pass predicate:
- [ ] L02: Run one bounded iteration action
  - Scope:
  - Safety / idempotency notes:
- [ ] L03: Recheck, update state, and decide whether to stop or repeat
  - Iteration:
  - Latest value:
  - Stop / repeat decision:
  - Abort reason, if any:

## Execution Contract Tasks
- Use when the active spec includes an Execution Contract.
- [ ] P01: Complete phase 1 and record validation
  - Goal:
  - Inputs:
  - Outputs:
  - Validation:
  - Continue / stop decision:
- [ ] P02: Complete phase 2 and record validation
  - Goal:
  - Inputs:
  - Outputs:
  - Validation:
  - Continue / stop decision:
- [ ] P03: Complete phase 3 and record validation
  - Goal:
  - Inputs:
  - Outputs:
  - Validation:
  - Continue / stop decision:
'@

    return $files
}

function Get-ChineseScaffold {
    $files = [ordered]@{}

    $files["AGENTS.md"] = @'
# AGENTS.md

项目级 agent 入口。

主要说明位于 `.agents/AGENTS.md`。每次非平凡任务开始时，先读取该文件，再计划或编辑。若 runtime 没有自动加载嵌套说明，本根文件就是 fallback contract。

项目记忆语言：简体中文。

每次实质会话的最低读取顺序：
1. `.agents/AGENTS.md`
2. `.agents/context/`
3. `.agents/process.txt`
4. `.agents/plan.md`，仅非平凡任务需要

即使 `.agents/AGENTS.md` 未加载，也适用以下核心规则：
- 系统、runtime 和用户明确指令优先于项目默认值。
- 常规可逆实现选择由 agent 自行判断；遇到真实歧义、破坏性动作、外部写入、缺失凭据或 policy / safety 风险时停止。
- 对宽泛或范围不清的请求，先做只读探索；必要时再澄清目标、范围和验证方式。
- 非平凡工作优先在 `docs/specs/<slug>/` 下建立 lightweight work package。
- `.agents/plan.md` 保持会话本地，不要复制完整项目 specs 或任务清单。
- 只有用户或项目策略要求时才 commit。只有用户明确要求，或既有项目流程明确要求时才 push。

需要在当前会话后保留的非平凡工作，使用：
- `docs/specs/<slug>/spec.md`：持久目标、约束、方案和验收。
- `docs/specs/<slug>/tasks.md`：多阶段工作需要的长期执行步骤。
- `docs/specs/_templates/`：可复用项目模板。

多阶段工作应在 spec 中使用 Execution Contract，使 agent 在 stop rule 触发前持续推进到下一个已验证阶段。
'@

    $files[".agents/AGENTS.md"] = @'
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

## 交付流程
产生仓库变更的实现任务，完整工作单元通常包含以下步骤中的相关部分：

1. **读取与计划**：读取相关代码和上下文记录。非平凡工作优先在 `docs/specs/<slug>/` 下建立项目 spec。`.agents/plan.md` 只作为会话级指针，不复制完整项目计划。
2. **实现与验证**：确认工作满足完成标准，并通过项目相关验证。以小步可验证方式实现，优先使用确定性、可脚本化的验证命令。阻塞写入 `.agents/process.txt`。
3. **原子提交**：只有当用户要求提交，或项目流程明确要求提交时才 commit。提交前检查 `git log`，遵循仓库既有 commit message 风格，除非用户或项目规则另有要求。
4. **推送**：只有当用户明确要求，或项目流程明确要求且远端可访问时才 push。
5. **报告**：完成验证以及必要的 commit / push 后再汇报。若任务只是 review 或被环境/规则阻塞，清楚报告阻塞或发现，不能假装完成。

## 工具约束
- **非交互优先**：不要为了常规可逆编辑等待仪式性确认。commit 和 push 仍遵守交付流程。
- **环境感知**：在 git 仓库中，提交前检查 `git status`。使用 `git diff` 和 `git diff --cached` 检查未暂存与已暂存变更，确认没有纳入意外文件或 hunk。

## 上下文加载顺序
1. 本文件和根目录 `AGENTS.md`。
2. 热记忆：`.agents/process.txt` 和 `.agents/plan.md`。
3. 温记忆：当前 `docs/specs/<slug>/spec.md` 和 `tasks.md`。
4. 冷记忆：`.agents/context/*` 和 `.agents/notes.md`，只在摘要、关键词或任务相关时打开。

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
'@

    $files[".agents/process.txt"] = @'
当前状态
- 项目记忆语言：简体中文。
- 会话结束时更新这里。
- 本文件只记录当前状态、阻塞和下一步。

已完成
- 在这里添加已完成的里程碑。

下一步
- 在这里添加直接可执行的下一步。

阻塞
- 只记录仍然存在的阻塞。

最后更新
- YYYY-MM-DD
'@

    $files[".agents/plan.md"] = @'
# 当前计划

项目记忆语言：简体中文。

当前 Spec
- `docs/specs/<slug>/spec.md` 或 `none`

当前任务
- `Txx` 或 `none`

本次会话
- [ ] 在这里添加 3-5 个直接会话步骤
'@

    $files[".agents/notes.md"] = @'
# 已确认记录

项目记忆语言：简体中文。

- 只记录已经验证的稳定事实。
- 尽量写明证据来源。
'@

    $files[".agents/commands/README.md"] = @'
# 命令目录

项目记忆语言：简体中文。

此目录用于沉淀高频、可复用的工作流命令。

示例：
- build workflow
- review checklist
- release checklist
'@

    $files[".agents/context/README.md"] = @'
# 上下文路由

项目记忆语言：简体中文。

此目录是长期项目记忆入口。

- `tech/`：架构、模块、构建/部署细节、环境说明。
- `business/`：产品逻辑、状态机、领域规则。
- `experience/`：踩坑、事故、修复和可复用 playbook。

渐进读取规则：非模板 context 文件应在靠前位置包含 `## Summary` 和 `## Keywords`，方便 agent 先读 README / index，再只打开匹配的上下文条目。
'@

    $files[".agents/context/tech/README.md"] = @'
# 技术上下文

项目记忆语言：简体中文。

在这里记录稳定的技术知识。

建议章节：
1. Background
2. Constraints
3. Decision
4. Verification
'@

    $files[".agents/context/business/README.md"] = @'
# 业务上下文

项目记忆语言：简体中文。

在这里记录产品规则和领域行为。

建议章节：
1. Rule
2. Inputs
3. Expected behavior
4. Edge cases
'@

    $files[".agents/context/experience/README.md"] = @'
# 经验上下文

项目记忆语言：简体中文。

在这里记录重复踩坑和已验证修复。

每条经验保持简洁：
1. Problem
2. Root Cause
3. Fix
4. Verification
5. Prevention rule
'@

    $files[".agents/context/experience/cases/README.md"] = @'
# 排障案例

项目记忆语言：简体中文。

此目录保存复杂或高复发问题的结构化案例。

## 使用场景
- 问题需要较多 root cause analysis。
- 修复包含不明显的步骤或 workaround。
- 问题可能在本项目或相似项目中再次出现。

## 格式
新案例使用 `case_template.md`。每个案例文件应包含：
- **Keywords**：用于索引匹配。
- **Symptoms**：保留准确错误文本。
- **Root Cause**：引用具体代码或配置。
- **Prevention Rule**：可执行或可检查的预防规则。

## 搜索
排障时先用错误文本、模块名或工具名扫描文件名和 Keywords。
'@

    $files[".agents/context/experience/cases/case_template.md"] = @'
# [Problem Title]

项目记忆语言：简体中文。

## Summary
[一到两句话说明这条可复用经验及适用场景]

## Keywords
[keyword1], [keyword2], [keyword3]

## Symptoms
- **Error message / observable behavior**: [exact error text or phenomenon]
- **Trigger condition**: [when / how it occurs]

## Root Cause
[说明根因，并引用具体代码位置或配置]

## Fix
[列出解决步骤或变更]

## Verification
[列出验证命令或确认方法]

## Prevention Rule
[可执行的预防规则]

## Scope
- **Scope**: Project-specific
- **Global candidate**: No
- **Date**: YYYY-MM-DD
'@

    $files["docs/specs/README.md"] = @'
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
'@

    $files["docs/specs/_templates/spec-lite.md"] = @'
# 工作说明

项目记忆语言：简体中文。

- **Title**:
- **Slug**:
- **Status**: Draft / Active / Done / Archived
- **Owner**:
- **Updated**:

## 1. 摘要
- 本次要构建、修改或调查什么？

## 2. 当前上下文
- 相关代码路径、二进制、文档、产物或观察到的行为。
- 已确认的现有实现事实。

## 3. 目标
- 清晰列出完成结果。

## 4. 非目标
- 明确本工作项不覆盖的边界。

## 5. 约束
- 环境、兼容性、工具、时间、安全或接口约束。
- 范围控制：不要纳入目标之外的无关重构、清理或行为变更。

## 6. 假设
- 尚待证实但当前用于推进的假设。

## 7. 风险
- 可能失败或需要 fallback 的事项。

## 8. 方案
- 计划方向、实现轮廓或分析方法。

## 9. 验收与证据
- 如何验证结果。
- 完成时应留下什么证据或输出。
- 如果验收检查被跳过或暂不可用，必须先记录原因，再声明完成。

## 10. 循环契约
- 只在需要重复执行直到变量或条件满足时使用。
- **Variable**:
- **Source of truth**:
- **Check command**:
- **Pass predicate**:
- **Iteration action**:
- **State record**:
- **Limits**:
- **Abort conditions**:

## 11. 执行契约
- 多阶段工作需要 agent 在每个已验证阶段后继续时使用。
- **Autonomy level**: ask-before-each-phase / autonomous-until-blocked / bounded-autonomous
- **Phase list**:
  - P01:
  - P02:
  - P03:
- **Continue rule**:
- **Stop rule**: 包含 scope drift、unrelated refactor、skipped acceptance checks、安全/权限阻塞和无法消解的真实歧义。
- **State record**:

## 12. 开放问题
- 仍可能阻塞或改变执行方向的问题。
'@

    $files["docs/specs/_templates/tasks-lite.md"] = @'
# 任务计划

项目记忆语言：简体中文。

- **Spec**:
- **Status**: Draft / Active / Done
- **Updated**:

## 任务

- [ ] T01：描述第一个具体步骤
  - Scope:
  - Validation:
  - Notes:

- [ ] T02：描述下一个具体步骤
  - Scope:
  - Validation:
  - Notes:

## Task-to-Spec 说明
- 在这里记录重要映射、假设或依赖。

## 条件循环任务
- 仅在 active spec 包含 Loop Contract 时使用。
- [ ] L01：执行前检查当前变量值
  - Source of truth:
  - Observed value:
  - Pass predicate:
- [ ] L02：运行一个有边界的 iteration action
  - Scope:
  - Safety / idempotency notes:
- [ ] L03：复查、更新状态，并决定停止或重复
  - Iteration:
  - Latest value:
  - Stop / repeat decision:
  - Abort reason, if any:

## 执行契约任务
- active spec 包含 Execution Contract 时使用。
- [ ] P01：完成 phase 1 并记录验证
  - Goal:
  - Inputs:
  - Outputs:
  - Validation:
  - Continue / stop decision:
- [ ] P02：完成 phase 2 并记录验证
  - Goal:
  - Inputs:
  - Outputs:
  - Validation:
  - Continue / stop decision:
- [ ] P03：完成 phase 3 并记录验证
  - Goal:
  - Inputs:
  - Outputs:
  - Validation:
  - Continue / stop decision:
'@

    return $files
}

$ProjectDirFull = [System.IO.Path]::GetFullPath($ProjectDir)
if (-not (Test-Path -LiteralPath $ProjectDirFull)) {
    throw "Project directory does not exist: $ProjectDirFull"
}

$resolved = Resolve-ProjectLanguage -Language $ProjectLanguage
$scaffold = if ($resolved.code -eq "zh-CN") {
    Get-ChineseScaffold
} else {
    Get-EnglishScaffold
}

$written = 0
$skipped = 0
foreach ($relativePath in $scaffold.Keys) {
    $result = Set-TextFile -RelativePath $relativePath -Content $scaffold[$relativePath]
    if ($result -eq "written") {
        $written++
    } else {
        $skipped++
    }
}

$resultData = [ordered]@{
    schema_version = 1
    project_dir = $ProjectDirFull
    project_language = $resolved.code
    language_label = $resolved.label
    marker = $resolved.marker
    overwrite_scaffold = [bool]$OverwriteScaffold.IsPresent
    files_written = $written
    files_skipped = $skipped
}

$resultData | ConvertTo-Json -Depth 4
