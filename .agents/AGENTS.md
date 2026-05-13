# Project Agent Guide

## Scope
This repository uses project-level `.agents` memory files.
Use this file as the primary working guide for agent sessions.

## Project Language Policy
Project engineering memory for this public repository should be written in
English by default.

Community-facing documentation is English-first. Chinese documentation may live
in `README.zh-CN.md` or under `docs/zh-CN/`.

Keep file names, directory names, Markdown field labels, commands, paths, API
names, and raw error text in English or in their original form.

Do not store private migration mappings, local machine paths, sensitive audit
findings, or personal overlay details in this repository. Those belong in the
private overlay repository.

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
- Asking "should I do the next step"—if the next step is part of the task, do it
- Dressing up a style choice you could have made yourself as "options for the user"
- Ending with routine follow-up questions when the next step was already part of the requested work

## Ambiguous Task Gate
When the user's request is semantically broad or underspecified, do a short read-only exploration pass before editing. Examples include "optimize this", "clean this up", "migrate this", "fix the workflow", "look for problems", or requests without clear acceptance criteria.

After exploration, proceed only when the goal, scope, non-goals, and validation path are clear. Ask a concise question when ambiguity is about product intent, success criteria, destructive/high-impact actions, external systems, or incompatible interpretations. Make reversible implementation choices yourself once intent is clear.

## Project Commands
Use documented project commands before inventing new ones. Discovery order:

1. Project docs such as `README.md`, `CONTRIBUTING.md`, `docs/`, and release notes.
2. Tooling surfaces such as package scripts, Makefiles, task runners, and CI workflows.
3. `.agents/commands/README.md` and any workflow cards under `.agents/commands/`.

Use `.agents/commands/` for reusable high-frequency workflows such as setup, format/lint, test, build, release validation, and review checklists. Each command card should be short and include purpose, when to use it, prerequisites, commands, expected evidence, and safety notes for external side effects.

## Large Issue Planning
For large, high-blast-radius, or multi-area issues, produce an implementation plan before editing. When the plan would create an oversized PR, propose a reviewable PR split and keep each phase tied to acceptance evidence.

## Delivery Protocol & Working Loop
For implementation tasks that produce repository changes, a complete unit of work may include the relevant parts of the following sequence:

1. **Read & Plan**: Read relevant code and context notes. For non-trivial work, prefer a project spec under `docs/specs/<slug>/` before implementation. Keep `.agents/plan.md` as a session-local pointer, not a second project plan.
2. **Implement & Verify**: Confirm the work meets the completion criteria and passes relevant validation for this project. Implement in small validated steps. Prefer deterministic, scriptable verification commands. Record blockers in `.agents/process.txt`.
3. **Atomic Commit**: Commit only when the user asks for a commit or project policy clearly requires one. When committing in a git repository, inspect recent history with `git log` and match the repository's prevailing commit message format unless the user or project policy says otherwise.
4. **The Push**: Push only when the user explicitly asks, or when established project workflow unambiguously requires it and remote access is available.
5. **The Report**: After validation and any required commit/push steps, provide your report. If the task is review-only or blocked by environment or policy, report the blocker or findings clearly instead of pretending the task is complete. The report must contain:
    * **What**: A summary of the changes.
    * **Why**: The engineering rationale.
    * **Tradeoffs**: Any compromises made.
6. **Session Wrap-up**: For substantial sessions, when the user asks for memory cleanup, handoff, reflection, or next-session preparation, use the active runtime's skill discovery mechanism to find a relevant memory-governance or session-wrap-up workflow. There is no reliable automatic session-end hook, so do not assume this step runs unless it is requested or explicitly part of the project workflow. If no suitable workflow is available, manually update `.agents/process.txt`, record confirmed findings in `.agents/notes.md`, and store reusable lessons in `.agents/context/experience/`.

## PR-Ready And Phase-Close Memory Sync Gate
Before an agent opens a pull request, marks a pull request ready for review, hands off a non-draft pull request, or closes an implementation phase, it must run a lightweight public engineering memory sync gate.

This gate is a workflow checklist, not a Git hook, repository ruleset, or branch-protection change. Ordinary intermediate commits do not require a full engineering-memory sync; update only the files needed for the work at that point.

Checklist:

1. Re-read the active `docs/specs/<slug>/spec.md` and `docs/specs/<slug>/tasks.md`.
2. Update the active spec status, phase state, acceptance evidence, and explicit non-goals when the phase result changed.
3. Update `.agents/plan.md` so it points at the real active spec and current next action, without copying the full task list.
4. Update `.agents/process.txt` when active issues, PRs, blockers, branch state, or next actions changed.
5. Update `.agents/notes.md` only for durable verified facts, final decisions, or evidence links that should survive the session.
6. Confirm no stale hosted-check, ready-for-review, or wait-for-review item still appears as active after it is complete.
7. Record hosted check results once at the relevant boundary. After a PR has been opened, do not push memory-only commits solely to refresh state or hosted-check timestamps unless explicitly approved.
8. Confirm the gate did not introduce unrelated refactors, pre-commit hooks, repository ruleset changes, or changes outside the accepted issue scope.

