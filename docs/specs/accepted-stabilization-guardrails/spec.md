# Work Spec

- **Title**: Accepted Stabilization Guardrails
- **Slug**: accepted-stabilization-guardrails
- **Status**: Done
- **Owner**: Codex
- **Updated**: 2026-05-20

## 1. Summary
- Executed the accepted public stabilization issues as reviewable pull
  requests and merged them to `main`.
- Repaired the #71 stacked-base merge accident with replacement PR #75.
- Kept #67, #56, and #23 deferred and out of scope.

## 2. Current Context
- Repository: `Huangshier/agent-ecosystem`.
- Final `main` and `origin/main`:
  `c35c35917c2dce55260f400312a4a5e15cd00932`.
- Open pull requests are empty after closeout.
- Accepted issues in scope:
  - #69: closeout write-scope guardrails.
  - #65 Phase B/C: cross-workspace root verification and `/goal` source
    evidence.
  - #65 Phase A: generic high-risk evidence gate.
  - #68: project-bootstrap analyze and language refresh semantics.
  - #66: memory-scope language governance.
- Deferred issues remain out of scope: #67, #56, and #23.

## 3. Goals
- Merged #70, #75, #72, #73, and #74 to `main`.
- Closed #65, #66, #68, and #69 as completed.
- Preserved the public/private boundary and avoided adding domain-specific
  incubator templates to the public kernel.

## 4. Non-Goals
- Do not implement #67 body-level language audit helpers.
- Do not implement #56 or #23 domain-pack governance.
- Do not redesign the README.
- Do not change `full` or `dev` profile behavior.
- Do not add private overlay content, local-only paths, authentication
  material, private audit notes, or domain-specific templates to this public
  repository.
- Do not implement #67, #56, #23, or README redesign follow-up as part of this
  completed sequence.
- Do not tag, publish a release, or change repository settings, secrets,
  rulesets, hooks, or runners.

## 5. Constraints
- Public repository artifacts are English-first.
- Every repository diff remained within the accepted issue scope for the active
  PR.
- Issue branches and pull requests were used for all public writes.
- Before opening or updating each PR, run:
  - `git diff --check`
  - `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-release.ps1 -ScratchRoot <scratch>`
- Hosted checks were recorded for merged PRs and final `main`.

## 6. Assumptions
- The maintainer authorized push, PR readiness, merge, and issue closeout for
  the accepted sequence during incident repair.
- The full local release validator remains the authoritative local regression
  gate for these public skill and governance changes.

## 7. Risks
- Multiple phases touched shared skill and memory files, and tracked `.agents`
  state churn made stacked-PR incident repair harder than necessary.
- `/goal` source-evidence requirements must stay generic and must not rely on
  private reference material.
- Hosted pull request checks can fail to appear after retarget / force-push
  until a new pull_request synchronize event changes the head SHA.
- Public memory updates can drift into a second copy of this spec if they are
  not kept concise.

## 8. Proposed Approach
- #70 / #69 established closeout write-scope guardrails.
- #75 replaced the accidentally stacked #71 merge and landed #65 Phase B/C on
  `main`.
- #72 landed #65 Phase A high-risk evidence gate on `main`.
- #73 landed #68 bootstrap analyze semantics on `main`.
- #74 landed #66 memory-scope language governance on `main`.
- For #73 and #74 incident repair, each PR's net scoped diff was applied to
  latest `main` instead of replaying old stacked `.agents` state commits.

## 9. Acceptance / Evidence
- #70, #75, #72, #73, and #74 are merged to `main`.
- #65, #66, #68, and #69 are closed as completed.
- Final `git diff --check` passed.
- Final local release validation passed with
  `PASS=46 FAIL=0 WARN=0 DEFERRED=0`.
- Final hosted Release validation passed on `main`:
  https://github.com/Huangshier/agent-ecosystem/actions/runs/26160716089
- #67, #56, and #23 remain deferred and unimplemented.

## 10. Loop Contract
- Not applicable. This is a fixed PR sequence.

## 11. Execution Contract
- **Autonomy level**: bounded-autonomous
- **Phase list**:
  - P01: create this public-safe execution package and refresh stale public
    hot memory.
  - P02: open PR-A for #69 closeout write-scope guardrails.
  - P03: open PR-B for #65 Phase B/C cross-workspace root verification and
    `/goal` source evidence.
  - P04: open PR-C for #65 Phase A high-risk evidence gate.
  - P05: open PR-D for #68 project-bootstrap analyze semantics.
  - P06: open PR-E for #66 memory-scope language governance.
  - P07: hand off the full draft PR sequence for maintainer review.
  - P08: repair #71 stacked-base merge accident, merge the replacement PR, and
    merge the remaining accepted PRs onto `main`.
  - P09: memory-governance closeout.
- **Continue rule**: Continue to the next phase when all of these conditions
  hold.
  - The current phase stays within accepted issue scope.
  - Local validation passes for the current branch.
  - The issue branch is pushed and the draft PR is created.
  - Public and private phase state are updated.
- **Stop rule**: Stop and hand off when any of these conditions occurs.
  - Continuing would require tagging, releasing, changing repository settings,
    secrets, rulesets, hooks, or runners, or force-pushing `main`.
  - Continuing would require implementing #67, #56, #23, or a README redesign.
  - Validator or hosted checks fail and cannot be fixed within the current
    issue scope.
  - Source/reference evidence is missing for a `/goal`-style migration prompt.
  - Repository root or write-scope authorization is ambiguous.
  - Continuing would introduce private overlay content, local-only paths,
    authentication material, private audit notes, or domain-specific templates.
- **State record**: `docs/specs/accepted-stabilization-guardrails/tasks.md`,
  `.agents/process.txt`, and `.agents/plan.md`.

## 12. Open Questions
- None. Accepted stabilization scope is complete.
