# Task Plan

- **Spec**: `docs/specs/v0-4-4-release-prep/spec.md`
- **Status**: Ready for review
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

- [x] T06: Correct post-publication metadata and finalization guardrail
  - Scope: `README.md`, `README.en.md`, `docs/releases/v0.4.4.md`,
    `docs/releases/README.md`, `docs/release-readiness.md`,
    `docs/release-process.md`, and `scripts/validate-release.ps1`.
  - Validation: `git diff --check`; full local release validation with
    `-TargetVersion v0.4.4` passed with
    `PASS=52 FAIL=0 WARN=0 DEFERRED=0`.

## Task-to-Spec Notes

- New release publication actions remain outside this addendum; the `v0.4.4`
  tag and GitHub Release already exist.
- Historical release-preparation work intentionally kept `README.md` and
  `README.en.md` on `v0.4.3`; the post-publication addendum updates them to
  `v0.4.4`.

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

- [x] P05: Correct post-publication metadata and finalization guardrail
  - Goal: Align public metadata with the published `v0.4.4` state and prevent
    future direct publishing from planning metadata.
  - Inputs: Published tag target
    `71fabb372a4cbc024f07c920a0c17b903a77afc2`, GitHub Release `v0.4.4`,
    final hosted Release validation run `26269908157`, and maintainer request.
  - Outputs: Updated README current-release fields, published release notes,
    release readiness, release notes index, release process finalization
    guidance, and validator target-version alignment check.
  - Validation: `git diff --check`; full local release validation with
    `-TargetVersion v0.4.4` passed with
    `PASS=52 FAIL=0 WARN=0 DEFERRED=0`.
  - Continue / stop decision: Stop at a reviewable PR; do not retag, republish,
    edit settings, reopen #23, or push directly to `main`.
