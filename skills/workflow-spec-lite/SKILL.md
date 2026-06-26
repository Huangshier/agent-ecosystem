---
name: workflow-spec-lite
description: Lightweight spec-first workflow for non-trivial target-project work. Use when starting a new feature, research thread, refactor, debugging effort, reverse-engineering task, or other implementation work where the goal, constraints, approach, or acceptance criteria should be made explicit before execution. Loads project context first, routes work as quick, standard, or deep, and writes target-project docs under docs/specs.
category: kernel
stability: stable
scope: cross-project
---

# Workflow Spec Lite

## Purpose
Create just enough structure before execution so non-trivial work does not live only in chat history or `.agents` session memory.

This skill is intentionally lightweight:
- trivial work can skip formal spec files
- medium work gets a single `spec.md`
- larger or multi-phase work gets `spec.md` plus `tasks.md`

## Trigger Conditions
Use this skill when at least one of these is true:
- The request is not a trivial one-file change with obvious completion criteria.
- The work spans multiple files, modules, stages, or validation steps.
- The user is still clarifying what "done" means.
- The task is exploratory or research-heavy, including reverse engineering and unfamiliar code investigation.
- The work has meaningful constraints, assumptions, or risks that should survive the current session.

Do not use this skill for:
- tiny local fixes with a clear file target and clear acceptance
- pure memory cleanup tasks already covered by `memory-governance`

## Output Paths
Write long-lived target-project artifacts under:
- `docs/specs/<slug>/spec.md`
- `docs/specs/<slug>/tasks.md`

Do not create `docs/specs/<slug>/plan.md`.

`.agents/plan.md` remains session-local and should only point to the active spec/task, not duplicate their full content.

When maintaining the public `agent-ecosystem` source repository itself, do not
create root `docs/specs/**` work packages. Use the accepted GitHub issue and
pull request body as the durable public maintenance record.

## Project Context Gate
Before planning or implementing a non-trivial repository task, run a project context gate.

Preferred:
- Use the `project-context-gate` skill when it is available.

Fallback:
- If `project-context-gate` is unavailable, manually load context in this order:
  1. root `AGENTS.md`, if present
  2. `.agents/AGENTS.md`, if present
  3. `.agents/process.txt`, if present
  4. `.agents/plan.md`, if present
  5. active `docs/specs/<slug>/spec.md` and `tasks.md`, if referenced by hot memory
  6. `.agents/context/` README/index files, then only matching context entries on demand
  7. `.agents/notes.md`, only when stable notes are relevant to the task

After loading context, summarize a short constraint capsule before routing the work: current objective, active phase, project rules, validation rules, commit/push rules, and known blockers.

Repeat the gate after a phase commit if continuing to another phase, after context compaction or resume, and after a user correction that changes project rules or workflow assumptions.

## Template Selection
Prefer project-local templates when present:
- `docs/specs/_templates/spec-lite.md`
- `docs/specs/_templates/tasks-lite.md`

If they do not exist, fall back to this skill's bundled references:
- [references/spec-template.md](references/spec-template.md)
- [references/tasks-template.md](references/tasks-template.md)

For routing heuristics, read [references/complexity-routing.md](references/complexity-routing.md).

## Workflow

### Step 0: Run the Project Context Gate
Run the context gate described above. Do not continue with stale project rules when the task is non-trivial, multi-stage, resumed, or corrected by the user.

### Step 1: Check for an Existing Active Spec
Before creating anything new:
1. Search `docs/specs/` for a matching slug, feature name, or current work item.
2. If a matching `spec.md` already exists, reuse it unless the user is clearly starting unrelated work.
3. If `tasks.md` already exists, treat it as the canonical implementation checklist.

### Step 2: Route the Work
Classify the request as one of:

#### Quick
Use when all are true:
- likely one file or one local edit area
- clear target behavior
- clear validation path
- no durable design or research value

Action:
- do not create `spec.md`
- state briefly why quick path is acceptable
- proceed with execution

#### Standard
Use when any of these is true:
- multiple files are likely
- constraints or acceptance need to be written down
- the work may continue across sessions
- the task is exploratory but still reasonably bounded

Action:
- create `docs/specs/<slug>/spec.md`
- fill it before implementation
- do not create `tasks.md` yet unless the work is clearly multi-stage

#### Deep
Use when any of these is true:
- multiple implementation stages or milestones are expected
- the task spans modules, subsystems, or research plus implementation
- review, validation, or handoff requires an explicit execution checklist
- the work will likely pause and resume across sessions

Action:
- create `docs/specs/<slug>/spec.md`
- create `docs/specs/<slug>/tasks.md`
- stop after drafting tasks if user confirmation is needed before execution

