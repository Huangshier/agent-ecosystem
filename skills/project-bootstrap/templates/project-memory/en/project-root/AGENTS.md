# AGENTS.md

Project-level agent entrypoint.

Primary instructions are in `.agents/AGENTS.md`. At the start of any non-trivial task, read that file before planning or editing. If the runtime does not automatically load nested guidance, this root file is the fallback contract.

Project memory language: English.

Minimum read order for each substantive session:
1. `.agents/AGENTS.md`
2. `.agents/process.txt`
3. `.agents/plan.md` (for non-trivial tasks)
4. `.agents/context/README.md`, then only matching `.agents/context/**` entries by Summary, Keywords, or task relevance

Do not preload the full `.agents/context/` tree at startup.

Core rules that apply even if `.agents/AGENTS.md` was not loaded:
- Follow system, runtime, and explicit user instructions before project defaults.
- Make routine reversible implementation choices yourself; stop for genuine ambiguity, destructive actions, external writes, missing credentials, or policy/safety risk.
- For broad or underspecified requests, do read-only exploration first, then clarify goal/scope/validation before editing when needed.
- For non-trivial work, prefer a lightweight work package under `docs/specs/<slug>/` before implementation.
- Keep `.agents/plan.md` session-local; do not duplicate full project specs or task lists there.
- Commit only when the user or project policy asks for it. Push only when explicitly requested or when established project workflow clearly requires it.

For non-trivial work that should survive the current session, use:
- `docs/specs/<slug>/spec.md` for durable goals, constraints, approach, and acceptance.
- `docs/specs/<slug>/tasks.md` for long-lived execution steps when the work is multi-stage.
- `docs/specs/_templates/` for reusable project templates.

For multi-stage work, use an Execution Contract in the spec so the agent continues to the next validated phase until the stop rule is triggered.
