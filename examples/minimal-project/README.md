# Minimal Project Example

This example shows the project-local files created or maintained around the
Workflow Kernel. It is intentionally small and does not include private overlay
content.

## Layout

```text
minimal-project/
  AGENTS.md
  .agents/
    AGENTS.md
    process.txt
    plan.md
  docs/
    specs/
      example-work/
        spec.md
        tasks.md
```

## Use

1. Bootstrap your own project with `project-bootstrap`.
2. Keep project rules in `.agents/AGENTS.md`.
3. Keep current session state in `.agents/process.txt` and `.agents/plan.md`.
4. Put durable multi-step work in `docs/specs/<slug>/`.
5. Run `project-context-gate` before non-trivial work.

The example files are illustrative. Prefer freshly bootstrapped templates for a
real project so the `hub.lock.json` matches your installed runtime.
