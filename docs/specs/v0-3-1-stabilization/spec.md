# Work Spec

- **Title**: v0.3.1 stabilization
- **Slug**: v0-3-1-stabilization
- **Status**: Done
- **Owner**: Maintainer + agent
- **Updated**: 2026-05-09

## 1. Summary

Stabilize the public `agent-ecosystem` surface before the next release by
clarifying the workflow-kernel positioning, fixing release metadata drift,
documenting a lightweight public reader review, and refreshing GitHub Actions
runtime maintenance.

## 2. Current Context

- Current public release: `v0.3.0`.
- Active public issues:
  - #10 README positioning and extension story.
  - #11 release validation metadata consistency.
  - #12 lightweight public reader review for maintainers.
  - #13 GitHub Actions runtime deprecation risk.
- The local release validator currently reports:
  `PASS=32 FAIL=0 WARN=0 DEFERRED=0`.
- The project is a workflow kernel for agent-assisted software projects, not an
  agent runtime or universal workflow bundle.

## 3. Goals

- Resolve #11 by making release validation metadata consistent and harder to
  drift.
- Resolve #10 and #12 by updating the README positioning, localized README
  entry, and lightweight maintainer review guidance.
- Resolve #13 by updating GitHub Actions versions where needed while preserving
  the existing validation matrix.
- Reach a release-ready state for maintainer approval.

## 4. Non-Goals

- Do not publish a release, create a tag, or update GitHub Releases without
  maintainer approval.
- Do not add Bash or Zsh wrappers in this stabilization work.
- Do not expand public domain packs or introduce new domain skills.
- Do not turn the project into an agent runtime, model orchestration framework,
  or task scheduler.
- Do not publish private overlay details, local migration mappings, or
  sensitive audit state.

## 5. Constraints

- Public repository docs and issues are English-first.
- Chinese documentation may live in `README.zh-CN.md` or `docs/zh-CN/`.
- Keep PRs reviewable and issue-scoped.
- Run local release validation for repository changes and wait for hosted CI
  before merging public PRs.
- Stop at the release preparation stage for maintainer approval.

## 6. Assumptions

- `v0.3.1` is a stabilization and positioning release, not a feature expansion
  release.
- The release validator is the source of truth for the current validation
  summary.
- Maintainer-facing process should remain lightweight.

## 7. Risks

- README wording can overemphasize non-goals and make the project feel smaller
  than it is.
- Heavy process wording can undermine the lightweight kernel story.
- Action version updates may require syntax changes or reveal hosted CI
  behavior differences.

## 8. Proposed Approach

- PR 1: fix #11 and establish this public work package.
- PR 2: fix #10 and #12 together because positioning and reader-review process
  are coupled.
- PR 3: fix #13 after checking official action version/runtime information.
- After all PRs are merged and validation is green, stop for release
  confirmation.

## 9. Acceptance / Evidence

- Issues #10, #11, #12, and #13 are closed by merged public PRs.
- Local release validation passes with zero failures, warnings, and deferred
  checks.
- Hosted release validation passes on Windows PowerShell 5.1, Windows pwsh,
  Ubuntu pwsh, and macOS pwsh.
- Public docs describe the project as a workflow kernel and avoid stale
  first-release framing in the main README.
- The final state is ready for maintainer release approval.

## 10. Loop Contract

Not applicable.

## 11. Execution Contract

- **Autonomy level**: bounded-autonomous
- **Phase list**:
  - P01: Resolve #11 release metadata consistency.
  - P02: Resolve #10 and #12 README positioning and maintainer review.
  - P03: Resolve #13 GitHub Actions runtime maintenance.
  - P04: Refresh state and stop for release confirmation.
- **Continue rule**: Continue to the next phase after local validation, PR
  merge, hosted CI success, and issue closure are confirmed.
- **Stop rule**: Stop for release/tag/publish approval, destructive git
  operations, force-push, authentication or access failure, skipped acceptance
  checks, scope drift, unrelated refactor pressure, or unresolved ambiguity.
- **State record**: `docs/specs/v0-3-1-stabilization/tasks.md`.

## 12. Open Questions

- The exact release version and publication timing remain maintainer decisions.
