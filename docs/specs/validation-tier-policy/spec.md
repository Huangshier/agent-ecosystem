# Work Spec

- **Title**: Validation Tier Policy
- **Slug**: validation-tier-policy
- **Status**: Active
- **Owner**: Maintainer + agent
- **Updated**: 2026-05-12

## 1. Summary

- Document how maintainers and agents choose local validation depth for
  agent-assisted maintenance.
- Keep the policy advisory for low-risk changes while making high-risk
  surfaces explicit.

## 2. Current Context

- GitHub issue #27 asks for validation tiers after governance and GitHub App
  rollout exposed repeated local-validation judgment calls.
- The `protect-main` ruleset already requires pull requests, conversation
  resolution, and hosted release validation checks before merge.
- The PR template already asks for validation evidence.
- `scripts/validate-release.ps1` is the full local release gate.
- Existing docs describe the release gate and public reader review, but do not
  explain validation depth by change type.

## 3. Goals

- Decide where validation-tier policy belongs.
- Document tiers for issue metadata, ordinary docs, governance docs, tracked
  agent memory, scripts, installer behavior, CI, and release metadata.
- Keep required hosted checks and release validation behavior unchanged.
- Update PR evidence collection so reviewers can see the selected tier.
- Refresh public `.agents` memory to point at #27 as the active maintenance
  item.

## 4. Non-Goals

- Do not change repository rulesets, required hosted checks, or GitHub App
  permissions.
- Do not add changed-file automation.
- Do not weaken the full release validation gate.
- Do not resolve #23 roadmap/domain-pack governance.
- Do not implement #29-#33 engineering-memory changes.

## 5. Constraints

- Public docs are English-first.
- Public `.agents` memory must not include private paths, local mappings, or
  sensitive auth material.
- The policy must not imply that an agent may merge or release.
- Scope control: keep this to documentation, PR template evidence, public spec,
  and tracked public memory.

## 6. Assumptions

- `docs/release-process.md` is the canonical home because the policy governs
  validation depth rather than agent authority.
- `docs/agent-governance.md` should reference the release-process policy
  instead of duplicating the tier table.
- Full local release validation is appropriate for this PR because it touches
  governance/release docs, tracked public memory, and the PR template.

## 7. Risks

- A rigid policy could slow small documentation changes.
- A vague policy could leave agents under-validating governance, release, CI,
  installer, or tracked memory changes.
- Mixed-scope PRs may need the highest tier that applies.

## 8. Proposed Approach

- Add a validation-tier section to `docs/release-process.md`.
- Add a short governance reference in `docs/agent-governance.md`.
- Add a validation-tier field to `.github/pull_request_template.md`.
- Update `.agents/process.txt`, `.agents/plan.md`, and `.agents/notes.md`.

## 9. Acceptance / Evidence

- Current hard requirements are documented:
  - hosted required checks;
  - PR validation evidence;
  - full local release validator availability.
- Validation tiers cover issue metadata, ordinary docs, governance docs,
  tracked agent memory, scripts, installer behavior, CI, and release metadata.
- Documentation stays advisory for low-risk docs and explicit for high-risk
  surfaces.
- `git diff --check` passes.
- Local release validation passes.
- Hosted release validation passes on the PR before merge.

## 10. Loop Contract

- Not required for this documentation policy task.

## 11. Execution Contract

- **Autonomy level**: bounded-autonomous
- **Phase list**:
  - P01: Draft spec/tasks and point public memory at #27.
  - P02: Document validation tiers and PR evidence fields.
  - P03: Validate locally, commit, push, and open PR.
  - P04: Wait for hosted checks and maintainer review.
- **Continue rule**: Continue while the change remains documentation/template
  and tracked public memory only, validation is available, and no repository
  settings or secrets are touched.
- **Stop rule**: Stop for scope drift, requested ruleset changes, GitHub App
  permission changes, skipped acceptance checks, or unresolved ambiguity about
  whether the policy should become enforcement.
- **State record**: `docs/specs/validation-tier-policy/tasks.md` and
  `.agents/plan.md`.

## 12. Open Questions

- Whether a later issue should add changed-file automation after maintainers
  observe the advisory policy in use.
