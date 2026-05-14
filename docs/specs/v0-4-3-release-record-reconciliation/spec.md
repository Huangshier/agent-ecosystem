# Work Spec

- **Title**: v0.4.3 Release Record Reconciliation
- **Slug**: v0-4-3-release-record-reconciliation
- **Status**: Done
- **Owner**: Codex
- **Updated**: 2026-05-14

## 1. Summary
- Reconcile public repository release records with the already published GitHub
  Release `v0.4.3`.
- Correct documentation and release validation checks that still describe
  `v0.4.3` as a release-prep draft or as not yet published.

## 2. Current Context
- Local `main`, `origin/main`, local tag `v0.4.3`, and remote tag `v0.4.3`
  all point to `26072b7f8e25e2a5b1092b6af45d47ae1c43cac8`.
- GitHub Release `v0.4.3` is published, non-draft, and non-prerelease:
  https://github.com/Huangshier/agent-ecosystem/releases/tag/v0.4.3
- Release `v0.4.3` was published at `2026-05-14T04:26:37Z`.
- Several tracked release records still say the latest public release is
  `v0.4.2` or that `v0.4.3` has not been tagged or published.
- `scripts/validate-release.ps1` currently validates the old release-prep
  wording, which allows the drift to pass.

## 3. Goals
- Update `README.md` and `README.zh-CN.md` to identify `v0.4.3` as the current
  published release.
- Update `CHANGELOG.md`, `docs/release-readiness.md`, and
  `docs/releases/v0.4.3.md` to use published-release wording and evidence.
- Update `docs/release-process.md` and `scripts/validate-release.ps1` so the
  release validator expects published `v0.4.3` release notes instead of
  release-prep notes.
- Update public `.agents` state so it no longer treats PR #63, issue #57, or
  `v0.4.2` as the current active release state.
- Record the release closeout rule that tracked `.agents` files should not
  chase per-push PR head CI timestamps through memory-only commits.

## 4. Non-Goals
- Do not move or recreate tag `v0.4.3`.
- Do not publish, edit, or delete GitHub Releases.
- Do not close, reopen, or edit GitHub issues.
- Do not implement `v0.5.0`, issue #56, installer/runtime behavior changes,
  profile changes, or broad documentation IA changes.
- Do not push directly to `main`, merge PRs, or change repository settings.

## 5. Constraints
- Public-facing artifacts are English-first, with Chinese content limited to
  the existing `README.zh-CN.md` surface for this work.
- Private overlay details, local private paths, local auth material, and private
  review material must not be copied into public docs or memory.
- The branch must stay scoped to release record reconciliation and validator
  checks that enforce the corrected state.
- Scope control: do not include unrelated refactors, cleanup, or behavior
  changes unless they are required to make the requested release records
  consistent.

## 6. Assumptions
- The published GitHub Release `v0.4.3` is the source of truth for published
  status and release URL.
- The existing `v0.4.3` tag target remains authoritative; this work only
  updates records on the post-release reconciliation branch.
- Local release validation is sufficient for this branch until a maintainer
  explicitly authorizes PR, merge, push, tag, or release actions.

## 7. Risks
- Release records may duplicate facts across README, changelog, readiness
  notes, release notes, and validator checks; all touched records must use the
  same status.
- Validator updates could accidentally weaken the release gate if they only
  remove old checks instead of asserting published-release evidence.
- Tracked `.agents` files can drift again if they record transient PR head or
  hosted-check wait state after every push.

## 8. Proposed Approach
- Use the confirmed release state as the baseline.
- Patch only the requested public records and the minimum validator logic needed
  to reject stale release-prep wording for `v0.4.3`.
- Update `.agents/process.txt`, `.agents/plan.md`, and `.agents/notes.md` to
  point at this active spec and the current published-release baseline.
- Run whitespace and release validation checks before claiming completion.

## 9. Acceptance / Evidence
- `git diff --check` passed on 2026-05-14.
- `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-release.ps1 -ScratchRoot "$env:TEMP\agent-ecosystem-v043-reconcile-validation-2"`
  passed on 2026-05-14 with `PASS=46 FAIL=0 WARN=0 DEFERRED=0`.
- A manual diff review should show no tag movement, GitHub Release publication or
  mutation command, issue mutation, `v0.5.0` implementation, or unrelated
  runtime/profile behavior change.
- If a requested acceptance check cannot be run, record the command, failure
  reason, and residual risk before marking this spec done.

## 10. Loop Contract
- Not applicable.

## 11. Execution Contract
- **Autonomy level**: bounded-autonomous
- **Phase list**:
  - P01: Confirm release baseline and create scoped branch/spec.
  - P02: Reconcile release docs and validator expectations. Completed.
  - P03: Sync public `.agents` state and record closeout evidence. Completed.
  - P04: Run required validation and review final diff. Completed.
- **Continue rule**: Continue to the next phase when the current phase only
  performs in-repository, reversible edits within the stated file scope and its
  validation evidence is recorded or still pending for a later validation
  phase.
- **Stop rule**: Stop for any requested tag movement, GitHub Release mutation,
  issue mutation, direct `main` push, repository setting change, missing release
  source of truth, validator failure that cannot be fixed without scope
  expansion, private data exposure risk, unrelated refactor pressure, or skipped
  acceptance check that would make completion unverifiable.
- **State record**: `docs/specs/v0-4-3-release-record-reconciliation/tasks.md`
  and `.agents/plan.md`.

## 12. Open Questions
- None blocking. Any remote PR, merge, push, tag, release, or issue action
  remains maintainer-authorized only.
