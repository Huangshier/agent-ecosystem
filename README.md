# Agent Ecosystem

Lightweight engineering scaffolding for agent-assisted software projects.

[简体中文](README.zh-CN.md)

The project is organized around a small Workflow Kernel, a layered knowledge
hub, and project-local memory templates. The first public release is focused on
the reusable kernel only; domain-specific skills are intentionally deferred.

Planned first public release: `v0.1.0`.

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

## Project Docs

- [Architecture](docs/architecture.md)
- [Language policy](docs/language-policy.md)
- [Release readiness](docs/release-readiness.md)

## Status

The Workflow Kernel has been imported into this public repository. The public
installer and recommended profile have passed temporary-runtime validation.
The repository is being prepared as a local `v0.1.0` release candidate; push,
tag, and release publication are still pending maintainer review.

## Quick Start

```powershell
.\scripts\install.ps1 -Profile recommended
```

For safe testing, install into a temporary runtime first:

```powershell
.\scripts\install.ps1 -Profile recommended -TargetDir <temp-runtime> -Copy -Force
```

The default install mode prefers links (`Junction` on Windows,
`SymbolicLink` elsewhere) and falls back to copy mode if link creation fails.
The generated runtime manifest records the mode used for each installed item.
