# PR validation risk tiers

Pull requests are classified before expensive validation starts. The classifier is deterministic, takes the highest tier when paths from multiple categories change, and escalates unresolved or high-risk unknown input to Tier 3.

| Tier | Typical changes | Hosted validation |
|---|---|---|
| 0 | Metadata, PR template, ordinary documentation | Classification, quick diff/parse/public-safe checks, base guard, identity guard |
| 1 | Knowledge and mapped non-runtime repository helpers | Tier 0 checks plus quick repository checks and real affected-module contracts |
| 2 | Mapped bootstrap, templates, installer, bridge, hooks, and project workspace asset surfaces | Cross-platform affected-module fixtures and runtime checks plus base and identity guards |
| 3 | Release, schema, profile, cross-module contracts, workflows, validation routing | Real affected suites on their declared hosts; validation control-plane changes also run an independent self-protection oracle |

`scripts/validation/change-risk-rules.json` is the single path-routing source. Workflows consume schema-2 `scripts/validate-change.ps1` output and do not maintain a second path table. Explicit rules run first; unmatched executable or control-plane surfaces fail closed, known content namespaces use their limited defaults, and only paths matching the finite ordinary-content pattern use the lightweight ordinary default. Every remaining unresolved path fails closed to Tier 3. The classifier returns affected suites, each suite's host dependencies, the required host union, and the independent self-protection decision. Unknown suites, hosts, high-risk mappings, or classifier failures fail closed.

`scripts/validate-release.ps1` owns two explicit Release authority profiles defined by `scripts/validation/release-shard-contract.json`. `Full` is the smaller product-runtime Release profile. `RepositoryCheckpoint` adds release archive, governance, evaluation, benchmark, historical, compatibility-observation, and roadmap-adjacent assertions for manual checkpoints. `main` pushes use the separate thin `main health` contract; they do not select either Release profile. The executable contract requires exact coverage and disjoint shards before either Release profile can pass.

## Output contract

```powershell
./scripts/validate-change.ps1 -BaseRef origin/main -HeadRef HEAD
./scripts/validate-change.ps1 -ChangedPath README.md,scripts/install.ps1 -Json
```

Text and JSON report the detected tier, required checks, skipped checks, routing reason, changed paths, affected modules, and required suites. Routing reasons distinguish an explicit rule, a namespace default, the ordinary-content default, a high-risk unknown fallback, and the final unresolved fallback. Schema 2 lists each affected suite as `affected-suite:<name>`, includes `validation-self-protection` only when its plan decision requires it, and always reports the PR-only `full-release-matrix` as skipped. Targeted JSON evidence records the executed suite names, counts, and per-module coverage. A skipped check means it was not required; it is never reported as passing.

Classifier JSON also owns a schema-2 `local_plan` for `iteration`, `pre_push`,
and `release`. Run it through the single local entrypoint:

```powershell
./scripts/invoke-local-validation.ps1 -Stage iteration -BaseRef origin/main -HeadRef HEAD -DryRun
./scripts/invoke-local-validation.ps1 -Stage pre-push -BaseRef origin/main -HeadRef HEAD
```

Iteration always runs the real affected suites on the current host and never runs a release profile. Pre-push keeps the same affected plan and final freshness boundary, but it may reuse complete successful iteration evidence when the compact candidate/tree, validation authority, routing plan, and host/runtime binding matches exactly and every planned iteration action completed successfully. Missing, failed, incomplete, malformed, or mismatched evidence causes the whole affected plan to be re-executed. The independent self-protection oracle remains in that plan only for validation control-plane or conservative-fallback changes. Tier 3 is therefore not synonymous with full validation. Release keeps the pwsh 7.6 host and uses the repository checkpoint profile.
Dry-run output includes exact commands, hosts, suites, reasons, and explicit
skips. Executed plans add actual action and stage timestamps and durations;
timing is observational and never changes pass/fail.
Executed stages also checkpoint `local-validation-result.json` after each
completed action, preserving prior evidence if a later long-running action is
interrupted by the caller. A caller can pass a completed iteration result to
pre-push with `-IterationEvidencePath`, or use the same explicit `ScratchRoot`;
action output records `executed`, `reused`, or `re-executed` plus the reason.

The targeted mappings reuse existing release helpers and fixtures: knowledge changes run catalog/index, entry metadata, public-safe metadata, experience search/regeneration, promotion, and helper consistency contracts; project bootstrap changes run the bootstrap safety fixture; bridge changes run the agent-skill bridge fixture; hooks run executable runtime fixtures; installer/runtime changes run installer contracts and runtime smoke; template and bundled snapshot changes run bootstrap safety plus language/template consistency. Project workspace schemas, canonical asset templates, the read-only parser, and the reserved continuity and migration paths run the `workspace-assets` fixture suite on Windows, Ubuntu, and macOS. Runtime skills and local fixtures without a reliable mapping conservatively escalate to Tier 3.

## Leaf validation ownership and routing

A validation helper's risk follows its actual failure model, owner module, host dependency, and affected suite. A known leaf helper does not become validation control plane merely because its file name starts with `release-`. Known single-owner leaves are routed to the existing owner modules and suites in `change-risk-rules.json`; this keeps one public routing source and avoids a parallel owner manifest. Existing cross-module and release-candidate contracts remain explicitly Tier 3 without being treated as classifier self-protection surfaces.

