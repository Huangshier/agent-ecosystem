# Release Validator Thin Entrypoint Plan

Status: planning boundary for issue #175.

This plan defines the second-stage modularization goal for
`scripts/validate-release.ps1`. The first stage (#96) completed its scoped
modularization sequence. This plan addresses continued growth after that first
stage: the file has grown beyond safe review size and needs a stricter
orchestration-only boundary.

## Baseline

Current state at the time this plan was written:

| Metric | Value |
| --- | --- |
| `scripts/validate-release.ps1` line count | 4,174 |
| `scripts/validate-release.ps1` file size | 209,868 bytes (~205 KB) |
| Existing `scripts/validation/` helpers | `release-test-helper.ps1`, `workflow-spec-lite-fixture-helper.ps1`, fixture directories |

## Target

Final goal:

- `scripts/validate-release.ps1` is **1,500 lines or less**.
- Stretch goal: **1,200 lines or less**, if achievable without unsafe churn.
- The file acts as a thin orchestration entrypoint, not a container for
  concrete validation logic.

## Relationship to #96

Issue #96 completed its first staged modularization pass. The
[v0.5.0 Validator Modularization Plan](v0.5.0-validator-modularization-plan.md)
documents that work. This plan does not re-open #96. It defines a stricter
second-stage target after continued growth made the first-stage boundary
insufficient.

## Entrypoint Responsibilities

`scripts/validate-release.ps1` should retain only:

- CLI parameters and defaults
- repository root / scratch root initialization
- live runtime safety guard calls
- dot-sourcing validation helper modules
- evidence / check collection initialization
- high-level check group invocation
- JSON and human-readable summary output
- final exit code behavior

All concrete validation logic should move to `scripts/validation/**`.

## Phased Extraction Plan

Each phase below should be a separate PR. Phases are ordered to reduce review
risk before moving behavior-heavy code.

### Phase 1 — Inventory and Guardrails

- Publish this plan document.
- Record baseline line count and file size.
- Define the growth rule.
- Add a minimal guard confirming this document exists and contains target
  tokens.
- No behavior change.

### Phase 2 — Move Static Repository / Documentation Checks

- Extract low-risk, read-only repository and documentation boundary checks
  into `scripts/validation/**`.
- Preserve check names, ordering, details, evidence shape, and pass/fail
  semantics.

### Phase 3 — Move Template / Language / Knowledge Checks

- Extract language template, routing, knowledge-hub, and public/private
  boundary checks into focused helper modules.
- Preserve existing coverage strength and output contracts.

### Phase 4 — Move Runtime Smoke / Bootstrap Checks

- Extract runtime smoke, bootstrap, and project-template validation checks
  into focused helper modules.
- Keep scratch-root safety and live-runtime protections intact.

### Phase 5 — Final Thin-Entrypoint Pass

- Reduce `scripts/validate-release.ps1` to the agreed thin orchestration
  shape.
- Confirm final line count is at or below the target.
- Confirm the growth guard prevents the entrypoint from growing back.

## Check Groups for `scripts/validation/**`

The following check groups are candidates for extraction:

| Group | Description |
| --- | --- |
| Repository and documentation boundary checks | required files, allowed/denied path patterns, documentation links |
| Required file / required token checks | specific text tokens that must appear in docs or scripts |
| Workflow-spec-lite fixtures and validator checks | positive and negative validator fixture construction and validation |
| Project-bootstrap runtime smoke checks | project memory creation, upgrade, and template smoke tests |
| Language template and routing checks | template file existence, language routing, bilingual section coverage |
| Knowledge-hub checks | knowledge-hub structure, catalog, and dotfile guard checks |
| Parser, encoding, JSON, and public-safety scans | PowerShell parser tests, encoding checks, JSON validity, public-safety boundaries |
| Installer profile matrix checks | install profile completeness, language file coverage |

## Growth Rule

> **New release-validation logic should normally live in
> `scripts/validation/**`, not in the main entrypoint script.**
>
> A check may remain in `scripts/validate-release.ps1` only if it is part of
> the orchestration layer (CLI setup, summary output, exit code) or if keeping
> it in the entrypoint is explicitly justified in the PR body. This rule applies
> after Phase 1 and should be enforced by review convention.

This rule is intentionally documented as a review convention rather than an
automated gate. Automated line-count or complexity guards can be added in
Phase 5 after the extraction is complete and the final entrypoint shape is
known.

## Behavior Preservation Contract

Unless a PR explicitly scopes and documents a behavior change:

- Release validation CLI parameters remain unchanged.
- `-TargetVersion`, `-ScratchRoot`, `-SkipLinkMode`, and `-Json` behavior
  remains unchanged.
- Check names, ordering, details, summary fields, JSON output shape, and
  pass/fail semantics remain unchanged.
- Existing validation coverage is not weakened.

Each PR must include:

- before/after line count and file size for `scripts/validate-release.ps1`;
- `git diff --check`;
- PowerShell parser check for modified `.ps1` files;
- full release validation passing.

## Rollback

Each phased PR should be independently revertable. Because phases extract
read-only or behavior-preserving checks, a revert should not need to repair
generated fixtures or migration artifacts.

## Non-Goals

- Do not rewrite the validator in one giant PR.
- Do not change release validator CLI parameters.
- Do not change check pass/fail semantics as part of mechanical movement.
- Do not weaken validation coverage.
- Do not couple this work to release preparation, tag creation, or GitHub
  Release publication.
- Do not include private paths, credentials, local scratch evidence, private
  overlays, or untracked `.agents/` runtime state in public docs or PRs.

## Validation

Phase 1 validation:

```powershell
git diff --check
pwsh -NoProfile -File scripts/validate-release.ps1 -TargetVersion v0.5.0 -SkipLinkMode
pwsh -NoProfile -File scripts/validate-release.ps1 -TargetVersion v0.5.0
```

Later phases add per-phase extraction evidence on top of the baseline.
