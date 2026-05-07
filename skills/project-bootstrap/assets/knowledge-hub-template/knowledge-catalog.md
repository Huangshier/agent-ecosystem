# Knowledge Catalog

This catalog is the human and agent reading map for the installed knowledge
hub. Use it before opening individual knowledge files.

## Reading Rule

- Start here when a task may benefit from reusable cross-project knowledge.
- Open only the entries that match the current task.
- Use `knowledge/experience/index.json` and `scripts/search_experience.ps1` for
  scriptable experience search when those scripts are installed.
- Treat this catalog as the curated reading map; do not use it as generated
  registry state.

## Knowledge Layers

| Layer | Purpose | Open when |
| --- | --- | --- |
| `knowledge/experience/` | Reusable lessons from toolchains, host environments, shells, build systems, caches, ports, permissions, path handling, and workflow failures. | You see a recurring failure shape or host/tooling symptom. |
| `knowledge/patterns/` | Reusable engineering workflows that coordinate agent work across context loading, planning, implementation, and validation. | You need a proven work sequence, not a troubleshooting case. |
| `knowledge/standards/` | Cross-project rules and boundaries that should stay stable across projects and releases. | You need to decide where content belongs or how reusable artifacts should behave. |

## Current Entries

### Experience

- No installed experience entries are bundled by default. Use promotion helpers
  to add reviewed cross-project lessons.

### Patterns

- [Context Gate to Spec to Validation Loop](knowledge/patterns/context-gate-spec-validation-loop.md)

### Standards

- [Public Knowledge Boundary](knowledge/standards/public-knowledge-boundary.md)

## Maintenance

- Add reusable knowledge only after confirming it is generic and cross-project.
- Keep local machine paths and project-only facts out of this hub.
- Update this catalog when adding, moving, deprecating, or renaming knowledge
  entries.
- Rebuild `knowledge/experience/index.json` after editing experience files.
