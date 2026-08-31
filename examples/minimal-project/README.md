# Minimal Project Example

This example shows the current C3.3 project-local workspace. It is intentionally
small and contains no runtime installation state or private overlay content.

## Fresh Bootstrap Layout

```text
minimal-project/
  AGENTS.md
  .agents/
    .gitignore
    README.md
    hub.lock.json
    work/
    context/
    procedures/
    skills/
  docs/
    specs/
```

`project-bootstrap` creates the empty canonical roots and the bootstrap metadata
shown above. Git does not track empty directories, so this repository example
uses empty `.gitkeep` files only to retain those roots. It also adds one
illustrative Spec under `docs/specs/example-work/`; neither the `.gitkeep` files
nor the example Spec are fresh bootstrap output. The generated
`.agents/hub.lock.json` is intentionally not copied into this static example
because it must describe the target project's actual bootstrap/runtime state.

## Use

1. Bootstrap your own project with `project-bootstrap`, passing
   `-ProjectLanguage en` or `-ProjectLanguage zh-CN` when an explicit language
   is required.
2. Keep the project behavior contract in root `AGENTS.md`.
3. Use `project-workspace check` and `discover` to inspect canonical assets.
4. Create a Spec in `docs/specs/<slug>/` only when work needs durable scope,
   constraints, and acceptance criteria.
5. Create a Work record only when unfinished work needs continuity across
   sessions.

Use freshly bootstrapped templates for a real project so its generated
`hub.lock.json` matches the installed runtime. Do not copy the illustrative Spec
unless the target project needs an equivalent durable work package.
