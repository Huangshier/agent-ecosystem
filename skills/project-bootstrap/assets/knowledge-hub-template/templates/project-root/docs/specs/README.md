# Project Specs

Use this directory for long-lived work packages that should survive the current agent session.

Recommended structure:
- `docs/specs/<slug>/spec.md`
- `docs/specs/<slug>/tasks.md`
- `docs/specs/_templates/`

Rules:
- `spec.md` is the canonical work definition.
- `tasks.md` is optional and should exist only for multi-step work.
- Do not create `plan.md` here; `.agents/plan.md` already covers session-local planning.
- When work must repeat until a condition is satisfied, define the watched variable, check command, pass predicate, limits, and abort conditions in `spec.md` before running the loop.
