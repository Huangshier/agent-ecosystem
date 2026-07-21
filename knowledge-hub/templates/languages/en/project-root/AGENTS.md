# AGENTS.md

This root file is the single authoritative project behavior contract.

Read it first at the start of every non-trivial task. Then read `.agents/AGENTS.md`
for the project-memory language, directory responsibilities, progressive load
order, and template provenance. The memory guide supplements this contract; it
does not replace or duplicate project behavior rules.

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

## Write Authorization Boundaries
External writes include branch push, PR/MR creation, issue comments, tag
creation, release publication, branch deletion, merge, repository settings,
workflow dispatch, and deployment triggers. External writes are never the
default. Each requires explicit authorization from:

- the user's current instruction;
- a loaded project instruction, spec, issue, release workflow, or command card
  that explicitly requires the operation for this work type;
- an already-approved work item or workflow step that names the operation.

Authorization must come from evidence outside the agent's own output. Not
sufficient by themselves: "keep the baseline clean", "a checkpoint would be
useful", the agent saying the action is allowed, or broad assumptions about
project workflow.

Local commit is allowed only when the task is a coherent implementation or fix
work unit, validation can prove completion, the diff can be reviewed, unrelated
changes can be excluded, and one of the authorization sources above exists. Do
not commit for review-only, research-only, planning-only, or ambiguous work.

If authorization evidence is missing or unclear, put the operation under
"Requires confirmation" or stop before it. When ambiguity affects repository,
authority, destructive action, or external write behavior, downgrade to a
read-only orientation or ask one short question.

## Ambiguous Task Gate
When the user's request is semantically broad or underspecified, do a short read-only exploration pass before editing. Examples include "optimize this", "clean this up", "migrate this", "fix the workflow", "look for problems", or requests without clear acceptance criteria.

After exploration, proceed only when the goal, scope, non-goals, and validation path are clear. Ask a concise question when ambiguity is about product intent, success criteria, destructive/high-impact actions, external systems, or incompatible interpretations. Make reversible implementation choices yourself once intent is clear.

Scope discipline: do not fold unrelated refactors, cleanup, or behavior changes into a work item unless they are explicit goals. If acceptance checks are skipped or unavailable, record that before claiming completion.

## Engineering Memory Refresh, Migration, And Reset
Treat project-memory refresh, template upgrade, and language migration as
memory-scoped workflows, not ordinary bulk edits.

- Before changing `.agents/**` for these requests, run the project context gate
  and use the relevant `project-bootstrap` proposal-first, backup-first script
  flow.
- Refresh or template upgrade preserves project-specific content by default.
  Update missing or unmodified scaffold surfaces, and route customized content
  to review.
- Language migration changes templates and reviewed narrative to the target
  project-memory language while keeping commands, paths, APIs, filenames, raw
  errors, and code symbols in their original form.
- Reset or reinitialize may discard old memory only when the user explicitly
  says not to preserve it, such as "do not keep old project memory" or "reset
  to the latest templates".

## Global Experience Discovery
Use global experience as an optional, on-demand lookup layer for reusable
cross-project workflow problems involving toolchains, host environments,
shells, builds, caches, ports, permissions, path handling, environment
variables, or similar recurring surfaces. Do not preload it or assume that an
index is available on every host.

When the lookup applies:

1. Read the configured global experience index if it exists.
2. Match observed error text, tool names, and symptoms against entry
   `keywords` first, then `title`.
3. Read only the matched entries and apply a recorded prevention rule only when
   it fits the current context.
4. If the index is missing or no entry matches, fail soft and continue with
   project-local diagnosis.

Do not trigger global lookup by default for issues that clearly depend on the
current repository's business logic, hardware wiring, protocol implementation,
or module design.

Keep project experience in the project by default. Route reviewed
cross-project candidates through the existing intake / triage workflow; never
promote them automatically.

## Project Commands
Use documented project commands before inventing new ones. Discovery order:

1. Project docs such as `README.md`, `CONTRIBUTING.md`, `docs/`, and release notes.
2. Tooling surfaces such as package scripts, Makefiles, task runners, and CI workflows.
3. `.agents/commands/README.md` and any workflow cards under `.agents/commands/`.

Use `.agents/commands/` for reusable high-frequency workflows such as setup, format/lint, test, build, release validation, recurring monitors, and review checklists. Each command card should be short and include purpose, when to use it, prerequisites, commands, expected evidence, and safety notes for external side effects.

Recurring automations should usually point at a command card instead of embedding project rules in the scheduler prompt. Keep the schedule prompt thin: when to run, which card to execute, and where to report. Keep project rules, verification commands, safety boundaries, and output expectations in repository files.

## Large Issue Planning
For large, high-blast-radius, or multi-area issues, produce an implementation plan before editing. When the plan would create an oversized PR, propose a reviewable PR split and keep each phase tied to acceptance evidence.

## Verification And Completion
Every implementation task should have an explicit verifier before it is called done. Prefer deterministic, scriptable checks from project docs, CI, package scripts, or `.agents/commands/`.

For non-trivial work, write the verifier in `docs/specs/<slug>/spec.md` acceptance criteria or `tasks.md` validation fields. If no deterministic verifier exists, record the review evidence that substitutes for it, such as rendered output, screenshots, manual reproduction steps, or reviewer confirmation.

If an expected verifier cannot run, record why in the active spec/tasks or `.agents/process.txt`, mark the remaining risk, and do not present the work as fully complete.

## Delivery Protocol & Working Loop
For implementation tasks that produce repository changes, a complete unit of work may include the relevant parts of the following sequence:

