# Work Spec

- **Title**: Post-v0.4.3 Flow Guardrails
- **Slug**: post-v0-4-3-flow-guardrails
- **Status**: Active
- **Owner**: Codex
- **Updated**: 2026-05-20

## 1. Summary
- Close the remaining post-`v0.4.3` process drift from the May 2026 audit.
- Add lightweight pull request base/stack safety guardrails.
- Add CI concurrency while keeping the current full hosted release validation
  gate intact.
- Re-triage deferred issues only after the state closeout, PR guardrails, and
  CI concurrency changes have landed.

## 2. Current Context
- Repository: `Huangshier/agent-ecosystem`.
- Published release remains `v0.4.3`.
- PR #76 closed out accepted stabilization engineering memory after #74.
- Open deferred issues remain #67, #56, and #23.
- Existing `protect-main` ruleset requires pull requests and four release
  validation checks before merge.

## 3. Goals
- Add PR template fields for base branch and stacked-PR intent.
- Add a PR base guard workflow that fails accidental non-`main` bases unless
  the PR is explicitly marked as an intentional stack.
- Add release-validation concurrency so stale same-branch runs are canceled.
- Record the decision not to split CI yet.
- Refresh public changelog, release readiness, and engineering memory state.
- Re-triage #67, #56, and #23 after repository changes are merged.

## 4. Non-Goals
- Do not change repository settings, rulesets, branch protection, secrets,
  runners, tags, or GitHub Releases.
- Do not enable `allow_update_branch` in this repository change.
- Do not split release validation into lightweight/full CI jobs in this change.
- Do not implement #67, #56, or #23 as part of the triage pass.
- Do not delete local or remote branches as part of this work.

## 5. Constraints
- Public repository artifacts are English-first.
- PRs must target `main` unless explicitly marked as intentional stacks.
- Required hosted release validation remains the hard merge gate.
- Workflow-level path filters are avoided for required checks because skipped
  workflows can leave required checks pending.

## 6. Assumptions
- The May 2026 audit findings about stale state, stacked PR merge risk, and CI
  run duplication are valid.
- The maintainer authorized direct execution through the repository-required PR
  path for this status and workflow cleanup.

## 7. Risks
- Adding a new workflow changes CI behavior and needs full local release
  validation plus hosted checks.
- A PR base guard can block legitimate stacked review PRs if the explicit label
  and body marker are omitted.
- Splitting CI now would require ruleset coordination and could weaken or stall
  required checks if done too quickly.

## 8. Proposed Approach
- Keep P1 and P2 in one narrowly scoped PR because both are workflow hygiene
  changes from the same audit.
- Add the PR base guard as an ordinary workflow and document the expected
  `stack:allowed` marker.
- Add only workflow-level concurrency to release validation.
- Update release process docs to state that CI is not split yet.
- Use GitHub issue comments/label updates for P3 triage after the PR lands.

## 9. Acceptance / Evidence
- `git diff --check` passes.
- Full local release validation passes with zero failures, warnings, and
  deferred checks.
- Hosted required release validation checks pass on the PR.
- The PR is merged to `main`.
- #67, #56, and #23 each have an updated triage comment or body state after the
  repository changes land.

## 10. Loop Contract
- Not applicable.

## 11. Execution Contract
- **Autonomy level**: bounded-autonomous
- **Phase list**:
  - P01: P0 closeout via PR #76.
  - P02: Implement PR base guardrails.
  - P03: Add CI concurrency and record the no-split decision.
  - P04: Validate, open, and merge the guardrail PR through required checks.
  - P05: Re-triage deferred issues #67, #56, and #23.
- **Continue rule**: Continue to the next phase when repository changes stay
  within this spec, validation passes, and required hosted checks pass.
- **Stop rule**: Stop if a phase requires repository settings/ruleset changes,
  release publication, tag movement, branch deletion, failed checks that cannot
  be fixed in scope, or implementation of #67/#56/#23.
- **State record**: `docs/specs/post-v0-4-3-flow-guardrails/tasks.md`,
  `.agents/process.txt`, and `.agents/plan.md`.

## 12. Open Questions
- None for repository-file changes.
- Repository settings changes such as `allow_update_branch` remain a separate
  maintainer-controlled decision.
