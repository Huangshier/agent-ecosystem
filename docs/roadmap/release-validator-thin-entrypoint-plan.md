# Release Validator Thin Entrypoint Plan

Status: complete. Phases 1-4 delivered the extraction; Phase 5 records the
final closeout for issue #175.

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

Status: completed by PR #176.

- Publish this plan document.
- Record baseline line count and file size.
- Define the growth rule.
- Add a minimal guard confirming this document exists and contains target
  tokens.
- No behavior change.

### Phase 2 — Move Static Repository / Documentation Checks

Status: completed by PR #177.

- Extract low-risk, read-only repository and documentation boundary checks
  into `scripts/validation/**`.
- Preserve check names, ordering, details, evidence shape, and pass/fail
  semantics.

### Phase 3 — Move Template / Language / Knowledge Checks

Status: completed by PR #178.

- Extract language template, routing, knowledge-hub, and public/private
  boundary checks into focused helper modules.
- Preserve existing coverage strength and output contracts.

### Phase 4 — Move Runtime Smoke / Bootstrap Checks

Status: completed by PR #179.

- Extract runtime smoke, bootstrap, and project-template validation checks
  into focused helper modules.
- Keep scratch-root safety and live-runtime protections intact.

### Phase 5 — Final Thin-Entrypoint Pass

Status: final closeout.

- Reduce `scripts/validate-release.ps1` to the agreed thin orchestration
  shape.
- Confirm final line count is at or below the target.
- Confirm the growth guard prevents the entrypoint from growing back.

## Final Closeout

Phases 1-4 reduced `scripts/validate-release.ps1` from the original 4,174
lines / 209,868 bytes to **566 lines / 24,841 bytes**. The result is 934 lines
below the 1,500-line target and 634 lines below the 1,200-line stretch goal.

The final entrypoint owns the intended orchestration surfaces:

- CLI parameters, defaults, repository discovery, and scratch-root setup;
- live-runtime and scratch-root safety initialization;
- check/evidence collection and release-version validation;
- dot-sourcing 10 focused helpers under `scripts/validation/**`;
- high-level check-group invocation in the compatibility-preserving order;
- JSON and human-readable result emission and the final exit code.

Two local wrappers are delegation-only. The remaining bounded
`Invoke-ReleaseValidationSpecAndDocumentationChecks` wrapper preserves the
established ordering of fixture-backed specification, structural-diagnostic,
adoption, release-documentation, and PR-guard checks. It is intentionally left
in place at closeout rather than creating another large mechanical-movement PR
after the line-count and architecture goals have been exceeded.

The extracted implementation now lives in these focused validation helpers:

- `release-repository-checks.ps1`
- `release-documentation-checks.ps1`
- `release-parser-safety-checks.ps1`
- `release-knowledge-hub-checks.ps1`
- `release-template-language-checks.ps1`
- `release-runtime-smoke-checks.ps1`
- `release-bootstrap-checks.ps1`
- `release-project-template-checks.ps1`
- `release-test-helper.ps1`
- `workflow-spec-lite-fixture-helper.ps1`

### Final Growth Guard Decision

The documented Growth Rule remains the final guard. An additional
self-line-count check inside `validate-release.ps1` would add validator logic
to the entrypoint and change the established 62-check output contract solely
to measure the entrypoint itself. The current rule is sufficient because:

- the entrypoint is already less than half of the 1,200-line stretch goal;
- its allowed responsibilities and helper destination are explicit;
- every future validator PR must report entrypoint line count and file size;
- the existing `thin entrypoint roadmap` check keeps this target and
  `scripts/validation/**` growth direction release-gated.

### Acceptance Criteria Mapping

| Issue #175 criterion | Final evidence |
| --- | --- |
| Entrypoint is 1,500 lines or less | 566 lines / 24,841 bytes on final Phase 4 main; also below the 1,200-line stretch goal. |
| Entrypoint is primarily orchestration | CLI/safety/state/group invocation/output remain in the entrypoint; concrete repository, documentation, parser, knowledge, language, runtime, bootstrap, and template checks are routed through focused helpers. |
| Output contracts are preserved | Phase 4 retained 62 checks with unchanged names, relative ordering, details format, summary, JSON evidence shape, and pass/fail semantics. |
| Coverage is not weakened | Local pwsh and Windows PowerShell 5.1 copy-only/full runs passed 62/62; PR #179 hosted validation passed on Windows, Ubuntu, and macOS plus Windows PowerShell 5.1. |
| Helpers are public-safe and under `scripts/validation/**` | All extracted helpers use the public validation tree; installed-runtime scripts do not depend on repository-only helper paths. |
| PRs include metrics and validation | PRs #176-#179 recorded phased metrics and validation; this closeout records the final result. |
| Final PR explains closure | This section maps every acceptance criterion and confirms no remaining Phase 5 implementation is required. |

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