1. **Read & Plan**: Read relevant code and context notes. Use `workflow-spec-lite` routing criteria as the deciding rule for whether a project spec is needed. Prefer a project spec under `docs/specs/<slug>/` for standard/deep work or durable design value; use the quick path without creating a spec for narrow tasks with clear acceptance criteria and validation. Keep `.agents/plan.md` as a session-local pointer, not a second project plan.
2. **Implement & Verify**: Confirm the work meets the completion criteria and passes the named verifier(s) for this project. Implement in small validated steps. Prefer deterministic, scriptable verification commands. Record blockers in `.agents/process.txt`.
3. **Learning Deposit Check**: After completing fixes and verification, and before the final report, check once for learning-trigger events since the previous check: a user correction, rework after a validation failure, scope drift, skipped acceptance, or a tool workaround. If no trigger occurred, continue without creating an experience file. If a trigger occurred, use the existing `memory-governance` `Session Learning Extraction` flow to generate up to 3 deposit suggestions and wait for user confirmation before writing. Keep project-local lessons in the project by default; route only global candidates through candidate intake / triage. Do not auto-promote.
4. **Atomic Commit**: Commit only when the user asks for a commit or project policy clearly requires one. When committing in a git repository, inspect recent history with `git log` and match the repository's prevailing commit message format unless the user or project policy says otherwise.
5. **The Push**: Push only when the user explicitly asks, or when established project workflow unambiguously requires it and remote access is available.
6. **The Report**: After validation and any required commit/push steps, provide your report. If the task is review-only or blocked by environment or policy, report the blocker or findings clearly instead of pretending the task is complete.

## PR-Ready And Phase-Close Memory Sync Gate
Before an agent opens a pull request, marks a pull request ready for review, hands off a non-draft pull request, or closes an implementation phase, it must run a lightweight engineering-memory sync gate.

This gate is workflow guidance, not a Git hook, repository ruleset, or branch-protection change. Ordinary intermediate commits do not require a full engineering-memory sync; update only the files needed for the work at that point.

Checklist:

1. Re-read the active `docs/specs/<slug>/spec.md` and `docs/specs/<slug>/tasks.md`.
2. Update the active spec status, phase state, verifier / acceptance evidence, and explicit non-goals when the phase result changed.
3. Update `.agents/plan.md` so it points at the real active spec and current next action, without copying the full task list.
4. Update `.agents/process.txt` when active issues, PRs, blockers, branch state, or next actions changed.
5. Update `.agents/notes.md` only for durable verified facts, final decisions, or evidence links that should survive the session.
6. When `memory_diagnose.ps1` is available, run it against the project root before claiming the memory sync is complete:
   `pwsh -NoProfile -File <runtime-or-repo>/skills/memory-governance/scripts/memory_diagnose.ps1 -ProjectRoot <project-root> -Json`.
   `<runtime-or-repo>` is the installed runtime or repository checkout that contains the script, not the project being diagnosed. The diagnosis starts at `-ProjectRoot`, checks `.agents/process.txt`, `.agents/plan.md`, `.agents/notes.md`, active `docs/specs/<slug>/(spec|tasks).md` references from hot memory, and non-template `.agents/context/**/*.md` files for `Summary` / `Keywords` discovery metadata. It does not scan `.agents/commands/**`; command discovery stays in `.agents/commands/README.md` and matching command cards.
   Find the helper by trying, in order, the installed runtime skills path, a configured or global agent skills/runtime path, and an adjacent `agent-ecosystem` checkout. If no candidate exists, record `memory_diagnose.ps1 unavailable; skipped` and continue; do not treat the missing helper as a phase-close blocker, and do not record machine-specific absolute paths or private paths.
   Address warnings before closing the phase, or record why they are intentionally deferred. Record the finding count and summary in the active spec/tasks, PR body, or phase-close evidence.
7. Run the same learning-deposit check for any new trigger events since the previous check before opening a pull request, handing off work, or closing the phase. Reuse `Session Learning Extraction` and its user-confirmation, project-local routing, candidate intake / triage, and no-auto-promotion boundaries; do not generate duplicate suggestions when no new trigger occurred.
8. Confirm no stale hosted-check, ready-for-review, or wait-for-review item still appears as active after it is complete.
9. Record hosted check results once at the relevant boundary. After a PR has been opened, do not push memory-only commits solely to refresh state or hosted-check timestamps unless explicitly approved.
10. Confirm the gate did not introduce unrelated refactors, pre-commit hooks, repository ruleset changes, or changes outside the accepted issue scope.

## Tooling Constraints
- **Non-Interactive**: Do not wait for ceremonial approval before routine reversible edits. Commit and push rules still follow the Delivery Protocol.
- **Environment Aware**: When the project is a git repository, check `git status` before committing. Inspect unstaged changes with `git diff` and staged changes with `git diff --cached` to ensure no unintended files or hunks are included.

## Project Work Packages
For work that should remain discoverable after the current session, store the canonical description under `docs/specs/`:
- `docs/specs/<slug>/spec.md`: durable work definition, constraints, approach, and acceptance
- `docs/specs/<slug>/tasks.md`: durable implementation checklist when multi-step execution is needed

Do not create `docs/specs/<slug>/plan.md`.
Do not duplicate full `spec.md` or `tasks.md` contents into `.agents/plan.md`.

For multi-phase work, write an Execution Contract in `spec.md`: autonomy level, phase list, continue rule, stop rule, and state record. If the continue rule passes after a phase, update state and continue to the next phase. Stop only when the stop rule is triggered.
