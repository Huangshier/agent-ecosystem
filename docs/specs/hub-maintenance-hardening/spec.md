# Work Spec

- **Title**: Knowledge hub maintenance hardening
- **Slug**: hub-maintenance-hardening
- **Status**: Done
- **Owner**: maintenance
- **Updated**: 2026-05-09

## 1. Summary

- Resolve GitHub issues #7 and #8 by hardening knowledge hub maintenance scripts.
- Prevent accidental nested Git repositories and timestamp-only experience registry diffs.

## 2. Current Context

- `knowledge-hub/` is tracked as an ordinary directory in the public `agent-ecosystem` repository.
- `skills/project-bootstrap/scripts/init_hub.ps1` currently initializes Git whenever the target hub lacks `.git`.
- `knowledge-hub/scripts/rebuild_experience_index.ps1` and its project-bootstrap compatibility copy rewrite `updated_at_utc` on every rebuild.
- A previous local review found `knowledge-hub/.git` with no remote and no commits, plus a timestamp-only `knowledge-hub/knowledge/experience/index.json` diff.

## 3. Goals

- Make hub Git initialization explicit and caller-controlled.
- Keep `-CommitInitial` behavior working for callers that intentionally want an initialized hub repo.
- Make no-op experience index rebuilds preserve registry bytes and avoid timestamp-only diffs.
- Add release validation coverage for both behaviors.
- Merge through a PR that closes issues #7 and #8.

## 4. Non-Goals

- Do not split `knowledge-hub/` into a separate repository.
- Do not change public knowledge content.
- Do not alter experience promotion semantics except no-op registry write avoidance.
- Do not push directly to `main`.

## 5. Constraints

- Scripts must remain Windows PowerShell 5.1-compatible.
- Public artifacts must stay English-first and public-safe.
- Compatibility helper copies must remain byte-identical where the validator expects them to match.

## 6. Assumptions

- `updated_at_utc` should indicate a meaningful registry content update, not a script rerun.
- `-CommitInitial` is sufficient signal to initialize Git if a caller wants an initial commit.

## 7. Risks

- JSON comparison may be too textual unless it compares normalized entries rather than raw file formatting.
- Existing validation may rely on `init_hub.ps1` creating Git metadata implicitly.

## 8. Proposed Approach

- Add `-InitializeGit` to `init_hub.ps1` and gate `git init` behind `-InitializeGit` or `-CommitInitial`.
- Add no-op registry write detection to `rebuild_experience_index.ps1`.
- Apply the same no-op helper behavior to compatibility copies and promotion helpers for consistency.
- Extend release validation with explicit hub initialization and no-op rebuild checks.

## 9. Acceptance / Evidence

- `git diff --check` passes.
- PowerShell parser checks pass.
- Release validator passes with zero failures.
- PR merges and GitHub issues #7 and #8 close.
- Evidence: PR #9 passed local and hosted release validation, then merged on
  2026-05-09 to close issues #7 and #8.

## 10. Loop Contract

- Not used for this work item.

## 11. Execution Contract

- **Autonomy level**: bounded-autonomous
- **Phase list**:
  - P01: Create and audit issues #7 and #8.
  - P02: Implement script and validation changes.
  - P03: Run local validation.
  - P04: Push PR, wait for CI, merge, and confirm issue closure.
- **Continue rule**: Continue when the current phase has a clean review point and relevant validation passes.
- **Stop rule**: Stop for failed validation that cannot be fixed in scope, GitHub permission failure, public/private boundary ambiguity, destructive cleanup, or force-push requirement.
- **State record**: `docs/specs/hub-maintenance-hardening/tasks.md` records completed task status and validation evidence.

## 12. Open Questions

- None currently blocking execution.
