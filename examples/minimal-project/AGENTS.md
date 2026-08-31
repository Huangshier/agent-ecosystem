# AGENTS.md

This file is the project behavior entrypoint.

- Canonical durable assets are Work, Context, Procedure, and Spec.
- Project-local Skills are a separate promoted surface; they are not a fifth canonical asset type.
- The packaged runtime owns only its installed, manifest-managed content. Project workspace files remain project-local.
- Discovery and status are read-only unless an explicit authoring operation is requested.
