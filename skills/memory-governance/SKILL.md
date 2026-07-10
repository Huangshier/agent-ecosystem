---
name: memory-governance
description: Normalize and maintain Agent memory files after implementation sessions, and extract reusable lessons from corrected errors. Use when you need to clean or update `.agents/notes.md`, `.agents/process.txt`, `.agents/plan.md`, or `.agents/context/*`; when memory files are bloated or duplicated; when you want stable facts separated from session logs; when you want a standardized next-session kickoff message; when refresh, upgrade, or language migration work touches project memory; or when you want to reflect on session errors and deposit prevention rules.
category: kernel
stability: stable
scope: cross-project
metadata:
  category: kernel
  stability: stable
  scope: cross-project
compatibility: Bundled scripts require PowerShell 7+. The metadata map is an additive compatibility layer; top-level category, stability, and scope aliases remain supported.
---

# Agent Memory Governance

## Objective
Keep project memory concise, consistent, and reusable across sessions.
When a project uses `docs/specs/`, treat those files as the canonical long-lived work package and keep `.agents` as session-local memory.

Use progressive disclosure:
- Hot memory: `.agents/process.txt` and `.agents/plan.md`; small enough to read during each context gate.
- Warm memory: active `docs/specs/<slug>/spec.md` and `tasks.md`; read only for the active work package.
- Cold memory: `.agents/context/*`, `.agents/notes.md`, and global experience; discover by summary/keywords and open only when relevant.
- Memory-scope tasks should also list `docs/specs/**/spec.md`,
  `docs/specs/**/tasks.md`, and `docs/specs/**/research.md` so non-active
  long-lived work packages can be matched without preloading every body.

## Refresh, Migration, And Reset Handoff

Requests to refresh project memory, upgrade memory templates, migrate memory
language, 刷新旧工程记忆, 升级工程记忆模板, or 迁移工程记忆语言 are not ordinary
bulk-edit tasks.

- Run `project-context-gate` first, then use `project-bootstrap` for the
  proposal-first and backup-first workflow.
- Do not hand-edit `.agents/**` in bulk and declare a refresh or migration
  complete. Preserve customized project memory unless a reviewed proposal says
  otherwise.
- Treat refresh or template upgrade as preservation-oriented: update missing or
  unmodified scaffold surfaces, and route modified project-specific content to
  review.
- Treat language migration as template replacement plus reviewed
  target-language narrative, with commands, paths, APIs, filenames, raw errors,
  and code symbols preserved in their original form.
- Treat reset or reinitialize as destructive only when the user explicitly says
  old memory can be discarded, such as "do not keep old project memory" or
  "重新初始化工程记忆，不保留旧内容".

## Operating Model
Apply this routing model every time:

1. `notes.md`:
- Keep only stable, reusable, verified conclusions.
- Remove session-by-session narration and temporary reasoning.
- Keep current policy, final decisions, and lasting architecture facts.
- Do not mirror the full contents of an active `docs/specs/<slug>/spec.md`; record only durable conclusions or references back to the spec.

2. `process.txt`:
- Keep only current operational status.
- Include: current state, last session update, blockers, next actions, last updated.
- Remove historical chronology once decisions are stabilized in `notes.md`.
- When an active spec exists, keep only status and pointer information here, not a second execution checklist.

3. `plan.md`:
- Keep task checklist state only.
- Mark completed/pending/deferred clearly.
- Do not duplicate technical deep-dives from `notes.md`.
- If `docs/specs/<slug>/tasks.md` exists, keep `.agents/plan.md` limited to the active spec path, current task id, and session-local next steps.

4. `.agents/context/*`:
- Store durable domain knowledge by category (`tech`, `business`, `experience`).
- Move broad, reusable facts from session artifacts into context files when repeated.
- Add `## Summary` and `## Keywords` near the top of non-template context files so agents can discover relevant entries without preloading the full directory. Tooling also recognizes localized equivalents for project memory while public templates remain English-first.
- Keep project-specific experience local by default.
- Promote only cross-project toolchain/host/workflow lessons into the global knowledge hub when they can be stated as stable prevention rules.
- When a lesson becomes a global hub candidate, mark it locally and point to the installed `knowledge-hub/scripts` promotion workflow; `memory-governance` does not mutate the global hub by itself.
- A marked local lesson may be collected into an explicit runtime candidate inbox with `knowledge-hub/scripts/manage_candidates.ps1`. Candidate intake is a separate review lifecycle and does not call `promote_experience.ps1` or write `knowledge/experience/**`.

## Directory Index Maintenance

- When creating or moving an indexed entry, update its parent directory index
  in the same change.
