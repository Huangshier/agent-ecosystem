# memory-governance

Memory maintenance skill for project-level `.agents` files.

## Purpose
- Keep project memory concise and reusable across sessions.
- Route stable facts, active status, and durable experience into the right `.agents` files.
- Distinguish project-local experience from cross-project experience that belongs in the global knowledge hub.
- When projects use `docs/specs/`, keep those as the long-lived work package and avoid duplicating them into `.agents`.
- Refresh project context before memory edits and again after phase commits when work continues.
- Apply progressive disclosure: hot session memory first, active specs second, context/global experience only by keyword.

## Key Files
- `SKILL.md`: skill workflow and output contract.
- `scripts/memory_diagnose.ps1`: read-only memory health diagnosis.
- `agents/openai.yaml`: skill metadata for local Agent usage.

Public templates use `## Summary` and `## Keywords` for context discovery
metadata. The diagnosis helper also recognizes localized equivalents for
project memory files.

## Structural Diagnostics Design
Future structural diagnostics for `memory_diagnose.ps1` should follow
[`docs/roadmap/memory-diagnose-structural-diagnostics.md`](../../docs/roadmap/memory-diagnose-structural-diagnostics.md).
That design records #155 Part B goals, non-goals, false-positive boundaries,
fixture expectations, and the staged implementation plan. It is intentionally
design-first and does not change current helper behavior.

## Legacy Memory Upgrade Stable Facts
`skills/project-bootstrap/scripts/memory_upgrade.ps1 -Mode Apply` is backup-first
and preserves stable notes only through deterministic section rules. Compact
bullet facts are kept from `# Confirmed Notes`, `## Stable Facts`,
`# 已确认记录`, or `## 稳定事实` after volatile TODO, checkbox, next-step,
branch / PR waiting, and temporary runtime lines are filtered. The helper does
not infer stable facts from arbitrary prose or use semantic classification.

## Related Repositories
- Global shared templates and experience live in `knowledge-hub`.
- This skill governs how project-local memory should be cleaned and routed. It may mark global candidates, but promotion is a separate `knowledge-hub/scripts` maintenance action.
