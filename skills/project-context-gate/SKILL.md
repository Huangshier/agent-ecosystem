---
name: project-context-gate
description: Load and refresh repository-level agent instructions before non-trivial project work. Use before starting implementation, debugging, migration, research, memory refresh, memory template upgrade, project-memory language migration, or multi-file edits in a repository; at phase boundaries after a commit when continuing; after context compaction/resume; and after user corrections that change project rules. Reads AGENTS.md, .agents/AGENTS.md, .agents/context, process.txt, plan.md, and active docs/specs files when present. Also use for triggers such as 刷新旧工程记忆, 升级工程记忆模板, 迁移工程记忆语言到中文, and 迁移工程记忆语言到英文.
category: kernel
stability: stable
scope: cross-project
metadata:
  category: kernel
  stability: stable
  scope: cross-project
compatibility: Bundled scripts require PowerShell 7+. The metadata map is an additive compatibility layer; top-level category, stability, and scope aliases remain supported.
---

# Project Context Gate

## Purpose
Make project guidance an explicit gate instead of passive background context. Use this skill to rebuild the working constraints for the current repository before planning, implementation, verification, or the next phase of a long task.

The helper also performs a fail-soft, read-only project template status check. It locates `scripts/status.ps1` only from the current skill's source, copy-install, or resolved bridge path, invokes it with `-ProjectDir <resolved-root> -Json`, and exposes only validated schema-1 project status fields. It never searches the target project for a status helper and never performs refresh or migration automatically.

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
- handling memory refresh, memory template upgrade, project-memory language
  migration, 刷新旧工程记忆, 升级工程记忆模板, or 迁移工程记忆语言到中文 / 英文
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
- `-Brief`: emit a compact, copyable agent brief for human/agent handoff.
- `-IncludeTemplates`: include every `.agents/context/` file, including templates, for audits.
- `-Query "<terms>"`: perform deterministic, read-only metadata matching against
  `.agents/context/` entries. Returns `matched_context_entries` with per-entry
  `path`, `matched_fields`, and `matched_terms`. Matching is metadata-only
  (README/index table Summary/Keywords and entry front-matter `## Summary` /
  `## Keywords`); entry bodies are never read. Results are ordered by normalized
  relative path (ordinal). Matched entries have NOT been loaded, applied, or
  authorized.

All output modes include a stable `Project template status` section. JSON callers receive `project_template` with `status`, `reason`, `project_language`, `guidance`, nullable `command`, and `helper.availability` / `helper.trust`. Suggested commands are emitted only from trusted runtime helpers: `optional-refresh` may offer `bootstrap_project.ps1 -RefreshUnmodifiedTemplates` when the language is validated, while `migration-required` offers only `memory_upgrade.ps1 -Mode Analyze -Json`. Missing helpers, execution failures, malformed or incompatible payloads, and invalid fields degrade to `unknown` without failing the context inventory or exposing helper output.

### Query Matching Contract

When `-Query` is provided, the JSON payload gains incremental fields:

- `query`: the original query string.
- `matched_context_entries`: array of `{ path, matched_fields, matched_terms }`.
- `match_status`: `"matched"` or `"no-match"`.
- `match_reason_codes`: structured fail-soft reasons (e.g. `context-directory-missing`, `no-matches`, `unsafe-index-path-ignored`, `unknown-json-index-schema`).

Determinism guarantees:

- Query terms are split on whitespace, deduplicated ordinal-ignore-case, and preserve first casing.
- Matching uses ordinal-ignore-case substring comparison.
- `matched_terms` are ordered by query position; `matched_fields` use fixed order (`keywords`, `summary`).
- Results are sorted by normalized relative path using ordinal comparison.
- Output is identical across PowerShell 7 and Windows PowerShell 5.1.

Safety and fail-soft:

- Only files under `.agents/context/` are considered.
- Index entries with absolute paths, `..` segments, or paths resolving outside the context root are ignored with `unsafe-index-path-ignored`.
- Missing context directory, missing index, incomplete metadata, unknown JSON index schema, and no matches all degrade gracefully via `match_reason_codes`.
- Matched entries are metadata hits only; they are never described as loaded, applied, or authorized.

### Step 2: Load Context Progressively
Read existing files by disclosure tier:

1. Hot: root `AGENTS.md`, `.agents/AGENTS.md`, `.agents/process.txt`, `.agents/plan.md`
2. Warm: active `docs/specs/<slug>/spec.md` and `tasks.md` referenced by process or plan files
3. Cold: `.agents/context/` README/index files and `.agents/notes.md`; open specific context entries only when the current task keywords match

Skip missing files without treating them as errors.

Do not preload all project memory. Token use is controlled mostly by the project memory layout and what the agent chooses to open, not by this gate itself.

For memory refresh, memory upgrade, language migration, reset/reinitialize,
standardization, or project-memory governance tasks, expand discovery without
bulk loading:

- List `.agents/context/**` and `.agents/commands/**` discovery files first,
  then open only entries whose Summary, Keywords, filename, or task relevance
  match the work.
- List long-lived work packages under `docs/specs/**/spec.md`,
  `docs/specs/**/tasks.md`, and `docs/specs/**/research.md`.
- Read the active work package and any matching non-active work packages; do
  not preload every spec body only because the task is memory-scoped.
- Include `.agents/notes.md`, `.agents/hub.lock.json`, and project language
  declarations when language consistency or scaffold provenance is in scope.
- Classify intent before editing: refresh/upgrade preserves project-specific
  memory, language migration changes template and narrative language while
  preserving protected literals, and reset/reinitialize discards old memory only
  when explicitly requested by the user.

### Step 3: Produce a Constraint Capsule
Before continuing work, summarize the current task constraints in a few lines:

- Current objective or active spec
- Current phase or task
- Project-specific rules that affect this task
- Commit, push, and validation rules
- Known blockers, risks, or required user actions
- For memory-scoped tasks, the project-memory surfaces in scope, such as
  `.agents` hot memory, notes, context cards, commands, and `docs/specs` work
  packages.

Use the capsule to guide the next implementation or verification step. Keep it short enough to refresh repeatedly during long sessions.

When a user or runtime needs a copyable handoff artifact, use `-Brief` instead
of manually rewriting the inventory. The brief is a presentation layer over the
same context inventory. It preserves the default and `-Json` behavior, does not
read every cold context file, and does not write project memory.

### Step 3a: Verify Cross-Workspace Roots
When work crosses repositories, sibling worktrees, generated workspaces, or
private/public ownership boundaries, verify the intended root before editing:

- Resolve the active root with `git rev-parse --show-toplevel` when the target
  is a Git repository.
- Record the current branch and `git status -sb` for the target root before
  writing.
- Compare the resolved root with the user request, active spec, or tool input.
  If they disagree, stop and report the ambiguity.
- After edits, rerun `git status -sb` from the resolved target root. If a new
  nested or sibling path was created accidentally, stop and report the path
  instead of expanding the diff to include it.
- For public/private or multi-repository workflows, keep the authorization
  boundary in the constraint capsule: which repository may be written, which
  repository is read-only evidence, and which files or issue/spec/PR scope
  authorize the write.

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

The project template status is advisory. Do not execute its suggested command without the user's authorization for the corresponding project-memory change.
