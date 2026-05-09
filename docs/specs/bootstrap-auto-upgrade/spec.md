# Work Spec

- **Title**: Bootstrap memory auto-upgrade
- **Slug**: bootstrap-auto-upgrade
- **Status**: Active
- **Owner**: maintenance
- **Updated**: 2026-05-09

## 1. Summary

- Resolve GitHub issues #4 and #5 by making legacy memory upgrade handling explicit in both the project-bootstrap script and skill workflow.
- Add a non-interactive `-AutoUpgrade` path for caller-approved bootstrap runs that should plan and apply memory normalization when candidates are detected.

## 2. Current Context

- `skills/project-bootstrap/scripts/bootstrap_project.ps1` already supports `-AnalyzeMemoryUpgrade`, `-PlanMemoryUpgrade`, and `-ApplyMemoryUpgrade`.
- Default bootstrap runs only print a hint when legacy memory candidates are detected.
- `skills/project-bootstrap/SKILL.md` documents manual upgrade commands but does not define a decision point between bootstrap and verification.
- Issue #4 requests a `-AutoUpgrade` switch.
- Issue #5 requests a workflow decision point so agents do not silently skip detected memory candidates.

## 3. Goals

- Add `-AutoUpgrade` to `bootstrap_project.ps1`.
- Keep default bootstrap behavior read-only for memory analysis.
- Document when an agent should use auto-upgrade, manual plan/apply, or ask the user.
- Extend release validation to exercise the new auto-upgrade path.
- Push a review branch, open and merge a PR, and close issues #4 and #5.

## 4. Non-Goals

- Do not change the proposal format produced by `memory_upgrade.ps1`.
- Do not remove the existing manual analyze, plan, or apply modes.
- Do not migrate unrelated project memory or knowledge hub entries.
- Do not publish private overlay details.

## 5. Constraints

- Public artifacts must be English-first.
- PowerShell scripts must remain Windows PowerShell 5.1-compatible.
- Default bootstrap must not rewrite memory unless the caller explicitly chooses an apply path.
- Scope control: avoid unrelated refactors or release doc churn.

## 6. Assumptions

- A caller who passes `-AutoUpgrade` is explicitly authorizing the default approved actions in the generated proposal.
- For ambiguous user intent, the skill workflow should ask before applying memory rewrites.
- Existing release validation is the primary local acceptance gate.

## 7. Risks

- Auto-upgrade could be too aggressive if it is allowed to combine with contradictory switches.
- Release validation may be slow because installer/runtime smoke tests are broad.
- GitHub merge may be blocked by CI or permissions.

## 8. Proposed Approach

- Add switch validation so `-AutoUpgrade` cannot be combined with manual memory upgrade mode switches or skip analysis.
- Implement `-AutoUpgrade` as analyze first, then plan and apply only when findings exist.
- Emit proposal, backup, and result paths for auditability.
- Update `project-bootstrap` skill docs and README with the decision point.
- Add release validator coverage using a temporary project with injected legacy memory findings.

## 9. Acceptance / Evidence

- `git diff --check` passes for the final staged changes.
- PowerShell parser checks pass.
- Targeted auto-upgrade smoke passes.
- `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-release.ps1 -ScratchRoot <scratch> -Json` passes.
- GitHub PR is merged and issues #4 and #5 are closed.
- Any skipped or unavailable acceptance check is recorded before claiming completion.

## 10. Loop Contract

- Not used for this work item.

## 11. Execution Contract

- **Autonomy level**: bounded-autonomous
- **Phase list**:
  - P01: Triage issues and create work package.
  - P02: Implement script and workflow documentation.
  - P03: Add and run validation.
  - P04: Push branch, open PR, wait for checks, merge, and confirm issue closure.
- **Continue rule**: Continue to the next phase when the current phase has a reviewable diff and relevant validation passes.
- **Stop rule**: Stop for failed required validation that cannot be fixed in scope, GitHub permission failure, force-push requirement, destructive cleanup, public/private boundary ambiguity, or unrelated refactor pressure.
- **State record**: `docs/specs/bootstrap-auto-upgrade/tasks.md` records task status and validation evidence.

## 12. Open Questions

- None currently blocking execution.
