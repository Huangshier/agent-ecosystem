# PR validation risk tiers

Pull requests are classified before expensive validation starts. The classifier is deterministic, takes the highest tier when paths from multiple categories change, and escalates unknown or ambiguous input to Tier 3.

| Tier | Typical changes | Hosted validation |
|---|---|---|
| 0 | Metadata, PR template, ordinary documentation | Classification, quick diff/parse/public-safe checks, base guard, identity guard |
| 1 | Knowledge and mapped non-runtime repository helpers | Tier 0 checks plus quick repository checks and real affected-module contracts |
| 2 | Mapped bootstrap, templates, installer, bridge, and hooks surfaces | Cross-platform affected-module fixtures and runtime checks plus base and identity guards |
| 3 | Release, schema, profile, cross-module contracts, workflows, validation routing | Full PowerShell 7 OS matrix and Windows PowerShell 5.1 release validation |

`scripts/validation/change-risk-rules.json` is the single path-routing source. Workflows consume `scripts/validate-change.ps1` output and do not maintain a second path table. `scripts/validate-release.ps1` remains the authoritative complete validator for Tier 3, `main`, release candidates, and publish finalization.

## Output contract

```powershell
./scripts/validate-change.ps1 -BaseRef origin/main -HeadRef HEAD
./scripts/validate-change.ps1 -ChangedPath README.md,scripts/install.ps1 -Json
```

Text and JSON report the detected tier, required checks, skipped checks, escalation reason, changed paths, affected modules, and required suites. Targeted JSON evidence records the executed suite names, counts, and per-module coverage. A skipped check means it was not required; it is never reported as passing.

The targeted mappings reuse existing release helpers and fixtures: knowledge changes run catalog/index, entry metadata, public-safe metadata, experience search/regeneration, promotion, and helper consistency contracts; project bootstrap changes run the bootstrap safety fixture; bridge changes run the agent-skill bridge fixture; hooks run executable runtime fixtures; installer/runtime changes run installer contracts and runtime smoke; template and bundled snapshot changes run bootstrap safety plus language/template consistency. Runtime skills and local fixtures without a reliable mapping conservatively escalate to Tier 3.

The classifier job runs only deterministic path-classification and routing-contract tests. Executable knowledge, bootstrap, bridge, installer, and mixed-path targeted regressions run only with the explicit `-RunTargetedRegression` switch from Tier 3/full validation jobs, including `main` and manual dispatch. Documentation modules in mixed Tier 1/2 changes are covered by diff, parse, and public-safe base checks; every affected runtime module must still execute a mapped targeted suite. Only the two existing repository guard test surfaces map to `repository-guards`; future or unmapped `scripts/test-*` paths escalate to Tier 3.

## Expected hosted cost

The baseline before risk routing was four complete validator calls for every PR (PowerShell 7 on Windows, Ubuntu, and macOS, plus Windows PowerShell 5.1), in addition to base and identity guards.

| Representative PR | Before | After |
|---|---|---|
| Ordinary docs | 4 complete validators + 2 guards | classifier + 1 quick job + 2 guards; 0 complete validators |
| Knowledge | 4 complete validators + 2 guards | classifier + 1 quick job + 2 guards; 0 complete validators |
| Skill or installer | 4 complete validators + 2 guards | classifier + 3 targeted OS jobs + 2 guards; 0 complete validators |
| Release or validation routing | 4 complete validators + 2 guards | classifier + 4 complete validators + 2 guards |

The classifier adds one auditable job. The reduction comes from preventing low-risk PRs from invoking the full release validator, not from relabeling skipped work.

## Conservative boundaries

- Empty diffs, unresolved refs, malformed Git diff records, unknown paths, unmapped runtime skills or fixtures, and classifier failures escalate to Tier 3.
- Every Tier 1 or Tier 2 affected module must execute at least one mapped suite. Zero module checks fail validation; classification or parsing alone cannot produce a targeted PASS.
- Renames classify both the old and new path; deletions classify the deleted path.
- `main` pushes and manual workflow dispatches always use the full matrix.
- Base and identity guards remain independent required workflow surfaces.