## Tooling Constraints
- **Non-Interactive**: Do not wait for ceremonial approval before routine reversible edits. Commit and push rules still follow the Delivery Protocol.
- **Environment Aware**: When the project is a git repository, check `git status` before committing. Inspect unstaged changes with `git diff` and staged changes with `git diff --cached` to ensure no unintended files or hunks are included.

## Delegation & Context Budget
- **Optional Capability**: If the active runtime supports sub-agents, workers, or parallel delegates, use them selectively. Do not treat delegation as the default approach.
- **Trigger Conditions**: Delegate only when a subtask is bounded, self-contained, and either can run in parallel or will materially reduce primary-context load during a long or complex task.
- **Keep The Spine Local**: Keep core design decisions, critical-path integration, final verification, and user-facing reporting in the primary agent.
- **Clear Ownership**: Assign each delegate a precise question, module, or file set. Avoid overlapping write scopes or duplicated investigation.
- **Concise Returns**: Pull back only the result, changed files, verification performed, blockers, and remaining risks. Do not import full transcripts or raw logs into the main context unless they are necessary.
- **Primary Agent Responsibility**: The primary agent remains responsible for integrating delegated work, validating correctness, and deciding what to present to the user.
- **Fallback Without Delegates**: If sub-agents are unavailable, apply the same discipline by splitting work into phases and externalizing intermediate summaries into `.agents/plan.md`, `.agents/process.txt`, or `.agents/notes.md`.

## Context Load Order
1. This file and root `AGENTS.md`
2. Hot memory: `.agents/process.txt` and `.agents/plan.md`
3. Warm memory: active `docs/specs/<slug>/spec.md` and `tasks.md`
4. Cold memory: `.agents/context/README.md` and indexes first, then only matching `.agents/context/**` entries and `.agents/notes.md` by Summary, Keywords, or task relevance

## Project Work Packages
For work that should remain discoverable after the current session, store the canonical description under `docs/specs/`:
- `docs/specs/<slug>/spec.md`: durable work definition, constraints, approach, and acceptance
- `docs/specs/<slug>/tasks.md`: durable implementation checklist when multi-step execution is needed

Do not create `docs/specs/<slug>/plan.md`.
Do not duplicate full `spec.md` or `tasks.md` contents into `.agents/plan.md`.

For multi-phase work, write an Execution Contract in `spec.md`: autonomy level, phase list, continue rule, stop rule, and state record. If the continue rule passes after a phase, update state and continue to the next phase. Stop only when the stop rule is triggered.

## Global Experience Discovery
Global experience is an optional, on-demand lookup layer for reusable cross-project lessons. Do not preload it, and do not assume it is installed on every machine.

Search the global experience index when an issue appears to come from a reusable workflow surface such as toolchains, host environment, shells, build systems, caches, ports, permissions, path handling, environment variables, or other recurring cross-project failures. The concrete trigger terms belong in the index entries, not in this template.

Lookup procedure:
1. If the configured global agent home has a `knowledge-hub/knowledge/experience/index.json` file, read it.
2. Match observed error text, tool names, and symptoms against entry `keywords` first, then `title`.
3. Open only the matched `.md` files and apply their Prevention Rule when it fits the current context.
4. If the index is missing or no entry matches, continue with normal project-local diagnosis.

When not to search: Issues that clearly depend on current repository business logic, hardware wiring, protocol implementation, or repo-specific module design.

Promotion: Store lessons locally in `.agents/context/experience/` first. Mark reviewed reusable lessons with `Global candidate: Yes` or `Scope: Cross-project reusable`. Promote to the global hub only when the root cause is toolchain/host/workflow driven, the fix is repo-independent, and it can be stated as a stable prevention rule. Use the installed `knowledge-hub/scripts/promote_experience.ps1` workflow for hub-side promotion when available.

## Global Skill Discovery
Global skills may be installed under the configured global agent home, commonly `%USERPROFILE%\.agents` on Windows or `$HOME/.agents` on Unix-like hosts, and may be synchronized into agent-specific skill directories through the soft-link sync workflow. Availability is environment-dependent; this file is not the authoritative skill list.

Skill loading procedure:
1. Prefer the active runtime's skill registry when it is available.
2. If needed, check the configured global agent home's `skills/<skill-name>/SKILL.md` or the active agent's synchronized skills directory.
3. Load only skills whose metadata or instructions match the current task, or when the user explicitly names a skill.
4. If a relevant skill is missing, continue with the best fallback and mention the missing capability only when it affects the result.

Do not maintain a hard-coded skill table here. Default installation is handled by the ecosystem installer and synchronization scripts; each skill's own `SKILL.md` owns its trigger conditions and detailed workflow.

## Memory Routing
- Stable technical facts: `.agents/context/tech/`
- Business or product rules: `.agents/context/business/`
- Repeated pitfalls and fixes: `.agents/context/experience/`
- Structured troubleshooting cases: `.agents/context/experience/cases/`
- Session status: `.agents/process.txt`
- Confirmed decisions and proof: `.agents/notes.md`
- Durable project work packages: `docs/specs/`

Non-template context files should include `## Summary` and `## Keywords` near the top so agents can discover relevant memory without preloading the full directory.
