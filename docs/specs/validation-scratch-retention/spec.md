# Work Spec

- **Title**: Validation Scratch Retention
- **Slug**: validation-scratch-retention
- **Status**: Done
- **Owner**: Maintainer + agent
- **Updated**: 2026-05-22

## 1. Summary

- Add a minimal, guarded way to inspect and prune persistent release-validation
  scratch roots.
- Keep the default behavior non-destructive.

## 2. Current Context

- Issue #38 was created after a read-only inventory found a persistent local
  validation scratch area with many generated files.
- `scripts/validate-release.ps1` defaults to a system temp scratch directory,
  but maintainers can pass a persistent `-ScratchRoot` during local work.
- Existing path guards protect generated runtime paths from escaping the active
  scratch root, but there is no equivalent retention helper for old validation
  runs.

## 3. Goals

- Add a public helper that lists prunable validation run directories.
- Make the helper dry-run by default.
- Require an explicit apply switch before deleting anything.
- Prune only direct child directories that contain `validation-result.json`.
- Reuse the shared PowerShell path guard helper.
- Record lightweight machine-readable evidence.
- Cover the helper in release validation.

## 4. Non-Goals

- Do not delete any existing local scratch contents in this work item.
- Do not expand PR #37.
- Do not implement #30, #32, or #33.
- Do not add pre-commit hooks, GitHub rulesets, or branch protection changes.
- Do not change the validator default scratch root.

## 5. Constraints

- Public docs, specs, scripts, and engineering memory remain English-first.
- Keep private local paths and private overlay details out of public files.
- PowerShell scripts must remain compatible with Windows PowerShell 5.1.
- Destructive behavior must be opt-in and guarded.

## 6. Assumptions

- Direct child directories with `validation-result.json` are the safest minimal
  pruning target for public release-validation runs.
- Other scratch artifacts can remain for a later issue if evidence shows they
  need separate handling.

## 7. Risks

- A broad pruning tool could delete evidence that was intentionally retained.
- Overly narrow matching may leave some unrelated scratch artifacts untouched.

## 8. Proposed Approach

- Add `scripts/prune-validation-scratch.ps1`.
- Reject live runtime, repository root, filesystem root, and `.git` targets.
- Sort evidence-marked direct child directories by last write time and retain
  the newest N runs.
- Emit dry-run/apply evidence in JSON.
- Add release validator coverage using a temporary fixture.
- Document the helper in release process/readiness docs.

## 9. Acceptance / Evidence

- Issue #38 exists and is referenced by the PR.
- The pruning helper exists and dot-sources `scripts/lib/path-guard.ps1`.
- Dry run lists prunable directories without deleting them.
- `-Apply` prunes only older evidence-marked direct child directories.
- Release validation includes the retention helper check.
- `git diff --check` passes.
- Local release validation passes.

## 10. Loop Contract

- Not required. This is a bounded maintenance fix.

## 11. Execution Contract

- **Autonomy level**: bounded-autonomous
- **Phase list**:
  - P01: Create/accept issue #38 and this work package.
  - P02: Implement the guarded pruning helper and validator coverage.
  - P03: Update public docs and engineering memory.
  - P04: Validate, commit, push, and open a PR for #38.
- **Continue rule**: Continue while changes stay limited to validation scratch
  retention, docs, specs, and tracked public engineering memory.
- **Stop rule**: Stop for scope drift into #30/#32/#33, PR #37 expansion,
  ruleset changes, hooks, direct main pushes, auth-material disclosure, or any
  request to delete existing local scratch contents.
- **State record**: `docs/specs/validation-scratch-retention/tasks.md` and
  `.agents/plan.md`.

## 12. Open Questions

- Whether future work should cover non-`validation-result.json` scratch
  evidence directories. This issue intentionally keeps that out of scope.
