# Task Plan

- **Spec**: docs/specs/v0-3-0-public-maintenance/spec.md
- **Status**: Active
- **Updated**: 2026-05-08

## Tasks

- [x] T01: Confirm public GitHub issues #1 and #2 exist and are open.
  - Scope: Issue tracking only.
  - Validation: GitHub issue pages show both issues open.
  - Notes: Branch `issue-1-2-v0.3.0-maintenance` created from local release-candidate state.

- [x] T02: Implement localized discovery heading support.
  - Scope: `memory-governance` diagnosis and `project-bootstrap` memory upgrade analysis.
  - Validation: Windows PowerShell 5.1 and PowerShell 7 release validators passed with `PASS=31 FAIL=0 WARN=0 DEFERRED=0`.
  - Notes: English headings remain valid; localized Simplified Chinese headings are accepted.

- [x] T03: Document bilingual public/private routing.
  - Scope: Knowledge standard, catalog, and public language policy docs.
  - Validation: Release validator content coverage for the standard and docs passed.
  - Notes: Keep public-safe and generic.

- [x] T04: Prepare `v0.3.0` release candidate docs.
  - Scope: README, changelog, release readiness, release process, and release notes.
  - Validation: Release validator `v0.3.0` release notes coverage passed.
  - Notes: Local gates passed; tag is deferred until after PR merge.

## Task-to-Spec Notes

- T02 maps to GitHub issue #1.
- T03 maps to GitHub issue #2.
- T04-P06 ship the existing v0.3.0 backlog remediation plus issue fixes.

## Execution Contract Tasks

- [x] P01: Complete phase 1 and record validation.
  - Goal: Establish durable public work package and branch state.
  - Inputs: Current public repo and open GitHub issues.
  - Outputs: Spec, tasks, and branch.
  - Validation: Context gate completed; issue pages opened; branch created.
  - Continue / stop decision: Continue.

- [x] P02: Complete phase 2 and record validation.
  - Goal: Issue #1 implementation and coverage.
  - Inputs: Memory scripts and release validator.
  - Outputs: Localized heading support.
  - Validation: Parser checks and release validator passed.
  - Continue / stop decision: Continue.

- [x] P03: Complete phase 3 and record validation.
  - Goal: Issue #2 documentation and coverage.
  - Inputs: Language policy and knowledge hub catalog.
  - Outputs: Public-safe bilingual routing guidance.
  - Validation: Release validator passed.
  - Continue / stop decision: Continue.

- [x] P04: Complete phase 4 and record validation.
  - Goal: Local release validation.
  - Inputs: Release docs and code changes.
  - Outputs: Passing local gates.
  - Validation: Windows PowerShell 5.1 and PowerShell 7 release validators, parser checks, public/private `git diff --check`, spec validation, and private overlay smoke passed.
  - Continue / stop decision: Continue to GitHub PR flow.

- [ ] P05: Complete phase 5 and record validation.
  - Goal: GitHub PR flow.
  - Inputs: Pushed branch and passing CI.
  - Outputs: Merged PR and closed issues.
  - Validation: GitHub PR/issue/API state.
  - Continue / stop decision:

- [ ] P06: Complete phase 6 and record validation.
  - Goal: Publish `v0.3.0`.
  - Inputs: Merged main and release notes.
  - Outputs: Pushed tag and GitHub Release.
  - Validation: GitHub release URL and tag state.
  - Continue / stop decision:
