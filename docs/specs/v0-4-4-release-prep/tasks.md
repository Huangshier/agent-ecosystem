# Task Plan

- **Spec**: `docs/specs/v0-4-4-release-prep/spec.md`
- **Status**: Draft
- **Updated**: 2026-05-22

## Tasks

- [x] T01: Assess public state and version positioning
  - Scope: latest published release, merged post-`v0.4.3` work, open
    issue/PR state, and release validation evidence.
  - Validation: Candidate classified as stabilization / docs / governance
    patch release; #23 remains a referenced planning umbrella.

- [x] T02: Prepare bilingual release-facing records
  - Scope: `CHANGELOG.md`, `docs/releases/README.md`,
    `docs/releases/v0.4.4.md`, and `docs/release-readiness.md`.
  - Validation: Release notes contain equivalent `中文` and `English`
    sections with scope, validation, usage impact, limitations, risk/rollback,
    and maintainer recommendation.

- [x] T03: Add release validator coverage
  - Scope: `scripts/validate-release.ps1` and release process coverage text.
  - Validation: Validator requires the `v0.4.4` release-prep notes and release
    index entry.

- [x] T04: Run local validation
  - Scope: whitespace diff check and full release validation.
  - Validation: `git diff --check`; `scripts/validate-release.ps1` passed with
    `PASS=51 FAIL=0 WARN=0 DEFERRED=0`.

- [x] T05: Prepare maintainer handoff
  - Scope: PR body with summary, validation, risk/rollback, and recommendation.
  - Validation: PR references #23 without closing it and does not tag or publish
    a release.

## Task-to-Spec Notes

- Release publication remains outside this work package.
- `README.md` and `README.en.md` intentionally keep `v0.4.3` as the current
  published release until maintainer-approved publication changes that fact.

## Conditional Loop Tasks

- Not applicable.

## Execution Contract Tasks

- [x] P01: Complete state assessment
  - Goal: Establish release scope from public evidence.
  - Inputs: GitHub issue, PR, release, run, and `main` state.
  - Outputs: Patch-release positioning.
  - Validation: No expansion or profile behavior change found.
  - Continue / stop decision: Continue.

- [x] P02: Draft release-facing records
  - Goal: Produce public-safe bilingual release material.
  - Inputs: merged post-`v0.4.3` work and release validation evidence.
  - Outputs: Changelog, release notes, release readiness, and spec records.
  - Validation: Release notes include both required languages and release
    recommendation.
  - Continue / stop decision: Continue.

- [x] P03: Add validation coverage and run checks
  - Goal: Keep release-prep artifacts under release validation.
  - Inputs: release-prep docs and validator patterns.
  - Outputs: Validator check and validation evidence.
  - Validation: Full local release validation passed with
    `PASS=51 FAIL=0 WARN=0 DEFERRED=0`.
  - Continue / stop decision: Continue to maintainer review.
