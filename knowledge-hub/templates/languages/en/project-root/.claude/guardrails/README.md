# Claude Code Guardrails

These guardrails are a template reliability contract for Claude Code projects
created by project-bootstrap. They help the agent notice when required project
context is missing before it continues work.

They are not a security sandbox, a permissions isolation model, or automatic
authorization for external writes. A project still decides which external write
paths are allowed, and maintainers still make review, merge, tag, and release
decisions.

## Required Awareness

Claude Code work should confirm these surfaces before acting:

- `CLAUDE.md` loaded the project entrypoint.
- `AGENTS.md`, `.agents/AGENTS.md`, `.agents/process.txt`, and
  `.agents/plan.md` were considered when present.
- The project memory language and `.agents/hub.lock.json` state were checked
  before memory refresh, upgrade, reset, or migration work.
- Public and private material stay on the correct side of the boundary.
- External writes match the current write authorization profile.
- Dangerous memory refresh or reset modes require explicit confirmation.
- Missing authority, missing context, wrong write path, or uncertain scope ends
  in a stop point such as `needs-human`, not silent continuation.
- Raw artifacts remain local or private unless a public-safe summary is
  intentionally prepared.

## Write Authorization Profiles

The default profile is `local-only`: local file work is allowed when the user
or project instructions authorize it, while external writes require explicit
confirmation.

The `public-contributor` profile keeps ordinary public collaboration open:
issues, fork pull requests, CI, and maintainer review do not require a bot
identity.

Projects may define a stricter maintenance profile when they have a declared
automation identity or repository-specific workflow. That profile is
project-specific; it is not a universal project-bootstrap requirement.

See `profile.json` for the deterministic profile shape validated by the release
validator.