The control plane remains Tier 3: classifier and routing code, workflows, local validation planning, the fixed gate, Release evidence writing, the Release shard contract, and the top-level release validator. These changes run the affected suites plus `test-heavy-targeted-regression.ps1` as an independent oracle. New or unmapped helpers, fixtures, and tests conservatively route every affected suite, every host, and that oracle; no empty or generic PASS is possible.

This ownership contract preserves the thin `main health` contract and fixed validation gate, while removing the old rule that every Tier 3 PR must run the release validator. PR self-protection remains conditional on a validation control-plane change; direct candidate identity checks remain in the validation jobs, while canonical candidate aggregation and main lineage shadow are retired.

## Validation authority migration

| Concern | Main health (`main` push) | Release profile (manual or publication) |
|---|---|---|
| PowerShell/JSON parse and public boundary | Thin parse and public-safe/sensitive scan | Authoritative and reused |
| Installer, bootstrap, and C3.3 runtime | One single-host copy-install/bootstrap/workspace smoke | Authoritative and reused |
| Governance and repository policy | — | Authoritative |
| Release archive and historical notes | — | Authoritative |
| Evaluation and benchmark artifacts | — | Authoritative |
| Knowledge candidate/search lifecycle | — | Authoritative |

The previous 92-check checkpoint inventory is reduced to 60 public check authorities: 6 obsolete checks are retired and 26 duplicate results are merged into existing authorities while their assertions and detailed evidence continue to execute. The 25-check product-runtime Release profile (7 platform-neutral and 18 runtime) remains available for Release validation; `main` health intentionally does not claim that coverage.

Rollback is contract-first: restore the prior `release-shard-contract.json`, validator shard routing, workflow job conditions, and gate fixtures together. Partial rollback is forbidden because classifier outputs, workflow matrices, shard coverage, and the fixed gate form one fail-closed contract.

The classifier job runs only deterministic path-classification and routing-contract tests. Hosted self-protection invokes `test-heavy-targeted-regression.ps1 -Json` exactly once when the classifier requires the independent oracle; that oracle is a focused validation-control-plane battery (classifier and routing fixtures, push-boundary fixtures, fail-closed output and escalation contracts, execution dedup, the gate fixture corpus, the full sensitive scan, deterministic weakening mutations, and a classifier-to-targeted-executor dispatch contract) and does not replay business validation suites already owned by affected validation. Documentation modules in mixed Tier 1/2 changes are covered by diff, parse, and public-safe base checks; every affected runtime module must still execute a mapped targeted suite. Only the two existing repository guard test surfaces map to `repository-guards`; future or unmapped `scripts/test-*` paths escalate to Tier 3.

## Expected hosted cost

The baseline before risk routing was three complete validator calls for every PR (PowerShell 7 on Windows, Ubuntu, and macOS), in addition to base and identity guards.

| Representative PR | Before | After |
|---|---|---|
| Ordinary docs | 3 complete validators + 2 guards | classifier + 1 quick job + 2 guards; 0 complete validators |
| Knowledge | 3 complete validators + 2 guards | classifier + 1 quick job + 2 guards; 0 complete validators |
| Skill or installer | 3 complete validators + 2 guards | classifier + 3 targeted OS jobs + 2 guards; 0 complete validators |
| Project workspace assets | 3 complete validators + 2 guards | classifier + `workspace-assets` on 3 targeted OS jobs + 2 guards; 0 complete validators |
| Release content | 3 complete validators + 2 guards | classifier + affected release-checkpoint suite on Ubuntu + 2 guards |
| Validation routing | 3 complete validators + 2 guards | classifier + affected suites on declared hosts + 1 independent self-protection oracle + 2 guards |

The classifier adds one auditable job. Pull requests run only real affected suites on their declared hosts, while `main` runs the thin health contract and manual events run the complete repository checkpoint. The reduction comes from authority separation, host-aware execution, retirement, and duplicate aggregation—not from relabeling skipped work.

## Conservative boundaries

- Empty diffs, unresolved refs, malformed Git diff records, unknown executable or control-plane paths, unmapped runtime skills or fixtures, and classifier failures escalate to Tier 3. A new path receives the lightweight ordinary default only when it matches the finite safe-content pattern; every other unresolved path keeps the conservative fallback and self-protection.
- Every Tier 1 or Tier 2 affected module must execute at least one mapped suite. Zero module checks fail validation; classification or parsing alone cannot produce a targeted PASS.
- Renames classify both the old and new path; deletions classify the deleted path.
- `main` pushes run main health against the pushed SHA. Manual dispatches run the repository checkpoint profile; Release publication retains the complete Release validator path.
- Pull-request classification uses the exact event base/head diff, while every selected validation job checks out and re-verifies `refs/pull/<number>/merge`. Direct candidate identity checks bind the merge-ref commit, tree, ordered parents, and base/head identities; base and identity guards remain independent.
- Push jobs use the pushed SHA. Candidate identity checks are never reused across identities or attempts.
- Base and identity guards remain independent fail-closed workflow surfaces.
