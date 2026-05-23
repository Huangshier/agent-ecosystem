# Task Plan

- **Spec**: `docs/specs/public-promotion-boundaries/spec.md`
- **Status**: Done
- **Updated**: 2026-05-24

## Tasks

- [x] T01: Create issue-backed public work package
  - Scope: Issue #92 and `docs/specs/public-promotion-boundaries/`.
  - Validation: Issue records accepted public follow-up scope; spec and tasks
    define goals, non-goals, risks, acceptance, and stop rules.
  - Notes: Private audit artifacts remain outside the public repository.

- [x] T02: Add live knowledge and governance guidance
  - Scope: `knowledge-hub/knowledge/**`, `knowledge-hub/knowledge-catalog.md`,
    and `docs/agent-governance.md`.
  - Validation: New entries are discoverable and public-safe.
  - Notes: Added public promotion and long-session entries, catalog/index
    references, and cross-repository promotion guidance.

- [x] T03: Mirror bootstrap asset knowledge entries
  - Scope: `skills/project-bootstrap/assets/knowledge-hub-template/knowledge/**`
    and bundled `knowledge-catalog.md`.
  - Validation: Bundled asset mirror contains the same new entries and catalog
    references.
  - Notes: Added matching bundled knowledge entries and catalog/index
    references.

- [x] T04: Validate
  - Scope: Public working tree.
  - Validation: `git diff --check`, `validate_spec.ps1`, and
    `validate-release.ps1` pass.
  - Notes: `git diff --check` passed; spec validation passed; release
    validation passed with `PASS=52 FAIL=0 WARN=0 DEFERRED=0` after replacing
    sensitive-keyword-triggering wording with existing public-safe phrasing.

- [x] T05: Close out public work package
  - Scope: Durable spec/tasks state and PR-ready public handoff.
  - Validation: Work package records final validation evidence and does not
    preserve local branch status or PR wait state as durable project history.
  - Notes: Review transport details belong in GitHub metadata or local
    checkout memory, not this public spec.

## Task-to-Spec Notes
- T02 maps to P02 in the execution contract.
- T03 maps to P03 in the execution contract.
- T04 and T05 map to P04 in the execution contract.

## Conditional Loop Tasks
- Not applicable.

## Execution Contract Tasks

- [x] P01: Complete phase 1 and record validation
  - Goal: Create issue-backed public work package.
  - Inputs: Accepted issue #92 and local audit summary.
  - Outputs: Public spec/tasks.
  - Validation: Spec/tasks keep private evidence out and include stop rules.
  - Continue / stop decision: Continue; scope is public-safe and issue-linked.

- [x] P02: Complete phase 2 and record validation
  - Goal: Add live public knowledge entries and governance guidance.
  - Inputs: Existing standards, patterns, catalog, and governance docs.
  - Outputs: Live standard, pattern, catalog updates, and governance section.
  - Validation: Content review for public/private boundary and discoverability.
  - Continue / stop decision: Continue; live content is public-safe and
    discoverable.

- [x] P03: Complete phase 3 and record validation
  - Goal: Mirror bundled bootstrap asset knowledge entries.
  - Inputs: Live knowledge entries and asset snapshot.
  - Outputs: Bundled mirror entries and asset catalog/index updates.
  - Validation: Mirror review and release validator.
  - Continue / stop decision: Continue; bundled asset mirror was updated.

- [x] P04: Complete phase 4 and record validation
  - Goal: Validate and close out the public review handoff.
  - Inputs: Public diff.
  - Outputs: Validation evidence and closed public work package.
  - Validation: `git diff --check` passed; spec validation passed; release
    validation passed with `PASS=52 FAIL=0 WARN=0 DEFERRED=0`.
  - Continue / stop decision: Complete; ready for commit, push, and draft PR
    handoff through GitHub.
