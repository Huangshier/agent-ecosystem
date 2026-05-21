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
- Keep this directory as durable public work packages, not as a GitHub or local
  checkout status database. Record goals, non-goals, accepted scope, durable
  decisions, risks, acceptance criteria, and completed evidence. Do not preserve
  current local branch names, waiting pull-request merge steps, pending hosted
  checks, branch publishing steps, or duplicate issue-label dashboards as
  long-lived state.
