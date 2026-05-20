# Work Spec

- **Title**: Accepted Stabilization Guardrails
- **Slug**: accepted-stabilization-guardrails
- **Status**: Active
- **Owner**: Codex
- **Updated**: 2026-05-20

## 1. Summary
- Execute the accepted public stabilization issues as a reviewable draft PR
  sequence.
- Keep each change public-safe, issue-scoped, and locally validated before it
  is handed to maintainers.
- Keep #67 deferred until the memory-scope surfaces and output contract are
  clarified by #66.

## 2. Current Context
- Repository: `Huangshier/agent-ecosystem`.
- Baseline: `main` and `origin/main` at
  `5e217c9549a8436ab8e8b1a10a6aa400be6d0466`.
- Open pull requests were empty when this work started.
- Accepted issues in scope:
  - #69: closeout write-scope guardrails.
  - #65 Phase B/C: cross-workspace root verification and `/goal` source
    evidence.
  - #65 Phase A: generic high-risk evidence gate.
  - #68: project-bootstrap analyze and language refresh semantics.
  - #66: memory-scope language governance.
- Deferred issues remain out of scope: #67, #56, and #23.

## 3. Goals
- Open PR-A through PR-E as draft pull requests.
- Record the issue mapping, branch/base relationship, local validation, and
  hosted check status for each PR.
- Keep public `.agents` memory and this spec aligned at each PR-ready
  boundary.
- Preserve the public/private boundary and avoid adding domain-specific
  incubator templates to the public kernel.

## 4. Non-Goals
- Do not implement #67 body-level language audit helpers.
- Do not implement #56 or #23 domain-pack governance.
- Do not redesign the README.
- Do not change `full` or `dev` profile behavior.
- Do not add private overlay content, local-only paths, authentication
  material, private audit notes, or domain-specific templates to this public
  repository.
- Do not push `main`, merge PRs, close issues, mark PRs ready for review, tag,
  publish a release, or change repository settings, secrets, rulesets, hooks,
  or runners.

## 5. Constraints
- Public repository artifacts are English-first.
- Every repository diff must remain within the accepted issue scope for the
  active PR.
- Use issue branches and draft pull requests.
- Stacked PRs are allowed when repeated edits to shared skill or memory files
  would make independent branches harder to review.
- Before opening or updating each draft PR, run:
  - `git diff --check`
  - `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-release.ps1 -ScratchRoot <scratch>`
- Hosted checks should be recorded when available. If they are unavailable or
  still pending, record the observed state instead of creating memory-only
  commits solely to refresh timestamps.

## 6. Assumptions
- The maintainer has accepted #69, #65, #68, and #66 for implementation.
- The maintainer has authorized pushing public issue branches and creating
  draft PRs.
- Draft PR creation targets `Huangshier/agent-ecosystem`.
- The full local release validator is the authoritative local regression gate
  for these public skill and governance changes.

## 7. Risks
- Multiple phases touch shared skill and memory files, so stacked PRs may be
  clearer than independent branches.
- `/goal` source-evidence requirements must stay generic and must not rely on
  private reference material.
- Hosted checks can be delayed or unavailable through the GitHub API; the PR
  body must state the observed status.
- Public memory updates can drift into a second copy of this spec if they are
  not kept concise.

## 8. Proposed Approach
- PR-A / #69 establishes the public execution state and closeout write-scope
  guardrails.
- PR-B / #65 Phase B/C adds cross-workspace root verification and `/goal`
  source/reference evidence requirements.
- PR-C / #65 Phase A adds a generic high-risk evidence gate.
- PR-D / #68 clarifies project-bootstrap analyze, refresh, and language
  semantics.
- PR-E / #66 completes memory-scope discovery surfaces and quality gates.

## 9. Acceptance / Evidence
- For each PR:
  - branch is pushed and mapped to the target issue;
  - draft PR exists with scope, non-goals, validation, and hosted-check status;
  - branch/base relationship is recorded;
  - `git diff --check` passes;
  - full local release validation passes or the stop rule is triggered.
- This spec and `tasks.md` record phase state.
- Public `.agents/process.txt` and `.agents/plan.md` point to this active work
  package without duplicating its checklist.
- #67 remains deferred and unimplemented.

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
- **Continue rule**: Continue to the next phase when all of these conditions
  hold.
  - The current phase stays within accepted issue scope.
  - Local validation passes for the current branch.
  - The issue branch is pushed and the draft PR is created.
  - Public and private phase state are updated.
- **Stop rule**: Stop and hand off when any of these conditions occurs.
  - Continuing would require pushing `main`, merging a PR, closing an issue,
    marking a PR ready for review, tagging, releasing, or changing repository
    settings, secrets, rulesets, hooks, or runners.
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
- None blocking at creation time.
