# Work Spec

- **Title**: Issue triage label sync
- **Slug**: issue-triage-label-sync
- **Status**: Done
- **Owner**: Maintainer + agent
- **Updated**: 2026-05-22

## 1. Summary

- Add a small GitHub Actions workflow that mirrors explicit human triage checklist decisions into issue labels for agent candidate issues.
- The workflow should prevent issue metadata drift like issue #30, where the body recorded Accepted but labels still showed needs-human.

## 2. Current Context

- Public issue #42 tracks this work.
- `.github/ISSUE_TEMPLATE/agent-candidate.md` includes a `## Human Triage Decision` checklist.
- `docs/agent-governance.md` defines triage labels but does not currently document automatic synchronization.
- `.github/workflows/release-validation.yml` is the only current workflow.
- `scripts/validate-release.ps1` is the public validation gate.

## 3. Goals

- Synchronize labels for agent candidate issues when exactly one human triage decision checkbox is checked.
- Map Accepted / Rejected / Deferred / Needs human investigation to the corresponding `triage:*` label.
- Remove stale triage labels and stale issue-level `review:needs-human` when a human triage decision is explicit.
- Fail without mutating labels when multiple decisions are checked.
- Document the workflow as metadata synchronization, not decision-making.
- Add release validation coverage for the workflow structure.

## 4. Non-Goals

- Do not infer decisions from free-form text outside the checklist.
- Do not create specs, branches, PRs, or implementation work from issues.
- Do not close issues, merge PRs, publish releases, or modify repository settings.
- Do not implement #30 conservative language migration.

## 5. Constraints

- Public-facing artifacts are English-first.
- The workflow must keep maintainer authority explicit: human edits the checklist, automation mirrors labels.
- The workflow must only operate on agent candidate issues, scoped by `source:agent`.
- Keep validation deterministic and local where possible.

## 6. Assumptions

- Agent candidate issues keep the `## Human Triage Decision` heading from the issue template.
- The existing `triage:*`, `source:agent`, and `review:needs-human` labels remain available.
- Failing an Actions run on ambiguous multiple checkbox selections is acceptable feedback.

## 7. Risks

- Label mutation could surprise maintainers if the workflow applies to non-agent issues.
- Checkbox parsing can drift if the template changes without validation coverage.
- Removing `review:needs-human` is correct for issue triage metadata, but PR review needs should be represented on PRs or separate review state.

## 8. Proposed Approach

- Add `.github/workflows/issue-triage-label-sync.yml`.
- Trigger on issue open/edit/label changes.
- Skip issues without `source:agent`.
- Parse only the `Human Triage Decision` section.
- If no decision is checked, no-op.
- If multiple decisions are checked, fail and no-op.
- If exactly one decision is checked, add the mapped triage label and remove conflicting triage labels plus stale `review:needs-human`.
- Update governance docs, issue template hints, public memory, and release validation.

## 9. Acceptance / Evidence

- Issue #42 exists and is accepted.
- Workflow file exists with `issues: write` and `contents: read` permissions.
- Governance docs explain that the workflow mirrors explicit human decisions only.
- Release validator checks required workflow strings and governance docs.
- `git diff --check` passes.
- `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-release.ps1 -ScratchRoot <scratch>` passes.

## 10. Loop Contract

- Not used.

## 11. Execution Contract

- **Autonomy level**: bounded-autonomous
- **Phase list**:
  - P01: Create accepted issue #42 and work package.
  - P02: Implement workflow, docs, validation, and public memory updates.
  - P03: Run local validation, commit, push branch, and open draft PR.
- **Continue rule**: Continue while changes stay within issue #42 scope and validation is available.
- **Stop rule**: Stop for repository settings changes, secrets, ruleset edits, direct `main` writes, ambiguous maintainer intent, skipped acceptance checks, or scope drift into #30 implementation.
- **State record**: `docs/specs/issue-triage-label-sync/tasks.md` and `.agents/plan.md`.

## 12. Open Questions

- None blocking.