### Step 3: Build the Spec
When `standard` or `deep` path is selected:
1. Pick a slug in lowercase kebab-case.
2. Create `docs/specs/<slug>/`.
3. Start from the selected spec template.
4. Fill only the sections supported by current evidence. Do not invent certainty.

The spec must capture:
- what is being changed or investigated
- why it matters
- current artifacts or code paths already known
- goals and non-goals
- constraints, assumptions, and risks
- proposed approach
- how completion will be judged
- how scope drift, unrelated refactors, and skipped acceptance checks will be handled before claiming completion

### Step 3a: High-Risk Evidence Gate
Before implementation, identify whether the work depends on facts where a
wrong assumption can cause data loss, unsafe behavior, production impact,
irreversible external side effects, or physical/electrical damage.

For high-risk work:

- Treat missing facts as blocking open questions, not as assumptions to fill
  from names, nearby resources, prior variants, or convenience.
- Record evidence sources in the spec before editing. Evidence can be a read
  file, issue, design note, test output, trace, schematic, maintainer statement,
  or other source that the agent actually inspected.
- Put unresolved high-risk facts in `Open Questions` and stop before
  implementation when those facts affect behavior or safety.
- Acceptance criteria should name the evidence-backed facts that must be
  verified, not just the intended output.
- When high-risk work involves schematic, pin-map, board-port, or power
  sequencing facts, acceptance criteria should include an evidence-backed
  mapping table or equivalent checklist for each safety-relevant signal or
  rail: source evidence, target pin or net, active level, reset/default
  behavior, power rail or domain, timing or sequencing constraint, and
  verification method.
- Any unknown required entry in that mapping is a blocking open question before
  implementation. Evidence must come from inspected schematics, board files,
  datasheets, source repositories, maintainer statements, or test output; do
  not infer it from signal names, nearby unused pins, or prior variants.

Examples of high-risk facts include destructive file operations, production
target identifiers, access boundaries, electrical pin mapping, active levels,
reset lines, power rails, timing constraints, and power sequencing. This is
generic evidence-gated workflow guidance; it is not a domain pack and does not
authorize domain-specific implementation without source evidence.

### Step 4: Build Tasks Only When Needed
Create `tasks.md` only on the `deep` path, or when the user explicitly asks for task decomposition.

Task rules:
- tasks must be actionable and ordered
- tasks should be independently checkable
- tasks should map back to the active spec
- tasks should describe validation where possible

### Step 4a: Conditional or Repeated Execution
For multi-phase work such as migrations, refactors, subsystem changes, or `/goal`-style autonomous execution, add an `Execution Contract` section to `spec.md`.

Execution Contract fields:
- `Autonomy level`: `ask-before-each-phase`, `autonomous-until-blocked`, or `bounded-autonomous`
- `Phase list`: each phase's goal, inputs, outputs, validation, and next-phase entry condition
- `Continue rule`: the condition that authorizes moving from one phase to the next without stopping
- `Stop rule`: failures, ambiguity, high-risk actions, missing permissions, budget limits, or external blockers that require stopping

When the work involves external writes (branch push, PR/MR creation, issue
comments, tags, releases, repository settings, workflow dispatch, or deployment
triggers), the Stop Rule must require stopping when explicit authorization
evidence is missing. Authorization must come from the user's instruction, a
loaded project instruction, or an approved work item that names the operation.
The agent's own assessment that an action "should be fine" is not authorization
evidence. Local commits require a coherent work unit, passable validation,
reviewable diff, and an explicit authorization source. When ambiguity affects
repository target, authority, destructive action, or external write behavior,
degrade to read-only or ask before continuing.
- `State record`: where current phase, completed phases, validation results, and next action are recorded

For `/goal` workflows, map the goal to the active spec/tasks before execution. After each phase, update the state record and continue to the next task when the continue rule passes; do not stop merely because one phase was completed.

For `/goal`-style migration prompt generation, long-running autonomous
execution, or any workflow that transfers behavior between repositories, record
source evidence before producing or executing the prompt. The active spec/tasks
or prompt notes must identify:

- the source and reference repositories, documents, commits, issues, or local
  artifacts that were actually read;
- the target repository root and write authorization boundary;
- the source facts that constrain the migration or generated prompt;
- any missing source/reference evidence as a blocking open question.

Do not generate a long-running `/goal` prompt from memory, naming conventions,
or an assumed source repository alone. If the source or reference evidence is
missing, stop before execution and ask for the missing evidence or a narrowed
scope.

When the user wants the agent to repeat a lightweight workflow until a variable, metric, build result, test result, device state, or other condition is satisfied, treat the work as `deep` unless it is clearly a one-shot check.

