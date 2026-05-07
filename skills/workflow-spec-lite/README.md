# Workflow Spec Lite

Lightweight spec-first workflow for non-trivial work. Create just enough structure before execution so important work does not live only in chat history or session memory.

## Why

When tackling non-trivial tasks - features spanning multiple files, research threads, refactors, or debugging efforts - it is easy for goals, constraints, and acceptance criteria to get lost in conversation. This skill ensures that durable work intent is captured in project documentation, not just in ephemeral agent memory.

## How It Works

The skill routes incoming work into three complexity tiers:

| Route | When | Output |
|-------|------|--------|
| **Quick** | Single file, clear target, obvious validation | No spec file - just execute |
| **Standard** | Multiple files, constraints need writing down, may span sessions | `docs/specs/<slug>/spec.md` |
| **Deep** | Multi-stage, cross-module, research + implementation, needs review/handoff | `docs/specs/<slug>/spec.md` + `docs/specs/<slug>/tasks.md` |

## Output Structure

```
docs/
  specs/
    <slug>/
      spec.md      # Work specification (standard & deep)
      tasks.md     # Ordered task checklist (deep only)
```

- Specs capture **what**, **why**, **constraints**, **approach**, and **acceptance criteria**.
- Tasks are **actionable, ordered, independently checkable** items mapping back to the spec.
- Project-local templates at `docs/specs/_templates/` are preferred when present.

## Repeated Execution

When a workflow needs to run repeatedly until a variable or condition is satisfied, route it as **Deep** unless it is a single check. Add a `Loop Contract` to `spec.md` with the watched variable, source of truth, check command, pass predicate, one bounded iteration action, limits, state record, and abort conditions.

Never rely on an open-ended "continue until done" instruction. Use a maximum iteration count or timeout, and stop for destructive, externally visible, non-idempotent, or ambiguous next actions.

## Multi-Phase Execution

For migrations, refactors, and `/goal`-style work where the agent should continue across stages, route as **Deep** and add an `Execution Contract`. The contract records autonomy level, phase list, continue rule, stop rule, and state record. After a phase validates, the agent should update state and continue to the next phase unless the stop rule is triggered.

## Usage

This skill is designed for AI coding assistants (e.g., CodeBuddy). It triggers automatically when the agent detects non-trivial work that benefits from upfront specification.

Before routing work, it runs a project context gate. If `project-context-gate` is installed, use it. If not, manually load root `AGENTS.md`, `.agents/AGENTS.md`, `.agents/context/`, `.agents/process.txt`, `.agents/plan.md`, and any active `docs/specs` files, then summarize a short constraint capsule.

Typical prompt:

```
Use workflow-spec-lite to route this work as quick, standard, or deep and create docs/specs artifacts when needed.
```

## When to Use

Use this skill when at least one of these is true:

- The request is not a trivial one-file change with obvious completion criteria
- The work spans multiple files, modules, stages, or validation steps
- The user is still clarifying what "done" means
- The task is exploratory or research-heavy (reverse engineering, unfamiliar code)
- The work has meaningful constraints, assumptions, or risks that should survive the current session
- The task is resuming after context compaction, interruption, or a user correction

**Do not use** for tiny local fixes with a clear file target and clear acceptance, or for pure memory cleanup tasks.

## Files

```
workflow-spec-lite/
|-- SKILL.md                          # Skill definition and workflow instructions
|-- README.md                         # This file
|-- agents/
|   `-- openai.yaml                   # Agent interface configuration
`-- references/
    |-- complexity-routing.md         # Routing heuristics (quick / standard / deep)
    |-- spec-template.md              # Template for spec.md
    `-- tasks-template.md             # Template for tasks.md
```

## License

MIT
