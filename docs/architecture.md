# Architecture

## Purpose

Define the boundaries between public source, private overlay, generated runtime,
and project-local memory.

## Source And Runtime Boundaries

- Public source lives in this repository.
- Private overlays live outside this repository.
- Runtime installs are generated under `$HOME/.agents`.
- Project-local state lives in each project's `.agents/` and `docs/specs/`
  directories.

## Workflow Kernel

The Workflow Kernel is the reusable core:

- `project-bootstrap`: install project memory scaffolds.
- `project-context-gate`: load project context progressively.
- `workflow-spec-lite`: route non-trivial work into lightweight specs.
- `memory-governance`: maintain project memory and reusable lessons.

Domain-specific skills should not be required by the kernel.

