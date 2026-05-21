# Work Spec

- **Title**: Domain Pack Governance Lifecycle
- **Slug**: domain-pack-governance-lifecycle
- **Status**: Done
- **Owner**: Codex
- **Updated**: 2026-05-21

## 1. Summary
- Implement issue #56 with a governance-only documentation pass that defines
  the public domain-pack lifecycle, manifest guidance, promotion criteria,
  public-safety checklist, release-validation expectations, and profile
  boundary.

## 2. Current Context
- Latest public main commit at implementation start was
  `6304b5bb415ea4e838104f73d464777597c2a128`, which includes #78 and #80.
- Issue #56 is accepted and explicitly requires no public domain-pack
  expansion.
- Existing docs describe domain packs in `docs/architecture.md`,
  `docs/roadmap/evolution-plan.md`, and `knowledge-hub/knowledge/domain-packs/`.
- `full` and `dev` profiles currently install the same public content as
  `recommended`.

## 3. Goals
- Add one authoritative domain-pack governance entrypoint.
- Define lifecycle states from draft through deprecated.
- Define minimum manifest fields.
- Define promotion criteria for moving from Markdown knowledge toward a public
  skill or future installable pack.
- Define a public-safety checklist that blocks private assumptions from public
  promotion.
- Define profile boundary text that keeps `full` and `dev` behavior unchanged.
- Link the governance entrypoint from existing public navigation.

## 4. Non-Goals
- Do not add a new real public domain pack.
- Do not promote `embedded-core` to a scriptable skill.
- Do not change `full`, `dev`, `recommended`, or `minimal` installer behavior.
- Do not change release tags, releases, repository settings, rulesets,
  sensitive access configuration, branch protection, or `main` directly.
- Do not implement #23, #67, #79, or any profile expansion work.

## 5. Constraints
- Public documentation remains public-safe and must not include private overlay
  details, local machine paths, access material, private repository names,
  generated runtime manifests, or sensitive audit material.
- This PR is documentation and governance only.
- Validation tier is Tier 2 because governance docs and public/private boundary
  wording change.

## 6. Assumptions
- The authoritative governance doc can live at `docs/domain-pack-governance.md`.
- Existing draft Markdown domain-pack entries do not need metadata churn solely
  for this issue.
- The full release validator is the expected local regression check.

## 7. Risks
- Duplicating roadmap criteria can create future drift unless the roadmap points
  to the authoritative governance document.
- Ambiguous wording around `installable` could be mistaken as enabling current
  profile expansion.

## 8. Proposed Approach
- Add `docs/domain-pack-governance.md` with lifecycle, manifest fields,
  promotion criteria, public-safety checklist, validation expectations, and
  profile boundary.
- Update architecture and knowledge-hub navigation to point to the governance
  doc.
- Update README navigation so profile readers can find the boundary.
- Keep all installer scripts, profile expectations, and domain-pack content
  behavior unchanged.

## 9. Acceptance / Evidence
- The governance doc covers lifecycle, manifest fields, promotion criteria,
  public-safety checklist, release-validation expectations, and profile
  boundary.
- Existing docs link to the authoritative governance entrypoint.
- No new domain pack is added and no installer/profile behavior changes.
- Local validation:
  - `git diff --check` passed.
  - `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\validate-release.ps1 -ScratchRoot "$env:TEMP\agent-ecosystem-issue-56-validation-r2"` passed with `PASS=49 FAIL=0 WARN=0 DEFERRED=0`.

## 10. Loop Contract
- Not applicable.

## 11. Execution Contract
- **Autonomy level**: bounded-autonomous
- **Phase list**:
  - P01: Create the spec and governance document.
  - P02: Update navigation and adjacent documentation references.
  - P03: Run local validation and prepare the scoped PR handoff.
- **Continue rule**: Completed while changes stayed inside #56 governance-only
  scope and validation had no unresolved failure.
- **Stop rule**: Completed without scope drift, profile behavior changes, new
  public domain-pack content, private data exposure, skipped acceptance checks,
  repository settings or protected-branch actions, or unresolved ambiguity.
- **State record**: This spec and checkout-local `.agents` memory when present.

## 12. Open Questions
- None.
