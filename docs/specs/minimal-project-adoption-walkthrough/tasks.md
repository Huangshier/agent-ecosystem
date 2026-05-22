# Task Plan

- **Spec**: `docs/specs/minimal-project-adoption-walkthrough/spec.md`
- **Status**: Done
- **Updated**: 2026-05-22

## Tasks

- [x] T01: Read accepted issue and existing adoption docs
  - Scope: #22, README files, `docs/how-to-adapt.md`, examples, existing specs.
  - Validation: Existing docs and issue body reviewed before editing.
  - Notes: #22 requires a continuous walkthrough rather than another short
    conceptual guide.

- [x] T02: Create walkthrough document
  - Scope: `docs/walkthroughs/minimal-project-adoption.md` and optional
    `docs/walkthroughs/README.md`.
  - Validation: Covers install, bootstrap, context gate, spec-lite,
    memory-governance, knowledge hub routing, validation, and cleanup.
  - Notes: Added `docs/walkthroughs/minimal-project-adoption.md` and
    `docs/walkthroughs/README.md`.

- [x] T03: Link walkthrough from entrypoints
  - Scope: `README.md`, `README.zh-CN.md`, `docs/how-to-adapt.md`,
    `examples/README.md` as appropriate.
  - Validation: Links resolve to the new walkthrough.
  - Notes: Linked from README, localized README, how-to-adapt, and examples.

- [x] T04: Refresh public memory for #22
  - Scope: `.agents/process.txt`, `.agents/plan.md`, `.agents/notes.md`.
  - Validation: Public memory no longer presents #25 as active.
  - Notes: Public memory now points to #22 and records PR #26 closeout.

- [x] T05: Validate, publish PR, and wait for checks
  - Scope: branch `issue-22-minimal-adoption-walkthrough`.
  - Validation:
    - `git diff --check`
    - `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-release.ps1`
    - hosted release validation checks on PR
  - Notes: PR #28 merged on 2026-05-11 at
    `38e39834398e034698b9c37541605a8a7630f04e`; issue #22 is closed.
    Follow-up release validation after review corrections passed with
    `PASS=33 FAIL=0 WARN=0 DEFERRED=0`.

## Task-to-Spec Notes

- This is a public docs adoption task, not a runtime feature.
- #27 validation-tier policy remains separate and should not be resolved here.

## Execution Contract Tasks

- [x] P01: Draft spec/tasks and point public memory at #22
  - Goal: Make the #22 work item durable and reviewable.
  - Inputs: #22 issue body, current docs, project templates.
  - Outputs: spec/tasks files.
  - Validation: Files added under `docs/specs/minimal-project-adoption-walkthrough/`.
  - Continue / stop decision: Continue to P02 unless scope expands beyond docs
    and tracked public memory.

- [x] P02: Implement walkthrough and entrypoint links
  - Goal: Add the user-facing adoption path.
  - Inputs: existing docs and minimal example.
  - Outputs: walkthrough doc and links.
  - Validation: Link and content review; no private/local path leakage.
  - Continue / stop decision: Completed; continue to P03 validation.

- [x] P03: Validate locally, commit, push, and open PR
  - Goal: Produce a reviewable PR for #22.
  - Inputs: completed docs and memory updates.
  - Outputs: commit, remote branch, PR.
  - Validation:
    - `git diff --check` passed.
    - Local release validation passed: `PASS=33 FAIL=0 WARN=0 DEFERRED=0`.
  - Continue / stop decision: Complete; PR #28 merged and issue #22 is closed.

- [x] P04: Wait for hosted checks and maintainer review
  - Goal: Ensure external checks pass before maintainer merge decision.
  - Inputs: opened PR.
  - Outputs: PR #28 merged to `main`; issue #22 closed.
  - Validation:
    - Hosted release validation passed on PR #28:
      - `validate Windows PowerShell 5.1`: `SUCCESS`
      - `validate pwsh (windows-latest)`: `SUCCESS`
      - `validate pwsh (ubuntu-latest)`: `SUCCESS`
      - `validate pwsh (macos-latest)`: `SUCCESS`
  - Continue / stop decision: Complete.
