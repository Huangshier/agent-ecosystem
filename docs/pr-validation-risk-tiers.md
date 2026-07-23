# PR validation risk tiers

Pull requests are classified before expensive validation starts. The classifier is deterministic, takes the highest tier when paths from multiple categories change, and escalates unknown or ambiguous input to Tier 3.

| Tier | Typical changes | Hosted validation |
|---|---|---|
| 0 | Metadata, PR template, ordinary documentation | Classification, quick diff/parse/public-safe checks, base guard, identity guard |
| 1 | Knowledge and mapped non-runtime repository helpers | Tier 0 checks plus quick repository checks and real affected-module contracts |
| 2 | Mapped bootstrap, templates, installer, bridge, and hooks surfaces | Cross-platform affected-module fixtures and runtime checks plus base and identity guards |
| 3 | Release, schema, profile, cross-module contracts, workflows, validation routing | Real affected suites on their declared hosts; validation control-plane changes also run an independent self-protection oracle |

`scripts/validation/change-risk-rules.json` is the single path-routing source. Workflows consume schema-2 `scripts/validate-change.ps1` output and do not maintain a second path table. The classifier returns affected suites, each suite's host dependencies, the required host union, Windows PowerShell dependencies, and the independent self-protection decision. Unknown suites, hosts, mappings, or classifier failures fail closed.

`scripts/validate-release.ps1` owns two explicit authority profiles defined by `scripts/validation/release-shard-contract.json`. `Full` is the smaller product-runtime full used by every `main` push. `RepositoryCheckpoint` adds release archive, governance, evaluation, benchmark, historical, compatibility-observation, and roadmap-adjacent assertions for weekly and manual checkpoints. The executable contract requires exact coverage and disjoint shards before either profile can pass.

## Output contract

```powershell
./scripts/validate-change.ps1 -BaseRef origin/main -HeadRef HEAD
./scripts/validate-change.ps1 -ChangedPath README.md,scripts/install.ps1 -Json
```

Text and JSON report the detected tier, required checks, skipped checks, escalation reason, changed paths, affected modules, and required suites. Schema 2 lists each affected suite as `affected-suite:<name>`, includes `affected-windows-powershell` and `validation-self-protection` only when their plan decisions require them, and always reports the PR-only `full-release-matrix` as skipped. Targeted JSON evidence records the executed suite names, counts, and per-module coverage. A skipped check means it was not required; it is never reported as passing.

Classifier JSON also owns a schema-2 `local_plan` for `iteration`, `pre_push`,
and `release`. Run it through the single local entrypoint:

```powershell
./scripts/invoke-local-validation.ps1 -Stage iteration -BaseRef origin/main -HeadRef HEAD -DryRun
./scripts/invoke-local-validation.ps1 -Stage pre-push -BaseRef origin/main -HeadRef HEAD
```

Iteration always runs the real affected suites on the current host and never runs a release profile. Pre-push repeats the affected suites, adds Windows PowerShell only when an affected suite declares that dependency, and adds the independent self-protection oracle only for validation control-plane or conservative-fallback changes. Tier 3 is therefore not synonymous with full validation. Release keeps both local PowerShell hosts and uses the repository checkpoint profile.
Dry-run output includes exact commands, hosts, suites, reasons, and explicit
skips. Executed plans add actual action and stage timestamps and durations;
timing is observational and never changes pass/fail.
Executed stages also checkpoint `local-validation-result.json` after each
completed action, preserving prior evidence if a later long-running action is
interrupted by the caller.

The targeted mappings reuse existing release helpers and fixtures: knowledge changes run catalog/index, entry metadata, public-safe metadata, experience search/regeneration, promotion, and helper consistency contracts; project bootstrap changes run the bootstrap safety fixture; bridge changes run the agent-skill bridge fixture; hooks run executable runtime fixtures; installer/runtime changes run installer contracts and runtime smoke; template and bundled snapshot changes run bootstrap safety plus language/template consistency. Runtime skills and local fixtures without a reliable mapping conservatively escalate to Tier 3.

## Leaf validation ownership and routing

A validation helper's risk follows its actual failure model, owner module, host dependency, and affected suite. A known leaf helper does not become validation control plane merely because its file name starts with `release-`. Known single-owner leaves are routed to the existing owner modules and suites in `change-risk-rules.json`; this keeps one public routing source and avoids a parallel owner manifest. Existing cross-module and release-candidate contracts remain explicitly Tier 3 without being treated as classifier self-protection surfaces.

