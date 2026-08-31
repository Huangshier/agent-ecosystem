# Project workspace

This directory contains the project-local workspace surface.

- `work/`, `context/`, `procedures/`, and `skills/` are project-local directories.
- Work, Context, Procedure, and Spec are the only canonical durable asset types.
- `docs/specs/` contains project-local specification surfaces; it is not runtime-owned.
- `skills/` contains project-local Skills and promoted Skills; packaged runtime Skills remain separate.
- `.cache/` is derived data and may be rebuilt. Runtime uninstall must not remove this workspace.

Bootstrap creates this structure only. It does not create placeholder assets.
