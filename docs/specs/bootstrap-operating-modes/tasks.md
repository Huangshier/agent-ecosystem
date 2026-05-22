# Task Plan

- **Spec**: `docs/specs/bootstrap-operating-modes/spec.md`
- **Status**: Done
- **Updated**: 2026-05-22

## Tasks

- [x] T01: Confirm issue dependency order
  - Scope: GitHub issues #33, #32, and #30.
  - Validation: #33 is first; #32 provides later file-based templates; #30 depends on safe modes plus template baselines.
  - Notes: #32 and #30 remain non-goals for this PR.

- [x] T02: Create #33 work package and branch
  - Scope: `docs/specs/bootstrap-operating-modes/*` and branch `issue-33-bootstrap-operating-modes`.
  - Validation: Spec and tasks exist on a branch based on current `main`.
  - Notes: #39 was merged and the old #38 branch was cleaned before starting.

- [x] T03: Implement operating-mode semantics
  - Scope: `skills/project-bootstrap/scripts/bootstrap_project.ps1`.
  - Validation: Existing project memory is not overwritten by default; force reset is explicit and backup-first.
  - Notes: Added `-RefreshUnmodifiedTemplates`, warning-only compatibility behavior for `-OverwriteTemplates`, and explicit `-ForceResetScaffold`.

- [x] T04: Update docs and skill guidance
  - Scope: `skills/project-bootstrap/README.md`, `skills/project-bootstrap/SKILL.md`, and relevant user docs.
  - Validation: Existing-project examples use conservative migration wording and #30/#32 are not implied as implemented.
  - Notes: Updated project-bootstrap guidance, adoption docs, language policy, and release docs.

- [x] T05: Add release validation coverage
  - Scope: `scripts/validate-release.ps1`.
  - Validation: Fixtures cover ordinary refresh, compatibility overwrite warning, and force-reset backup behavior.
  - Notes: Full local release validation passed with `PASS=35 FAIL=0 WARN=0 DEFERRED=0`.

- [x] T06: Validate and publish draft PR
  - Scope: branch commit, push, and draft PR for #33.
  - Validation: `git diff --check` and release validation pass; PR body includes required non-goals.
  - Notes: PR #40 merged to `main` at
    `19656e5f92264a960c8e6ac6039debd97166c10f`; issue #33 is closed.

## Task-to-Spec Notes
- #33 is a semantic and safety-boundary change.
- #32 file-based template extraction is the next separate issue.
- #30 conservative `en` / `zh-CN` migration is the final separate issue.
- This PR must not change release version, rulesets, hooks, runner configuration, App auth, or main protection.

## Execution Contract Tasks

- [x] P01: Re-read #33, #32, and #30; create this work package and branch from current `main`
  - Goal: Make #33 scope durable and confirm dependency order.
  - Inputs: Issue bodies, public project memory, and current git state.
  - Outputs: Branch and spec/tasks pair.
  - Validation: Branch exists and #33 is marked accepted for implementation.
  - Continue / stop decision: Continue to implementation.

- [x] P02: Update bootstrap mode semantics, warnings, and safe reset behavior
  - Goal: Make dangerous overwrite/reset semantics explicit and backup-first.
  - Inputs: Current bootstrap script and prior memory-safety behavior.
  - Outputs: `-RefreshUnmodifiedTemplates`, compatibility `-OverwriteTemplates` warning behavior, explicit `-ForceResetScaffold`, lock/evidence mode metadata, language overwrite backups.
  - Validation: Release validation bootstrap fixture passed.
  - Continue / stop decision: Continue to docs and validation closeout.

- [x] P03: Update docs, skill guidance, and release validation coverage
  - Goal: Make the operating model visible to users and future agents.
  - Inputs: README, skill docs, public user docs, and validator.
  - Outputs: Updated `project-bootstrap` docs, adoption/language/release docs, and release validator coverage.
  - Validation: `git diff --check` passed; `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-release.ps1` passed with `PASS=35 FAIL=0 WARN=0 DEFERRED=0`.
  - Continue / stop decision: Continue to recorded PR evidence.

- [x] P04: Validate, commit, push, and open a draft PR for #33
  - Goal: Produce a reviewable issue-first PR.
  - Inputs: Completed implementation and documentation.
  - Outputs: PR #40 merged to `main`.
  - Validation: PR #40 merge commit
    `19656e5f92264a960c8e6ac6039debd97166c10f`.
  - Continue / stop decision: Complete.