The control plane remains Tier 3: classifier and routing code, workflows, local validation planning, the fixed gate, evidence writing, sharding contracts, and the top-level release validator. These changes run the affected suites plus `test-heavy-targeted-regression.ps1` as an independent oracle. New or unmapped helpers, fixtures, and tests conservatively route every affected suite, every host, Windows PowerShell, and that oracle; no empty or generic PASS is possible.

This ownership contract preserves `main` push full product-runtime validation and the fixed validation gate, while removing the old rule that every Tier 3 PR must run the release validator.

## Validation authority migration

| Concern | Product-runtime full (`main` push) | Repository checkpoint (weekly/manual) |
|---|---|---|
| Product safety and public boundary | Authoritative | Reused |
| Installer, bootstrap, runtime, templates, hooks | Authoritative | Reused plus scheduled observations |
| Governance and repository policy | — | Authoritative |
| Release archive and historical notes | — | Authoritative |
| Evaluation and benchmark artifacts | — | Authoritative |
| Knowledge candidate/search lifecycle | — | Authoritative |

The previous 92-check checkpoint inventory is reduced to 60 public check authorities: 6 obsolete checks are retired and 26 duplicate results are merged into existing authorities while their assertions and detailed evidence continue to execute. Product-runtime full is 25 authorities (7 platform-neutral and 18 runtime), so `main` remains fully checked without carrying checkpoint-only history and governance work on every host.

Rollback is contract-first: restore the prior `release-shard-contract.json`, validator shard routing, workflow job conditions, and gate fixtures together. Partial rollback is forbidden because classifier outputs, workflow matrices, shard coverage, and the fixed gate form one fail-closed contract.

The classifier job runs only deterministic path-classification and routing-contract tests. Executable knowledge, bootstrap, bridge, installer, and mixed-path targeted regressions run through `test-heavy-targeted-regression.ps1`; Hosted self-protection invokes `test-heavy-targeted-regression.ps1 -Json` exactly once when the classifier requires the independent oracle. Documentation modules in mixed Tier 1/2 changes are covered by diff, parse, and public-safe base checks; every affected runtime module must still execute a mapped targeted suite. Only the two existing repository guard test surfaces map to `repository-guards`; future or unmapped `scripts/test-*` paths escalate to Tier 3.

## Expected hosted cost

The baseline before risk routing was four complete validator calls for every PR (PowerShell 7 on Windows, Ubuntu, and macOS, plus Windows PowerShell 5.1), in addition to base and identity guards.

| Representative PR | Before | After |
|---|---|---|
| Ordinary docs | 4 complete validators + 2 guards | classifier + 1 quick job + 2 guards; 0 complete validators |
| Knowledge | 4 complete validators + 2 guards | classifier + 1 quick job + 2 guards; 0 complete validators |
| Skill or installer | 4 complete validators + 2 guards | classifier + 3 targeted OS jobs + 2 guards; 0 complete validators |
| Release content | 4 complete validators + 2 guards | classifier + affected release-checkpoint suite on Ubuntu + 2 guards |
| Validation routing | 4 complete validators + 2 guards | classifier + affected suites on declared hosts + 1 independent self-protection oracle + 2 guards |

The classifier adds one auditable job. Pull requests run only real affected suites on their declared hosts, while `main` runs the complete product-runtime profile and weekly/manual events run the complete repository checkpoint. The reduction comes from authority separation, host-aware execution, retirement, and duplicate aggregation—not from relabeling skipped work.

## Conservative boundaries

- Empty diffs, unresolved refs, malformed Git diff records, unknown paths, unmapped runtime skills or fixtures, and classifier failures escalate to Tier 3.
- Every Tier 1 or Tier 2 affected module must execute at least one mapped suite. Zero module checks fail validation; classification or parsing alone cannot produce a targeted PASS.
- Renames classify both the old and new path; deletions classify the deleted path.
- `main` pushes run the product-runtime full profile and bind evidence to the pushed SHA. Weekly schedules and manual dispatches run the repository checkpoint profile.
- Pull-request classification uses the exact event base/head diff, while every selected validation job checks out and re-verifies `refs/pull/<number>/merge`. Candidate evidence binds the merge-ref commit, tree, ordered parents, base/head identities, latest Release run generation, and current-generation final gate; base and identity guards remain independent of the canonical producer closure.
- Push jobs use the pushed SHA. Candidate evidence and push observations are never reused across identities or attempts.
- Base and identity guards remain independent fail-closed workflow surfaces.
