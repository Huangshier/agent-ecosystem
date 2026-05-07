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

## Related Repositories
- Global shared templates and experience live in `knowledge-hub`.
- This skill governs how project-local memory should be cleaned and routed. It may mark global candidates, but promotion is a separate `knowledge-hub/scripts` maintenance action.