Add a `Loop Contract` section to `spec.md` with:
- `Variable`: the value being watched
- `Source of truth`: where the value comes from
- `Check command`: the deterministic command or inspection step used to read the value
- `Pass predicate`: the exact condition that means the loop is done
- `Iteration action`: the bounded action to take once per loop
- `State record`: where the latest observed value and iteration count are recorded
- `Limits`: max iterations, timeout, and cost/resource bounds
- `Abort conditions`: errors, safety boundaries, non-idempotent operations, or ambiguity that should stop the loop

Task rules for loops:
- Record one task for checking the current value before acting.
- Record one task for a single bounded iteration.
- Record one task for rechecking and updating state.
- Do not ask an agent to run indefinitely. Every loop needs a max iteration count or timeout.
- Prefer idempotent iteration actions. If the next action is destructive, externally visible, or not safely repeatable, stop and ask for confirmation.
- Markdown is acceptable for agent-facing state; use a machine-readable state file only when an external runner or scheduler must resume the loop automatically.

### Step 5: Handoff to Execution
After spec generation:
- point `.agents/plan.md` at the active spec and current task
- do not copy the full spec into `.agents/notes.md` or `.agents/process.txt`
- if execution starts immediately, keep the spec authoritative and update tasks there

### Step 6: PR-Ready / Phase-Close Memory Sync Gate
Before marking a pull request ready for review, handing off a non-draft pull request, or closing an implementation phase, run this boundary gate:

1. Re-read the active `docs/specs/<slug>/spec.md` and `docs/specs/<slug>/tasks.md`.
2. Update the active spec and tasks when the phase state, status, validation evidence, non-goals, or next action changed.
3. Update `.agents/plan.md` so it points to the real active spec and current next action without duplicating the full task list.
4. Update `.agents/process.txt` if active issues, PRs, branch state, blockers, or next actions changed.
5. Update `.agents/notes.md` only when there is a durable verified fact, final decision, or evidence link worth preserving.
6. When `memory_diagnose.ps1` is available, run it against the project root before claiming the memory sync is complete:
   `pwsh -NoProfile -File <runtime-or-repo>/skills/memory-governance/scripts/memory_diagnose.ps1 -ProjectRoot <project-root> -Json`.
   Address warnings before closing the phase, or record why they are intentionally deferred. Record the finding count and summary in the active spec/tasks, PR body, or phase-close evidence.
7. Check that no completed hosted-check wait, ready-for-review step, or previous PR remains listed as active work.
8. Record hosted check evidence once at the relevant boundary. Do not create repeated memory-only commits solely to refresh hosted-check timestamps.
9. Confirm the sync did not add unrelated refactors, pre-commit hooks, GitHub ruleset changes, or work outside the accepted issue scope.

Ordinary intermediate commits do not require a full engineering-memory sync. Keep this as a documented workflow gate; do not implement it as a pre-commit hook or repository ruleset requirement.

## Writing Rules
- Keep the spec generic and project-facing, not agent-facing.
- Put durable work intent in `docs/specs/`, not in `.agents`.
- Prefer concise bullets over narrative prose.
- Record assumptions explicitly instead of silently resolving ambiguity.
- If the task is reverse engineering or research, evidence and open questions are first-class outputs.
- If the task depends on high-risk facts, missing evidence is a blocking open
  question before implementation.
- When the work involves external writes, state the write authorization boundary
  in the spec: which writes are authorized, by what evidence, and what must stop
  before proceeding. Do not let the spec's own wording become its own
  authorization source.
- For multi-phase execution, write an Execution Contract instead of relying on a vague "work through the plan" instruction.
- For repeated execution, write a bounded loop contract instead of relying on a vague "continue until done" instruction.
- Use `scripts/validate_spec.ps1` when you need a read-only check that a spec has the required goals, non-goals, risks, acceptance, and Execution Contract stop rule fields. The helper reports findings only; it does not rewrite the spec.

## Anti-Patterns
- Writing long-lived design content only in `.agents/notes.md`
- Creating `tasks.md` for trivial one-step work
- Duplicating the task list into `.agents/plan.md`
- Treating `.agents/plan.md` as the project's canonical implementation checklist
- Creating a new spec when an existing active spec should be extended
- Stopping after a successful phase when an Execution Contract says to continue
- Asking an agent to loop forever without a deterministic check, pass predicate, timeout, or abort conditions

## Output Contract
When this skill is used, return:
1. The chosen route: `quick`, `standard`, or `deep`
2. The active slug and output path
3. What file(s) were created or reused
4. Any unresolved assumptions or questions before execution
