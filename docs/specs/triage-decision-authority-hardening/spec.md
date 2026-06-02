# Work Spec

- **Title**: Triage Decision Authority Hardening
- **Slug**: triage-decision-authority-hardening
- **Status**: Done
- **Owner**: Codex + maintainer
- **Updated**: 2026-06-02

## 1. Summary
- Harden the `agent-candidate` human triage decision path so new issues use a single normalized decision field, legacy checklist issues remain safe, and triage label synchronization only mutates labels for trusted actors or maintainer-authorized changes.

## 2. Current Context
- Issue #121 tracks this work and is accepted.
- `.github/ISSUE_TEMPLATE/agent-candidate.md` currently records `Human Triage Decision` as four Markdown task-list checkboxes.
- `.github/workflows/issue-triage-label-sync.yml` currently mirrors exactly one checked decision into `triage:*` labels for issues labeled `source:agent`.
- `docs/agent-governance.md` states that issue body decisions are the source of truth and the workflow does not make triage decisions.
- `scripts/validate-release.ps1` includes structural validation for the current checklist-based workflow and template guidance.

## 3. Goals
- Replace the new issue template decision UI with a single normalized `Decision:` field.
- Preserve safe compatibility for existing checklist-based issues.
- Add trusted actor / maintainer authority checks before mutating `triage:*` labels.
- Reduce avoidable label-event workflow noise while keeping label metadata synchronized with explicit decisions.
- Update governance documentation and release validation coverage for the new parsing and authority model.
- Publish a scoped PR for #121 and stop when the PR is ready for maintainer review.

## 4. Non-Goals
- Do not infer triage decisions from free text.
- Do not let agent-authored text alone decide acceptance without maintainer authority.
- Do not change repository settings, branch protection, rulesets, access-control configuration, GitHub App installation permissions, tags, releases, or release publishing behavior.
- Do not close issues, merge pull requests, tag releases, or publish GitHub Releases.
- Do not refactor unrelated release validator or workflow code.

## 5. Constraints
- Public-facing artifacts must be English-first.
- Keep root `.agents/**` local and untracked.
- The workflow must continue to use least practical permissions for metadata synchronization.
- Bot identity should be used for issue/PR publication where possible; if the bot cannot push workflow changes, the maintainer's current authenticated identity may be used as authorized for this task.
- The PR is not merge-to-publish and must stop before merge.

## 6. Assumptions
- Maintainers or trusted automation are the only actors allowed to cause `triage:*` label mutations from issue-body decisions.
- Repository collaborator permission or role information is sufficient to identify maintainer-authorized human actors.
- The configured `agent-ecosystem-bot[bot]` login is trusted automation for candidate issue and PR preparation, but the workflow should still keep maintainer authority explicit.
- Existing checklist-based issues should not require immediate manual migration.

## 7. Risks
- GitHub Actions expression changes could accidentally skip intended issue events or run on too many label events.
- Inline workflow JavaScript can drift from validation expectations if release validation remains string-only.
- Actor permission API failures should fail safely without mutating labels for untrusted actors.
- Tightening source or actor checks could surprise maintainers if undocumented.

## 8. Proposed Approach
- Change the issue template `Human Triage Decision` section to `Decision: needs-human` with allowed values.
- Update the workflow parser:
  - prefer a single `Decision:` field when present;
  - reject multiple `Decision:` fields or invalid values;
  - support legacy checklist parsing only when no `Decision:` field exists;
  - reject mixed single-field and checked legacy checklist decisions.
- Add an actor authority guard before label mutation:
  - trust the configured `agent-ecosystem-bot[bot]`;
  - trust users with repository `admin`, `maintain`, `write`, or `triage` role/permission;
  - warn and no-op for untrusted actors.
- Add issue-number concurrency and narrow label-event execution to relevant labels.
- Update governance docs and release validation structural checks.

## 9. Acceptance / Evidence
- `git diff --check` passed.
- Workflow YAML parsed successfully with PyYAML.
- A local Node harness extracted the inline `github-script` body and verified:
  - trusted maintainer `Decision: accepted` adds `triage:accepted`;
  - trusted bot legacy checklist parsing adds the mapped label;
  - untrusted actor changes no-op before parsing failures can mutate labels;
  - trusted actor invalid `Decision:` fails without mutation.
- `pwsh -NoProfile -File scripts/validate-release.ps1 -ScratchRoot .runtime/validation/issue121-after-pr-evidence-rerun` passed with `PASS=54 FAIL=0 WARN=0 DEFERRED=0`.
- Workflow file contains single-field parsing, legacy checklist compatibility, actor authority guard, and concurrency.
- Issue template exposes a single normalized decision field.
- Governance docs describe the authority boundary.
- PR #122 is open and ready for maintainer review:
  <https://github.com/Huangshier/agent-ecosystem/pull/122>.
- Issue #121 and PR #122 were created by `agent-ecosystem-bot[bot]`.
- The branch was pushed with the maintainer-authenticated account after GitHub
  rejected the bot push because the App lacks workflow-file write permission.

## 10. Loop Contract
- Not applicable.

## 11. Execution Contract
- **Autonomy level**: bounded-autonomous
- **Phase list**:
  - P01: Create accepted issue #121 and durable public work package.
  - P02: Implement template, workflow, governance docs, and release validation updates.
  - P03: Run local validation and fix in-scope failures.
  - P04: Commit, push, open PR, mark ready for review, and stop before merge. Completed.
- **Continue rule**: Continue while changes remain within #121 scope, validation failures are explainable and fixable, and no repository settings, release, tag, or merge action is required.
- **Stop rule**: Stop on scope drift, unrelated refactor pressure, skipped acceptance checks that cannot be honestly reported, missing push/PR permission after the authorized fallback, repository settings/access-control/ruleset/tag/release/merge requirements, or unresolved ambiguity about maintainer authority.
- **State record**: This spec, `tasks.md`, and the scoped PR description.

## 12. Open Questions
- None currently blocking implementation.