- When an entry is completed, deprecated, archived, or changes responsibility,
  update its status or remove it from the parent directory index.
- Update `Last reviewed` only after actually checking the indexed content.
- Keep indexes limited to current, public-safe facts that can be maintained over
  time.
- Do not automatically create or rewrite directory indexes. The opt-in
  `directory_missing_index` diagnosis from phase 1 is a warning and recommendation only; it does not authorize writes.

## Workflow
Follow this exact sequence:

0. Run a project context gate before memory edits when available. Prefer `project-context-gate`; if it is unavailable, manually load hot memory first: root `AGENTS.md`, `.agents/AGENTS.md`, `.agents/process.txt`, `.agents/plan.md`, referenced active `docs/specs` files, then `.agents/context/` discovery files and `.agents/notes.md` only as needed. Summarize the active objective, phase, memory routing rules, and commit expectations before editing.

1. Read current memory files in this order:
- `.agents/AGENTS.md`
- `.agents/process.txt`
- `.agents/plan.md`
- `.agents/notes.md`
- `.agents/context/` discovery files first, then specific context entries that match the cleanup or learning-deposit task
- `.agents/commands/` discovery files when command guidance is part of the
  memory-scope task
- `docs/specs/**/spec.md`, `docs/specs/**/tasks.md`, and
  `docs/specs/**/research.md` as a discovered file list; read only the active
  work package and non-active work packages whose slug, Summary, Keywords, or
  task relevance match the current memory change

2. If `.agents/process.txt` or `.agents/plan.md` points to an active `docs/specs/<slug>/spec.md` or `tasks.md`, read those referenced files before rewriting memory.

