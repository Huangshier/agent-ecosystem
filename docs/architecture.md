# Architecture

## Purpose

Define the boundaries between public source, private overlay, generated runtime,
and project-local memory.

## Source And Runtime Boundaries

- Public source lives in this repository.
- Private overlays live outside this repository.
- Runtime installs are generated under `$HOME/.agents`.
- Project-local state lives in each target project's `.agents/` directory and,
  when the project chooses spec-first work packages, its local `docs/specs/`
  directory.
- This public source repository uses GitHub issues and pull request bodies as
  the canonical maintenance record. It does not track root `docs/specs/**`
  work packages for its own maintenance.

## Workflow Kernel

The Workflow Kernel is the reusable core:

- `project-bootstrap`: install project memory scaffolds.
- `project-context-gate`: load project context progressively.
- `workflow-spec-lite`: route non-trivial work into lightweight specs.
- `memory-governance`: maintain project memory and reusable lessons.

Domain-specific skills should not be required by the kernel.

## Domain Packs

Domain packs are optional knowledge bundles under
`knowledge-hub/knowledge/domain-packs/`. They start as public-safe Markdown
catalogs, checklists, and boundaries. Promote a domain pack into a skill only
after repeated cross-project use proves a stable, scriptable workflow.

The authoritative public lifecycle, manifest, promotion, safety, validation, and
profile-boundary rules are defined in
[Domain pack governance](domain-pack-governance.md).

Private domain skills and environment-specific automation belong outside this
public repository.
