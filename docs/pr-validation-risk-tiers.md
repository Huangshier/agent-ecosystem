# PR validation risk tiers

Pull requests are classified before expensive validation starts. The classifier is deterministic, takes the highest tier when paths from multiple categories change, and escalates unknown or ambiguous input to Tier 3.

| Tier | Typical changes | Hosted validation |
|---|---|---|
| 0 | Metadata, PR template, ordinary documentation | Classification, quick diff/parse/public-safe checks, base guard, identity guard |
| 1 | Knowledge and mapped non-runtime repository helpers | Tier 0 checks plus quick repository checks and real affected-module contracts |
| 2 | Mapped bootstrap, templates, installer, bridge, and hooks surfaces | Cross-platform affected-module fixtures and runtime checks plus base and identity guards |
| 3 | Release, schema, profile, cross-module contracts, workflows, validation routing | Platform-neutral contracts once on Ubuntu; runtime/platform contracts on the PowerShell 7 OS matrix and Windows PowerShell 5.1 |

`scripts/validation/change-risk-rules.json` is the single path-routing source. Workflows consume `scripts/validate-change.ps1` output and do not maintain a second path table. `scripts/validate-release.ps1` remains the authoritative validator for Tier 3, `main`, release candidates, and publish finalization. Its `Full`, `PlatformNeutral`, and `RuntimePlatform` shards are defined by `scripts/validation/release-shard-contract.json`; the executable contract requires exact coverage, a disjoint split, and a complete union before a successful result can be emitted.

## Output contract

```powershell
./scripts/validate-change.ps1 -BaseRef origin/main -HeadRef HEAD
./scripts/validate-change.ps1 -ChangedPath README.md,scripts/install.ps1 -Json
```

Text and JSON report the detected tier, required checks, skipped checks, escalation reason, changed paths, affected modules, and required suites. Targeted JSON evidence records the executed suite names, counts, and per-module coverage. A skipped check means it was not required; it is never reported as passing.

Classifier JSON also owns a schema-1 `local_plan` for `iteration`, `pre_push`,
and `release`. Run it through the single local entrypoint:

```powershell
./scripts/invoke-local-validation.ps1 -Stage iteration -BaseRef origin/main -HeadRef HEAD -DryRun
./scripts/invoke-local-validation.ps1 -Stage pre-push -BaseRef origin/main -HeadRef HEAD
```

Iteration never runs full or heavy validation. Pre-push uses quick or targeted
affected-module checks for Tier 0-2; Tier 3 uses the complete validator under
PowerShell 7 and Windows PowerShell 5.1, plus the separate heavy targeted
regression only when the classifier's fail-closed self-protection decision
requires it. Release always keeps both local PowerShell full-validator hosts.
Dry-run output includes exact commands, hosts, suites, reasons, and explicit
skips. Executed plans add actual action and stage timestamps and durations;
timing is observational and never changes pass/fail.
Executed stages also checkpoint `local-validation-result.json` after each
completed action, preserving prior evidence if a later long-running action is
interrupted by the caller.

The targeted mappings reuse existing release helpers and fixtures: knowledge changes run catalog/index, entry metadata, public-safe metadata, experience search/regeneration, promotion, and helper consistency contracts; project bootstrap changes run the bootstrap safety fixture; bridge changes run the agent-skill bridge fixture; hooks run executable runtime fixtures; installer/runtime changes run installer contracts and runtime smoke; template and bundled snapshot changes run bootstrap safety plus language/template consistency. Runtime skills and local fixtures without a reliable mapping conservatively escalate to Tier 3.

## Leaf validation ownership and routing

A validation helper's risk follows its actual failure model, owner module, host dependency, and affected suite. A known leaf helper does not become validation control plane merely because its file name starts with `release-`. Known single-owner leaves are routed to the existing owner modules and suites in `change-risk-rules.json`; this keeps one public routing source and avoids a parallel owner manifest. Existing cross-module and release-candidate contracts remain explicitly Tier 3 without being treated as classifier self-protection surfaces.

The control plane remains Tier 3: classifier and routing code, workflows, local validation planning, the fixed gate, evidence writing, sharding contracts, and the top-level release validator. New or unmapped helpers, fixtures, and tests also remain Tier 3 by the classifier's fail-closed fallback. Refactoring the independent self-protection oracle belongs to the next architecture phase, not this routing change.

This ownership contract does not change the current Tier 3 local dual-host boundary, Hosted shard topology, main full validation, or fixed validation gate.

Tier 3 sharding changes only execution placement. Repository, documentation,
release, specification, evaluation, and governance contracts run once in the
platform-neutral shard. Installer, runtime, bootstrap, path, link, encoding,
PowerShell parsing, JSON parsing, language/template behavior, executable Claude
hooks runtime fixtures, and other host-sensitive contracts remain in the
runtime/platform shard. Windows
PowerShell 5.1 therefore retains parsing, parameter-binding, sorting, path, and
critical runtime compatibility coverage. `workflow_dispatch` and local release
checkpoints run `Full` on all required hosts.

The classifier job runs only deterministic path-classification and routing-contract tests. Executable knowledge, bootstrap, bridge, installer, and mixed-path targeted regressions run through `test-heavy-targeted-regression.ps1`; the hosted workflow retains the compatible `test-validate-change.ps1 -RunTargetedRegression` spelling until a separately reviewed workflow change. Documentation modules in mixed Tier 1/2 changes are covered by diff, parse, and public-safe base checks; every affected runtime module must still execute a mapped targeted suite. Only the two existing repository guard test surfaces map to `repository-guards`; future or unmapped `scripts/test-*` paths escalate to Tier 3.

## Expected hosted cost

The baseline before risk routing was four complete validator calls for every PR (PowerShell 7 on Windows, Ubuntu, and macOS, plus Windows PowerShell 5.1), in addition to base and identity guards.

| Representative PR | Before | After |
|---|---|---|
| Ordinary docs | 4 complete validators + 2 guards | classifier + 1 quick job + 2 guards; 0 complete validators |
| Knowledge | 4 complete validators + 2 guards | classifier + 1 quick job + 2 guards; 0 complete validators |
| Skill or installer | 4 complete validators + 2 guards | classifier + 3 targeted OS jobs + 2 guards; 0 complete validators |
| Release or validation routing | 4 complete validators + 2 guards | classifier + 1 platform-neutral shard + 4 runtime/platform shards + 2 guards |

The classifier adds one auditable job. For Tier 3, the platform-neutral shard runs once instead of four times while every host-sensitive contract retains its required matrix. The reduction comes from preventing low-risk PRs from invoking the full release validator and from removing proven cross-host duplication, not from relabeling skipped work.

## Conservative boundaries

- Empty diffs, unresolved refs, malformed Git diff records, unknown paths, unmapped runtime skills or fixtures, and classifier failures escalate to Tier 3.
- Every Tier 1 or Tier 2 affected module must execute at least one mapped suite. Zero module checks fail validation; classification or parsing alone cannot produce a targeted PASS.
- Renames classify both the old and new path; deletions classify the deleted path.
- `main` pushes use the same Tier 3 shard topology and bind evidence to the pushed SHA. Manual workflow dispatches keep complete validation on every required host.
- Pull-request jobs explicitly check out the PR head SHA; push jobs use the pushed SHA. Evidence is never reused across SHAs.
- Base and identity guards remain independent required workflow surfaces.
