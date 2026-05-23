# Work Spec

- **Title**: Public Promotion Boundaries
- **Slug**: public-promotion-boundaries
- **Status**: Done
- **Owner**: Codex + maintainer
- **Updated**: 2026-05-24

## 1. Summary
- Capture the reusable public follow-ups from a local Codex session workflow
  audit without publishing private session content.
- Add public-safe guidance for cross-repository promotion, permission
  preflights, and long-session phase splitting.

## 2. Current Context
- Issue #92 records the accepted public follow-up scope.
- PR #91 already strengthened verifier-driven completion, closeout evidence,
  and recurring automation command-card routing.
- Existing public standards cover public knowledge boundaries and bilingual
  public/private routing, but there is no dedicated promotion checklist for
  moving reusable lessons from private or project-local evidence into public
  artifacts.
- Existing patterns cover context gate to spec to validation, but long sessions
  need a more explicit spec / implementation / closeout split.

## 3. Goals
- Add a reusable public promotion checklist that includes public/private
  routing and write-boundary preflight expectations.
- Add a reusable long-session phase split pattern for large or restart-prone
  work.
- Keep live `knowledge-hub` entries and bootstrap asset mirrors aligned.
- Update governance guidance so agent-assisted PRs can refer to the promotion
  and permission boundary without copying private details.

## 4. Non-Goals
- Do not publish private paths, local session logs, sensitive access material,
  private repository mappings, private automation cadence, or sensitive audit
  details.
- Do not add scheduler jobs, GitHub Actions workflows, repository settings,
  rulesets, branch protection changes, tags, or release publication steps.
- Do not change installer, bootstrap, validation, CI, or release behavior.
- Do not reopen or replace the already-merged PR #91 scope.

## 5. Constraints
- Public docs remain English-first unless a localized public doc is explicitly
  in scope.
- Bootstrap asset mirrors must carry the same public knowledge entries as the
  live hub template snapshot.
- This is documentation and knowledge-hub work; validation tier is Tier 2.
- Scope control: avoid unrelated refactors, cleanup, or behavior changes.

## 6. Assumptions
- The reusable parts of the audit can be expressed as generic public guidance.
- A single issue and PR are sufficient for this documentation-only follow-up.
- Release validation is expected to cover catalog and bundled knowledge asset
  consistency.

## 7. Risks
- Wording could accidentally imply private-control-plane requirements for all
  public users.
- A checklist could become too heavy and slow down ordinary small fixes.
- Live hub and bundled asset mirrors could drift.

## 8. Proposed Approach
- Create a `Public Promotion Checklist` standard in the public knowledge hub
  and bundled asset mirror.
- Create a `Long Session Phase Split` pattern in the public knowledge hub and
  bundled asset mirror.
- Update knowledge catalogs and index READMEs for discoverability.
- Add a concise cross-repository promotion section to `docs/agent-governance.md`.

## 9. Acceptance / Evidence
- Issue #92 exists and links the accepted public follow-up scope.
- The new standard and pattern exist in both live and bundled asset locations.
- Catalog and index files reference the new entries.
- Governance docs describe public/private promotion preflight without private
  local details.
- `git diff --check` passed.
- `validate_spec.ps1 -RequireExecutionContract -FailOnError` passed.
- `validate-release.ps1 -ScratchRoot .runtime\validation\public-promotion-boundaries-final-20260524003500`
  passed with `PASS=52 FAIL=0 WARN=0 DEFERRED=0`.

## 10. Loop Contract
- Not applicable.

## 11. Execution Contract
- **Autonomy level**: bounded-autonomous
- **Phase list**:
  - P01: Create issue-backed public work package.
  - P02: Add live public knowledge entries and governance guidance.
  - P03: Mirror bundled bootstrap asset knowledge entries.
  - P04: Validate and close out the public review handoff.
- **Continue rule**: Completed; changes stayed documentation-only,
  public-safe, issue-linked, mirror-aligned, and validated.
- **Stop rule**: Completed without private data exposure, skipped acceptance
  checks, destructive cleanup, settings/ruleset/release changes, unresolved
  public/private boundary ambiguity, or unrelated refactor pressure.
- **State record**: `docs/specs/public-promotion-boundaries/tasks.md`.

## 12. Open Questions
- None for this bounded documentation follow-up.
