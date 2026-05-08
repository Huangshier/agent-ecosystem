# Work Spec

- **Title**: v0.3.0 public maintenance and release
- **Slug**: v0-3-0-public-maintenance
- **Status**: Active
- **Owner**: release maintenance
- **Updated**: 2026-05-08

## 1. Summary

- Resolve GitHub issues #1 and #2 through a standard public collaboration flow.
- Prepare and publish the next public release after validation passes.

## 2. Current Context

- Local public `main` contains the v0.3.0 backlog remediation commits and is ahead of `origin/main`.
- Issue #1 covers localized context discovery headings for memory diagnostics.
- Issue #2 covers bilingual public/private workflow routing guidance.
- The private overlay CI blocker is private-side state and does not block public release publication.

## 3. Goals

- Add localized `Summary` / `Keywords` heading support to memory diagnostics and upgrade analysis.
- Document public/private bilingual routing in public-safe language.
- Extend release validation so both changes are covered by the release gate.
- Update release candidate documentation for `v0.3.0`.
- Push a review branch, open and merge a pull request, close the issues, and publish the public release when validation passes.

## 4. Non-Goals

- Do not publish private overlay content, local machine paths, private migration mappings, or sensitive audit detail.
- Do not implement Bash or Zsh wrappers in this release.
- Do not resolve private CI visibility issues inside this public release.
- Do not force-push or rewrite public history.

## 5. Constraints

- Public repository artifacts must be English-first.
- Private specs and memory remain outside this public work item.
- Windows PowerShell 5.1 and PowerShell 7 release validator paths must pass.
- Use ordinary GitHub issue, branch, pull request, merge, issue close, and release publication flow.
- Scope control: do not include unrelated refactors, cleanup, or behavior changes unless they are explicit goals.

## 6. Assumptions

- Maintainer authorization in the current session allows normal release publication after tests pass.
- Issue #1 and #2 are the public tracking issues for the two requested follow-ups.
- Existing local backlog remediation commits are intended to ship in `v0.3.0`.

## 7. Risks

- PowerShell 5.1 may reject non-ASCII scripts unless encoding remains compatible.
- GitHub API permissions may block PR merge or release creation.
- Hosted CI may fail on a platform-specific issue that local validation does not catch.
- Release docs may drift from validator pass counts if coverage changes late.

## 8. Proposed Approach

- Add a small shared-in-file heading matcher to relevant memory scripts.
- Add a public-safe knowledge standard and link it from the catalog and language policy.
- Add release validator checks for localized context metadata, bilingual routing docs, and `v0.3.0` notes.
- Validate locally on Windows PowerShell 5.1 and PowerShell 7.
- Push a branch, open a PR with `Closes #1` and `Closes #2`, wait for hosted CI, then merge and publish `v0.3.0`.

## 9. Acceptance / Evidence

- `git diff --check` passes.
- PowerShell parser checks pass.
- `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-release.ps1 -ScratchRoot <scratch> -Json` passes.
- `pwsh -NoProfile -File .\scripts\validate-release.ps1 -ScratchRoot <scratch> -Json` passes.
- GitHub PR is merged and issues #1 and #2 are closed.
- GitHub Release `v0.3.0` is published.
- Any skipped or unavailable acceptance check is recorded before claiming completion.

## 10. Loop Contract

- Not used for this work item.

## 11. Execution Contract

- **Autonomy level**: bounded-autonomous
- **Phase list**:
  - P01: Create public work package and review branch.
  - P02: Implement issue #1 localized metadata support and validator coverage.
  - P03: Implement issue #2 bilingual routing docs and validator coverage.
  - P04: Update `v0.3.0` release docs and run local validation gates.
  - P05: Push branch, open/merge PR, close issues through GitHub.
  - P06: Tag and publish `v0.3.0`.
- **Continue rule**: Continue to the next phase when the current phase has a clean diff review point and its relevant validation passes.
- **Stop rule**: Stop for failed required validation that cannot be fixed in scope, GitHub permission failure, unresolved public/private boundary ambiguity, force-push requirement, destructive cleanup, or any request to publish private content.
- **State record**: `docs/specs/v0-3-0-public-maintenance/tasks.md` records phase status and validation evidence.

## 12. Open Questions

- None currently blocking execution.
