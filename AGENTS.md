# AGENTS.md

Project-level agent entrypoint.

Root `.agents/` is local runtime memory for this checkout. It may exist on a
maintainer machine after bootstrap or previous agent work, but it is not a
public fact source and is not tracked by this repository.

## Project Language Policy

Project memory language: English.

The root `README.md` is the chosen Simplified Chinese repository homepage, with
`README.en.md` as the English entrypoint and `README.zh-CN.md` as a
compatibility redirect. Deeper public documentation may remain English-first
unless a file or issue explicitly targets another language. Keep commands,
paths, APIs, file names, code identifiers, and raw error text in their original
form.

## Startup Sources

At the start of any non-trivial task, read this root file first. If local
`.agents/` files exist, they may be read as checkout-local working memory in
this order:

1. `.agents/AGENTS.md`
2. `.agents/process.txt`
3. `.agents/plan.md` (for non-trivial tasks)
4. `.agents/context/README.md`, then only matching `.agents/context/**` entries by Summary, Keywords, or task relevance

Do not preload the full `.agents/context/` tree at startup.

If local `.agents/` files are absent or stale, use public sources instead:

- this root `AGENTS.md`
- GitHub issues and pull requests
- `docs/specs/**`
- `docs/agent-governance.md`
- `docs/release-process.md`
- `CHANGELOG.md`
- release notes under `docs/releases/`
- curated knowledge under `knowledge-hub/knowledge/`

Core rules that apply even if `.agents/AGENTS.md` was not loaded:
- Follow system, runtime, and explicit user instructions before project defaults.
- Make routine reversible implementation choices yourself; stop for genuine ambiguity, destructive actions, external writes, missing credentials, or policy/safety risk.
- For broad or underspecified requests, do read-only exploration first, then clarify goal/scope/validation before editing when needed.
- For non-trivial work, prefer a lightweight work package under `docs/specs/<slug>/` before implementation.
- Keep `.agents/plan.md` session-local when local runtime memory exists; do not duplicate full project specs or task lists there.
- Keep `docs/specs/**` durable. Specs may record goals, non-goals, decisions,
  risks, acceptance criteria, and completed evidence. They should not become a
  long-lived dashboard for the current branch, waiting pull requests, pending
  hosted checks, or local publish steps.
- Commit only when the user or project policy asks for it. Push only when explicitly requested or when established project workflow clearly requires it.

For non-trivial work that should survive the current session, use:
- `docs/specs/<slug>/spec.md` for durable goals, constraints, approach, and acceptance
- `docs/specs/<slug>/tasks.md` for long-lived execution steps when the work is multi-stage
- `docs/specs/_templates/` for reusable project templates

For multi-stage work, use an Execution Contract in the spec so the agent continues to the next validated phase until the stop rule is triggered.
