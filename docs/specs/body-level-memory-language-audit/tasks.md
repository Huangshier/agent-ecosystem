# Task Plan

- **Spec**: `docs/specs/body-level-memory-language-audit/spec.md`
- **Status**: Done
- **Updated**: 2026-05-22

## Tasks

- [x] T01: Implement the read-only audit helper
  - Scope: `skills/project-bootstrap/scripts/audit_memory_language.ps1`
  - Validation: direct JSON and human-readable smoke runs against a temporary
    fixture project passed.
  - Notes: Helper must not write project memory.

- [x] T02: Add release validation integration
  - Scope: `scripts/validate-release.ps1` scratch fixture coverage and required
    file checks.
  - Validation: full release validator passed with
    `PASS=50 FAIL=0 WARN=0 DEFERRED=0`.
  - Notes: Cover metadata/body mismatch, opposite-language metadata with
    correct body, fenced code, protected literals, and mixed body text.

- [x] T03: Update documentation references
  - Scope: project-bootstrap docs, language policy, and release validation
    documentation.
  - Validation: validator content checks and manual review for no rewrite
    claims passed.
  - Notes: Keep docs explicit that audit is read-only and heuristic.

- [x] T04: Publish review branch and PR
  - Scope: commit, push branch, open PR for issue #67, and complete hosted
    checks before merge.
  - Validation: PR #84 merged to `main` at
    `df208697889f4a3104f234c4b4c5aef4a79c1c22`; issue #67 is closed.
  - Notes: No direct `main` push, tag, release, settings, ruleset, or
    sensitive repository configuration changes were made.

## Task-to-Spec Notes
- Issue #67 is intentionally separate from #79; this work provides audit
  capability but does not change migration apply semantics.

## Conditional Loop Tasks
- Not applicable.

## Execution Contract Tasks
- [x] P01: Complete helper implementation and targeted smoke
  - Goal: Reusable read-only audit helper.
  - Inputs: issue #67, private audit recommendation, existing migration helper
    conventions.
  - Outputs: `audit_memory_language.ps1`.
  - Validation: helper smoke command passed.
  - Continue / stop decision: continued; no mutation behavior was introduced.

- [x] P02: Complete validator and docs integration
  - Goal: Release validation covers helper behavior and docs point users to it.
  - Inputs: release validator fixture patterns and project-bootstrap docs.
  - Outputs: validator check and docs updates.
  - Validation: targeted and full validator checks passed.
  - Continue / stop decision: continued; validation failures were resolved.

- [x] P03: Complete publish and PR check phase
  - Goal: Reviewable PR with passing local and hosted checks.
  - Inputs: final diff and validation evidence.
  - Outputs: PR #84 merged to `main`.
  - Validation: Local validation passed; PR #84 hosted checks passed before
    merge.
  - Continue / stop decision: Complete; #67 is closed by PR #84.
