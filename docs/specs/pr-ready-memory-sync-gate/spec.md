# Work Spec

- **Title**: PR-Ready Memory Sync Gate
- **Slug**: pr-ready-memory-sync-gate
- **Status**: Active
- **Owner**: Maintainer + agent
- **Updated**: 2026-05-12

## 1. Summary

- Add a lightweight governance rule that requires agents to synchronize active
  engineering memory before a PR becomes ready for review or an implementation
  phase is closed.
- Keep the rule as documentation and skill guidance only.

## 2. Current Context

- Issue #36 was created after PR #35 exposed a process gap: the PR could become
  ready while `.agents/plan.md`, `.agents/process.txt`, and active spec/tasks
  still described intermediate work.
- `project-context-gate` reloads memory but does not write updates.
- `workflow-spec-lite` creates durable work packages but does not currently
  require a PR-ready or phase-close memory sync.
- `memory-governance` is available for memory cleanup, but it is not a
  pre-commit hook or automatic session-end hook.

## 3. Goals

- Define a PR-ready / phase-close memory sync gate in `.agents/AGENTS.md`.
- Add matching workflow guidance to `skills/workflow-spec-lite/SKILL.md`.
- Make the required files explicit:
  - active `docs/specs/<slug>/spec.md`;
  - active `docs/specs/<slug>/tasks.md`;
  - `.agents/plan.md`;
  - necessary `.agents/process.txt`;
  - necessary `.agents/notes.md`.
- Provide an agent-executable checklist.
- Close out the PR #35 memory-safety work package as Done before pointing hot
  memory at #36.

## 4. Non-Goals

- Do not require every intermediate commit to synchronize all engineering
  memory.
- Do not add a pre-commit hook.
- Do not change GitHub rulesets, branch protection, required checks, or App
  permissions.
- Do not turn hosted-check result recording into an endless memory-only commit
  loop.
- Do not implement #30, #32, or #33.

## 5. Constraints

- Public repository docs, specs, skills, and engineering memory remain
  English-first.
- Keep the change lightweight and reviewable.
- Preserve the existing issue-first governance workflow.
- Keep private paths, local mappings, and App authentication material out of
  public files.

## 6. Assumptions

- A documented checklist is sufficient for this phase; automation can be
  considered only if later evidence shows the manual gate is unreliable.
- The gate should run at meaningful boundaries, not before every local commit.

## 7. Risks

- The gate could become busywork if it is written too broadly.
- Hosted checks could create churn if agents treat every check timestamp as a
  required memory update.

## 8. Proposed Approach

- Add a focused gate section to `.agents/AGENTS.md`.
- Add a reusable gate section to `workflow-spec-lite` so future work packages
  inherit the same expectation.
- Update public hot memory and the completed #35 work package to remove stale
  active-work references.

## 9. Acceptance / Evidence

- `.agents/AGENTS.md` contains the PR-ready / phase-close memory sync gate.
- `skills/workflow-spec-lite/SKILL.md` contains the same rule and checklist.
- The checklist names the required files and distinguishes required checks from
  conditional updates.
- The rule says ordinary intermediate commits do not force a full memory sync.
- The rule explicitly does not introduce pre-commit hooks or GitHub ruleset
  changes.
- The rule prevents hosted-check evidence from becoming an infinite update
  loop.
- PR #35 and issues #29/#31 are no longer presented as active work in public
  engineering memory.
- `git diff --check` passes.

## 10. Loop Contract

- Not required. This is a bounded documentation and memory-governance change.

## 11. Execution Contract

- **Autonomy level**: bounded-autonomous
- **Phase list**:
  - P01: Accept #36 scope and create this work package.
  - P02: Add the PR-ready / phase-close gate to project and skill guidance.
  - P03: Synchronize public engineering memory and close out PR #35 state.
  - P04: Validate, commit, push, and open a PR for #36.
- **Continue rule**: Continue while changes stay limited to governance docs,
  skill guidance, specs, and tracked public engineering memory.
- **Stop rule**: Stop for scope drift into #30/#32/#33, pre-commit hooks,
  GitHub ruleset changes, repository setting changes, App-auth boundary
  changes, or missing permission for GitHub writes.
- **State record**:
  `docs/specs/pr-ready-memory-sync-gate/tasks.md` and `.agents/plan.md`.

## 12. Open Questions

- Whether a later release should add lightweight validator coverage for stale
  memory references. This PR does not add that automation.