3. Diagnose memory quality:
- Find duplicated information across `notes/process/plan`.
- Find stale items that contradict current code state.
- Find content in wrong file by routing model.
- Detect when `.agents` has become a second copy of active `docs/specs/` content.
- Prefer the helper when available:
  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/memory_diagnose.ps1 -ProjectRoot <repo-root>
  ```
  Use `pwsh -NoProfile -File` with the same arguments on non-Windows systems or when PowerShell 7+ is already available. Use `-Json` for structured output.

4. Refactor by destination:
- Compress `notes.md` to stable facts.
- Compress `process.txt` to active status snapshot.
- Update `plan.md` checklist and phase status.
- Move durable cross-session knowledge into `.agents/context/*` when needed.
- If an experience item is primarily about shell behavior, build systems, toolchains, caches, ports, permissions, path handling, or other cross-project workflow failures, treat it as a global experience candidate rather than duplicating it into many projects.
- Do not preload global experience into project memory; rely on lightweight project rules that trigger on-demand lookup from the global experience index.
- If the user wants that candidate promoted immediately, run or point to the installed `knowledge-hub/scripts/promote_experience.ps1` workflow rather than duplicating promotion logic inside memory cleanup.
- If the user wants cross-project comparison before promotion, use `manage_candidates.ps1 -Mode Intake` with explicit project roots, explicit languages, and an explicit `<runtime>/state/knowledge-candidates/` path. Project-root scanning is read-only and is intended for legacy import or recovery; normal discovery starts from the inbox.

5. Consistency check:
   - Version labels and branch status should not conflict across files.
   - Decisions in `notes.md` must match `plan.md` and current code.
   - `process.txt` should not reintroduce archived detail.
   - Active `docs/specs/` files and `.agents` pointers should agree on the current work item.
   - For project-memory language work, check the relevant hot memory, notes,
     context cards, commands, and long-lived work packages for language-policy
     consistency. Record intentional exceptions instead of silently translating
     or dropping project-specific content.

5a. Cross-repository closeout guardrail:
   - Before writing outside the current repository, confirm the target
     repository root and the specific public issue, spec, or pull request that
     authorizes that write scope.
   - Public repository writes require explicit public scope authorization. A
     private retrospective, migration closeout, or multi-repository cleanup
     does not by itself authorize new public repository files.
   - If a public worktree is unexpectedly dirty during a private or
     multi-repository closeout, report the changed paths and the suspected
     source first. Do not commit, promote, or expand those changes until the
     public scope is confirmed.
   - Cross-project skill and process lessons default to the source project's
     local memory or private retrospective. Promote them into the public
     knowledge hub only through an explicit public issue/spec/PR path.
   - Keep public `knowledge-hub/templates` kernel-safe. Do not add
     domain-specific, private, authentication-material, or incubator templates
     to the public template tree by default.

6. Session Learning Extraction:
   Extract reusable lessons from errors corrected during the session.
   This step runs automatically as part of the full workflow.
   It can also be triggered independently when the user asks to reflect; in that case, skip steps 1-4 and execute only this step.

   6a. **Scan for correction events** in the current session:
   - User rejected AI output and provided the correct approach
   - AI executed a rollback or rework after a failed attempt
   - An unexpected error was diagnosed and fixed
   - A workaround was applied for a tool/environment issue

   If no correction events are found, skip to step 7.

   6b. **Classify each event** by root cause:

   | Root Cause | Signal | Deposit Target |
   |------------|--------|----------------|
   | **Project knowledge gap** | AI didn't know a project-specific convention | `.agents/context/tech/` or `experience/` |
   | **Toolchain/environment issue** | Shell, build, port, path, permissions | `.agents/context/experience/` -> consider promote |
   | **Domain knowledge gap** | AI misunderstood business logic or hardware behavior | `.agents/context/business/` |
   | **Workflow omission** | Skipped a verification step or process | `.agents/notes.md` (as stable rule) |
   | **Scope drift** | Work expanded beyond stated goals or ignored non-goals | `.agents/context/experience/` or active spec/tasks |
   | **Unrelated refactor** | Cleanup or refactor was bundled into unrelated work | `.agents/context/experience/` or active spec non-goals |
   | **Skipped acceptance** | Completion was claimed without running or recording required checks | `.agents/notes.md` plus active spec/tasks evidence |

   6c. **Generate deposit suggestions** (up to 3 items):
   For each, state:
   - Error pattern (one line)
   - Root cause category
   - Target file and proposed content
   - Whether the lesson is a candidate for global hub promotion

   6d. **Present suggestions and wait for user confirmation**:
   ```text
   Session Learning (N items)

   1. [Error pattern]
      - Root cause: Project knowledge gap
      - Target: .agents/context/tech/xxx.md (append)
      - Content: [specific prevention rule]
      - Global candidate: No

   2. [Error pattern]
      - Root cause: Toolchain issue
      - Target: .agents/context/experience/yyy.md
      - Content: [specific prevention rule]
      - Global candidate: Yes -> can promote later via knowledge-hub

   Execute which? (all / select / skip)
   ```

   6e. **Execute confirmed deposits**:
   - Write to the designated context files
   - For global hub candidates, mark them in the file header but do not auto-promote; hand off to `knowledge-hub/scripts/promote_experience.ps1` when the user is ready

7. Optional close-out outputs:
   - Generate a standardized next-session kickoff message.
   - If requested, prepare a memory-only commit.

8. Phase continuation:
   - If memory cleanup or a phase commit finishes and the user wants to continue into another stage, rerun `project-context-gate` if available.
   - If the gate skill is unavailable, manually reload root `AGENTS.md`, `.agents/AGENTS.md`, `.agents/process.txt`, `.agents/plan.md`, active `docs/specs` files, then only relevant `.agents/context/` entries and `.agents/notes.md`.

## Quality Gates
A memory update is complete only when all conditions hold:

1. `notes.md` contains stable facts only.
2. `process.txt` fits on one concise status page.
3. `plan.md` reflects the real execution state and deferred items.
4. No major duplicate blocks remain between files.
5. All statements are consistent with current repository state.
6. If `docs/specs/` is in use, `.agents` files point to it instead of duplicating it.
7. Cross-project experience is either promoted to the global hub or explicitly kept local for a repo-specific reason.
8. Session correction events have been reviewed and deposited (or explicitly skipped).
9. Any cross-repository closeout write has an explicit target repository root
   and public issue/spec/PR authorization, and unexpected public worktree
   changes were reported before promotion or commit.
10. For memory refresh, upgrade, language migration, or standardization tasks,
    relevant `docs/specs` work packages and context cards were checked for
    project-memory language consistency, or intentional exceptions were
    recorded in the active spec/tasks or handoff.

## Next-Session Kickoff Template
Use this template when the user asks for the first message of the next session:

```text
Continue task on <repo-path>, branch <branch>, baseline <commit/version>.

Load context in order:
1) `.agents/AGENTS.md`
2) `.agents/context/`
3) `.agents/process.txt`
4) `.agents/plan.md`

Current state:
- <state-1>
- <state-2>

Goals this session:
1) <goal-1>
2) <goal-2>

Constraints:
- <constraint-1>
- <constraint-2>

Deliverables:
- <validation>
- <docs update>
- <commit rule>
```

## Output Contract
When using this skill, return:

1. A short summary of what changed in memory files.
2. Any unresolved conflicts or assumptions.
3. Session learning deposit results (what was deposited, what was skipped, any global hub candidates).
4. A next-session kickoff message if requested.
