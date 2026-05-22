# Task Plan

- **Spec**: `docs/specs/spec-state-reconciliation/spec.md`
- **Status**: Done
- **Updated**: 2026-05-22

## Tasks

- [x] T01: Scan active specs and tasks
  - Scope: `docs/specs/**/spec.md` and `docs/specs/**/tasks.md`.
  - Validation: Found 13 work packages with active status markers.

- [x] T02: Verify GitHub state
  - Scope: linked issues, PRs, merge commits, and release evidence for each
    active work package.
  - Validation: Each audited work package has closed issue, merged PR, or
    published release evidence.

- [x] T03: Reconcile durable spec state
  - Scope: affected `spec.md` and `tasks.md` files.
  - Validation: Completed work packages were changed to `Done`; stale PR
    publish, hosted-check wait, merge wait, and maintainer-review waiting text
    was rewritten to durable completion evidence.

- [x] T04: Update adjacent readiness wording
  - Scope: `docs/release-readiness.md`.
  - Validation: `full` / `dev` wording no longer says `v0.1.0` placeholders;
    behavior remains unchanged.

- [x] T05: Validate scoped reconciliation
  - Scope: docs-only state reconciliation.
  - Validation: `git diff --check`; release validator with a temporary scratch
    root; PR body requirement recorded as `Refs #23`, not a closing keyword.

## Notes

- This work does not implement #23, publish a release, modify profiles, add
  public domain packs, or change tags, releases, settings, rulesets, sensitive
  repository configuration, branch protection, or public `main`.
