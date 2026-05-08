---
name: project-context-gate
description: Load and refresh repository-level agent instructions before non-trivial project work. Use before starting implementation, debugging, migration, research, or multi-file edits in a repository; at phase boundaries after a commit when continuing; after context compaction/resume; and after user corrections that change project rules. Reads AGENTS.md, .agents/AGENTS.md, .agents/context, process.txt, plan.md, and active docs/specs files when present.
category: kernel
stability: stable
scope: cross-project
---

# Project Context Gate

## Purpose
Make project guidance an explicit gate instead of passive background context. Use this skill to rebuild the working constraints for the current repository before planning, implementation, verification, or the next phase of a long task.

## Gate Types

### Start Gate
Run before any non-trivial repository task.

### Phase Gate
Run after completing and committing a phase when continuing to another phase.

### Resume Gate
Run after context compaction, interruption, long pause, or a user correction that changes project rules.

## Trigger Discipline

Use this gate for meaningful repository context changes, not for every tool call.

Run the gate when:

- starting a new non-trivial repository task or switching to a different objective
- entering implementation/debugging/research/migration work after a purely conversational exchange
- starting memory governance or any edit to `.agents/` project memory
- continuing after a commit into a new phase or follow-up task
- resuming after context compaction, interruption, long pause, or user correction to project rules
- crossing repositories, toolchains, or ownership boundaries

You may reuse the already-loaded context instead of re-running the gate when all of these are true:

- the current turn is a continuous part of the same objective
- the gate was already run in this conversation for that objective
- no commit, context compaction, long pause, user correction, repository switch, or active spec change happened since
- the next action is a narrow continuation such as reading nearby files, applying a small patch, running validation, or answering a question from the just-loaded context

Do not run the gate mechanically before every search, edit, validation command, or commit. If a commit concludes the task and no further phase will continue, a final status check is enough; run a phase gate only when work continues after that commit.

## Workflow

### Step 1: Inventory
Prefer running the helper when available:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/context_gate.ps1 -ProjectRoot <repo-root>
```

On non-Windows systems, or when PowerShell 7+ is already available, replace
`powershell -NoProfile -ExecutionPolicy Bypass -File` with
`pwsh -NoProfile -File`.

Run the command from the `project-context-gate` skill directory, or specify the full path to the script.
The skill is typically installed under the global agent home (`%USERPROFILE%\.agents\skills\project-context-gate\`) or the active agent's synchronized skills directory.

If the helper is unavailable, manually check the same paths.

Useful flags:
- `-Json`: emit a structured payload for automation or compact summaries.
- `-IncludeTemplates`: include every `.agents/context/` file, including templates, for audits.

### Step 2: Load Context Progressively
Read existing files by disclosure tier:

1. Hot: root `AGENTS.md`, `.agents/AGENTS.md`, `.agents/process.txt`, `.agents/plan.md`
2. Warm: active `docs/specs/<slug>/spec.md` and `tasks.md` referenced by process or plan files
3. Cold: `.agents/context/` README/index files and `.agents/notes.md`; open specific context entries only when the current task keywords match

Skip missing files without treating them as errors.

Do not preload all project memory. Token use is controlled mostly by the project memory layout and what the agent chooses to open, not by this gate itself.

### Step 3: Produce a Constraint Capsule
Before continuing work, summarize the current task constraints in a few lines:

- Current objective or active spec
- Current phase or task
- Project-specific rules that affect this task
- Commit, push, and validation rules
- Known blockers, risks, or required user actions

Use the capsule to guide the next implementation or verification step. Keep it short enough to refresh repeatedly during long sessions.

### Step 4: Re-run at Boundaries
Repeat this gate:

- after a phase commit if more phases remain
- after context compaction or resume
- after the user corrects a project rule or workflow assumption
- before committing if the task crossed repositories or toolchains and the loaded context may be stale

## Fallback Rule for Other Skills
When another skill wants to use this gate but it is not installed, that skill must perform Step 2 and Step 3 manually. Do not fail the parent workflow only because this skill is unavailable.

## Output Contract
When using this skill, report:

1. Which gate was run: `start`, `phase`, or `resume`
2. Which hot/warm/cold context files were listed or loaded
3. The constraint capsule
4. Any unresolved ambiguity that blocks safe execution
