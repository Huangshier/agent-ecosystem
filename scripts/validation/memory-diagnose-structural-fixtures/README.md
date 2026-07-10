# Memory Diagnose Structural Fixtures

This directory contains public-safe fixture families for deterministic release
validation of structural findings from `memory_diagnose.ps1`.

| Entry | Summary | Status | Refs | Last reviewed |
| --- | --- | --- | --- | --- |
| [`completed-list-growth/`](completed-list-growth/) | Covers compact and backlogged completed sections in hot `process.txt` memory. | Active; issue #155 is closed as completed and PR #163 is merged. | [Family notes](completed-list-growth/README.md), [release check](../release-memory-diagnostics-fixture-checks.ps1) | 2026-07-11 |
| [`hot-memory-soft-length/`](hot-memory-soft-length/) | Covers the soft line limits for hot `process.txt` and `plan.md` memory. | Active; issue #167 is closed as completed and PR #190 is merged. | [Family notes](hot-memory-soft-length/README.md), [diagnostic](../../../skills/memory-governance/scripts/memory_diagnose.ps1) | 2026-07-11 |
| [`directory-index-health/`](directory-index-health/) | Covers opt-in missing-index warnings, direct-file thresholds, and reparse-point exclusion. | Active; phase 1 PR #234 is merged and issue #217 remains open for phase 2. | [Family notes](directory-index-health/README.md), [directory index reference](../../../skills/memory-governance/references/directory-index-template.md) | 2026-07-11 |

Keep this table synchronized with the direct fixture-family directories. Use
repository-relative links and record only durable public facts.
