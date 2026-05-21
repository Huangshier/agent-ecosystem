# Task Plan

- **Spec**: `docs/specs/local-root-agents-runtime-state/spec.md`
- **Status**: Done
- **Updated**: 2026-05-21

## Tasks

- [x] T01: Update public guidance and durable spec boundaries
  - Scope: root `AGENTS.md`, `docs/specs/README.md`, governance and release
    process docs as needed.
  - Validation: manual diff review and release validator content checks.
  - Notes: Keep clean-clone startup independent from untracked root `.agents/`.

- [x] T02: Migrate or discard tracked root `.agents` content
  - Scope: promote reusable experience content, discard stale hot state, and
    remove root `.agents/` from the Git index.
  - Validation: `git ls-files .agents` returns no files.
  - Notes: Preserve local files in the working tree.

- [x] T03: Update release validation
  - Scope: root `.agents` tracking check, spec-state boundary check, and
    existing assertions that assumed tracked root `.agents`.
  - Validation: targeted validator runs plus full release validation.
  - Notes: Keep templates, examples, fixtures, and generated scratch projects
    allowed.

- [x] T04: Complete local validation handoff
  - Scope: prepare a scoped branch for #78 with no tag, release, repository
    settings, ruleset, protected configuration, or protected-branch changes.
  - Validation: `git diff --check` and full release validation.
  - Notes: Pull request creation and hosted check readback are reported outside
    this durable spec so merged docs do not preserve transient PR wait state.

## Task-to-Spec Notes
- This PR closes #78 only.
