# Work Spec

- **Title**: Issue triage decision comment command
- **Slug**: issue-triage-decision-command
- **Status**: Done
- **Owner**: Codex
- **Updated**: 2026-06-03

## 1. Summary
- Add a scoped maintainer comment command path for agent candidate issue triage decisions.
- Authorized maintainers can write `/decision <value>` on an agent candidate issue.
- Automation updates the issue body `Decision:` field and then converges `triage:*` labels from that updated body decision.

## 2. Current Context
- Public issue #123 is accepted for this workflow usability improvement.
- Existing `.github/workflows/issue-triage-label-sync.yml` mirrors `Decision:` body edits into labels for `source:agent` issues.
- New agent candidate issues already use a normalized `Decision:` field.
- GitHub Actions does not normally trigger another workflow from events caused by `GITHUB_TOKEN`, except for documented dispatch exceptions. A comment-command workflow that edits the issue body with `GITHUB_TOKEN` must therefore converge labels itself instead of relying on a follow-up `issues: edited` run.

## 3. Goals
- Add an exact-command `issue_comment` workflow for open `source:agent` issues.
- Support `/decision accepted`, `/decision rejected`, `/decision deferred`, and `/decision needs-human`.
- Optionally support `/accept` as a high-frequency exact-command alias for `accepted`.
- Restrict body mutation to trusted automation or users with repository `admin`, `maintain`, or `write` authority.
- Ignore pull request comments, closed issues, non-`source:agent` issues, invalid commands, and unauthorized actors without mutating issue body or labels.
- Keep `Decision:` as the source of truth and keep the existing manual body-edit workflow working.
- Add local and release-validation coverage for parsing, authorization, body update, and label convergence.

## 4. Non-Goals
- Do not implement accepted issues automatically.
- Do not infer decisions from natural-language comments.
- Do not allow untrusted commenters to mutate issue bodies or labels.
- Do not create branches, PRs, sub-issues, tags, release candidates, or publish-finalization artifacts from comment commands.
- Do not change repository settings, rulesets, secrets, branch protection, or release publishing behavior.

## 5. Constraints
- Public changes must not include private overlay paths, local `.agents` memory, access material, or private review evidence.
- Workflow changes require maintainer-authorized branch push because the bot currently cannot push workflow files.
- The comment-command workflow should use repository `GITHUB_TOKEN` with minimal permissions: `contents: read` and `issues: write`.
- The workflow must not weaken the existing manual `Decision:` label sync path.

## 6. Assumptions
- `actions/github-script@v8` can load a repository helper after checkout in the same way other repository-local scripts are available to Node.
- Exact command parsing is preferable for v1 because it avoids natural-language inference.

## 7. Risks
- Duplicating label convergence logic across workflows can drift from the existing label sync workflow.
- Workflow body edits performed with `GITHUB_TOKEN` will not trigger the existing `issues: edited` workflow, so missing same-workflow label convergence would leave temporary label drift.
- If the command parser accepts too much syntax, ordinary comments may be misinterpreted as decisions.

## 8. Proposed Approach
- Add `.github/scripts/issue-triage-decision-command.js` with pure helpers and a GitHub Actions handler.
- Add `.github/workflows/issue-triage-decision-command.yml` for `issue_comment.created`.
- Add `scripts/test-issue-triage-decision-command.ps1` to run local Node-based unit checks against the reusable helper.
- Update `scripts/validate-release.ps1` to require the new workflow, helper, governance documentation, and local harness.
- Update `docs/agent-governance.md` with the comment command UX and authority boundary.

## 9. Acceptance / Evidence
- `scripts/test-issue-triage-decision-command.ps1 -Json` passed with 9 checks.
- `git diff --check` passed.
- `scripts/validate-release.ps1 -ScratchRoot <scratch>` passed with `PASS=54 FAIL=0 WARN=0 DEFERRED=0`.
- Draft PR links issue #123 and includes validation evidence.

## 10. Loop Contract
- Not applicable.

## 11. Execution Contract
- **Autonomy level**: bounded-autonomous
- **Phase list**:
  - P01: Create accepted issue and implementation branch. Completed.
  - P02: Add workflow, helper, docs, spec, and validator coverage. Completed.
  - P03: Run local validation, commit, push with maintainer identity, and open a draft PR. Completed through local validation; draft PR is the handoff artifact.
- **Continue rule**: Continue while work remains inside issue #123 scope, local validation is available, and no repository settings, secrets, release, tag, merge, or branch-protection action is needed.
- **Stop rule**: Stop on workflow scope drift, untrusted write identity, validation failure that cannot be diagnosed, missing maintainer authorization for workflow branch push, skipped acceptance checks, or any request to merge, publish, tag, or change repository controls.
- **State record**: This spec, `tasks.md`, issue #123, and the draft PR.

## 12. Open Questions
- None blocking for the scoped draft PR.
