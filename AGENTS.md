# AGENTS.md

Project-level agent entrypoint.

Root `.agents/` is local runtime memory for this checkout. It may exist on a
maintainer machine after bootstrap or previous agent work, but it is not a
public fact source and is not tracked by this repository.

## Project Language Policy

Project memory language: English.

The root `README.md` is the chosen Simplified Chinese repository homepage, with
`README.en.md` as the English entrypoint and `README.zh-CN.md` as a
compatibility redirect. Deeper public documentation may remain English-first
unless a file or issue explicitly targets another language. Keep commands,
paths, APIs, file names, code identifiers, and raw error text in their original
form.

## Startup Sources

At the start of any non-trivial task, read this root file first. If local
`.agents/` files exist, they may be read as checkout-local working memory in
this order:

1. `.agents/AGENTS.md`
2. `.agents/process.txt`
3. `.agents/plan.md` (for non-trivial tasks)
4. `.agents/context/README.md`, then only matching `.agents/context/**` entries by Summary, Keywords, or task relevance
5. `.agents/commands/README.md`, then only matching `.agents/commands/**` command cards when a documented workflow is relevant

Do not preload the full `.agents/context/` or `.agents/commands/` trees at startup.

If local `.agents/` files are absent or stale, use public sources instead:

- this root `AGENTS.md`
- GitHub issues and pull requests
- `docs/agent-governance.md`
- `docs/release-process.md`
- `CHANGELOG.md`
- release notes under `docs/releases/`
- curated knowledge under `knowledge-hub/knowledge/`

Core rules that apply even if `.agents/AGENTS.md` was not loaded:
- Follow system, runtime, and explicit user instructions before project defaults.
- Make routine reversible implementation choices yourself; stop for genuine ambiguity, destructive actions, external writes, missing credentials, or policy/safety risk.
- For broad or underspecified requests, do read-only exploration first, then clarify goal/scope/validation before editing when needed.
- Keep `.agents/plan.md` session-local when local runtime memory exists; do not duplicate full project specs or task lists there.
- For this public repository, use GitHub issues and PR bodies as the canonical
  maintenance record. Do not create or commit root `docs/specs/**` work
  packages for public repository maintenance.
- `workflow-spec-lite` remains a target-project tool. Target projects may keep
  their own local `docs/specs/<slug>/` work packages when that fits their
  workflow.
- Commit only when the user or project policy asks for it. Push only when explicitly requested or when established project workflow clearly requires it.

### Write Authorization Boundaries

External writes include branch push, PR/MR creation, issue comments, tag
creation, release publication, branch deletion, merge, repository settings,
rulesets, runners, hooks, secrets, webhook or API configuration, and workflow
dispatch.

External writes are never the default. Each requires explicit authorization from
one of:

- the user's current instruction;
- a loaded project instruction, spec, issue, release workflow, or command card
  that explicitly requires the operation for this work type;
- an already-approved work item or workflow step that names the operation.

Authorization must come from evidence outside the agent's own output. The
following are not sufficient by themselves to authorize a write:

- "this would keep the baseline clean";
- "a checkpoint would be useful";
- the agent saying the action is allowed;
- broad assumptions about what "project workflow usually wants";
- an unverified claim that a hidden workflow requires the operation.

Local commit is allowed only when the task is an implementation or fix work
unit, validation can prove completion, the diff can be reviewed, unrelated
changes can be excluded, and one of the authorization sources above exists. Do
not commit for review-only, research-only, planning-only, or ambiguous work.

If the authorization evidence is missing or unclear, put the operation under
"Requires confirmation" or stop before it. When ambiguity affects repository,
authority, destructive action, or external write behavior, downgrade to a
read-only orientation or ask one short question.

For non-trivial public maintenance that should survive the current session, use:
- the accepted GitHub issue for scope, non-goals, and acceptance criteria
- the pull request body for issue-to-change mapping, validation, rollback, and
  maintainer decision state
- release docs, changelog entries, governance docs, or curated knowledge entries
  only when the result is meant to remain user-facing or reusable

For multi-stage target-project work that uses `workflow-spec-lite`, use an
Execution Contract in the project-local spec so the agent continues to the next
validated phase until the stop rule is triggered.
