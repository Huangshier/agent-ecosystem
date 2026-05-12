# Task Plan

- **Spec**: `docs/specs/validation-tier-policy/spec.md`
- **Status**: Active
- **Updated**: 2026-05-12

## Tasks

- [x] T01: Read issue #27 and current validation docs
  - Scope: #27, `docs/release-process.md`, `docs/agent-governance.md`,
    PR template, release validation workflow.
  - Validation: Existing rules and requested acceptance criteria reviewed.
  - Notes: Policy belongs in release process, with governance linking to it.

- [x] T02: Create validation-tier work package
  - Scope: `docs/specs/validation-tier-policy/`.
  - Validation: Spec and tasks describe goals, non-goals, acceptance, and
    execution contract.
  - Notes: No runtime behavior or ruleset changes included.

- [x] T03: Document validation tiers
  - Scope: `docs/release-process.md`, `docs/agent-governance.md`, PR template.
  - Validation: Covers issue metadata, ordinary docs, governance docs, tracked
    agent memory, scripts, installer behavior, CI, and release metadata.
  - Notes: Policy lives in release process; governance doc links to it; PR
    template now records the selected tier.

- [x] T04: Refresh public memory for #27
  - Scope: `.agents/process.txt`, `.agents/plan.md`, `.agents/notes.md`.
  - Validation: Public memory no longer presents #22 as active.
  - Notes: Public memory points to #27 and records PR #28 closeout.

- [ ] T05: Validate, publish PR, and wait for checks
  - Scope: branch `issue-27-validation-tiers`.
  - Validation:
    - `git diff --check` passed.
    - Local release validation passed: `PASS=33 FAIL=0 WARN=0 DEFERRED=0`.
    - hosted release validation checks on PR
  - Notes: PR #34 is open and should close #27. Full local validation is
    required because this touches release process docs, governance docs, PR
    template, specs, and tracked public `.agents` memory.

## Task-to-Spec Notes

- #23 roadmap/domain-pack governance remains deferred.
- #29-#33 engineering-memory issues remain separate follow-up work.

## Execution Contract Tasks

- [x] P01: Draft spec/tasks and point public memory at #27
  - Goal: Make #27 policy work durable and reviewable.
  - Inputs: #27 issue body, current docs, project templates.
  - Outputs: spec/tasks files.
  - Validation: Files added under `docs/specs/validation-tier-policy/`.
  - Continue / stop decision: Continue to P02.

- [x] P02: Document validation tiers and PR evidence fields
  - Goal: Add the user-facing policy and PR evidence hook.
  - Inputs: release process, agent governance, PR template.
  - Outputs: updated docs/template.
  - Validation: Content review against #27 acceptance criteria.
  - Continue / stop decision: Continue to local validation.

- [x] P03: Validate locally, commit, push, and open PR
  - Goal: Produce a reviewable PR for #27.
  - Inputs: completed docs, memory updates, validation evidence.
  - Outputs:
    - Commit `c106792 docs: define validation tiers`.
    - Remote branch `issue-27-validation-tiers`.
    - PR #34 `docs: define validation tiers` by `agent-ecosystem-bot[bot]`.
  - Validation:
    - `git diff --check` passed.
    - Local release validation passed: `PASS=33 FAIL=0 WARN=0 DEFERRED=0`.
  - Continue / stop decision: Continue to hosted checks and maintainer review.

- [ ] P04: Wait for hosted checks and maintainer review
  - Goal: Ensure external checks pass before maintainer merge decision.
  - Inputs: opened PR.
  - Outputs: hosted check summary.
  - Validation: required hosted release validation checks pass.
  - Continue / stop decision:
