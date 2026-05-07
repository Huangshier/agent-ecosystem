# Agent Ecosystem

Lightweight engineering scaffolding for agent-assisted software projects.

The project is organized around a small Workflow Kernel, a layered knowledge
hub, and project-local memory templates. The first public release is focused on
the reusable kernel only; domain-specific skills are intentionally deferred.

## First Release Scope

- `project-bootstrap`
- `project-context-gate`
- `workflow-spec-lite`
- `memory-governance`
- Public knowledge hub templates
- Installer/profile scaffolding

## Repository Model

- Public source: this repository.
- Private overlay: optional sibling repository for private profiles, sensitive
  knowledge, experimental skills, and local migration notes.
- Runtime layer: generated under `$HOME/.agents` by the installer.
- Project local layer: each project's `.agents/` and `docs/specs/` directories.

## Status

The Workflow Kernel has been imported into this public repository. The public
quick start and installer are not ready yet.
