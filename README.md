# Agent Ecosystem

Lightweight engineering scaffolding for agent-assisted software projects.

[简体中文](README.zh-CN.md)

The project is organized around a small Workflow Kernel, a layered knowledge
hub, and project-local memory templates. The first public release is focused on
the reusable kernel, public-safe knowledge scaffolds, and adoption examples.

Current release: `v0.2.0`.

## First Release Scope

- `project-bootstrap`
- `project-context-gate`
- `workflow-spec-lite`
- `memory-governance`
- Public knowledge hub templates
- Public-safe domain-pack scaffold
- Installer/profile scaffolding
- Adaptation guide and minimal project example

## Repository Model

- Public source: this repository.
- Private overlay: optional sibling repository for private profiles, sensitive
  knowledge, experimental skills, and local migration notes.
- Runtime layer: generated under `$HOME/.agents` by the installer.
- Project local layer: each project's `.agents/` and `docs/specs/` directories.

## Project Docs

- [Architecture](docs/architecture.md)
- [How to adapt](docs/how-to-adapt.md)
- [Language policy](docs/language-policy.md)
- [Release process](docs/release-process.md)
- [Release readiness](docs/release-readiness.md)
- [v0.2.0 release notes](docs/releases/v0.2.0.md)
- [Knowledge catalog](knowledge-hub/knowledge-catalog.md)
- [Examples](examples/README.md)

## Status

The initial `v0.1.0` public release is available. The Workflow Kernel, public
installer, public knowledge templates, and release validation workflow have
passed temporary-runtime validation.

Post-`v0.1.0` maintenance has added catalog-first knowledge, first-session
language write support, spec-lite validation, public-safe domain-pack scaffold,
and adoption examples for `v0.2.0`.

## Quick Start

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -Profile recommended
```

For safe testing, install into a temporary runtime first:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -Profile recommended -TargetDir <temp-runtime> -Copy -Force
```

On non-Windows systems, or when PowerShell 7+ is already available, use
`pwsh -NoProfile -File` with the same script arguments.

The default install mode prefers links (`Junction` on Windows,
`SymbolicLink` elsewhere) and falls back to copy mode if link creation fails.
The generated runtime manifest records the mode used for each installed item.
Generated runtime directories and manifests can contain local absolute paths.
Do not commit them to a project repository.

To remove a runtime installed by this public installer, use the manifest-based
uninstaller:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\uninstall.ps1 -TargetDir <runtime>
```

The uninstaller removes only paths recorded in `install-manifest.json` plus the
manifest itself. Unknown files are preserved. If the manifest is missing, the
script does not remove anything and prints manual cleanup guidance.

## Profiles

The `v0.1.0` release provides four public profile names:

- `minimal`: installs the bootstrap skill and public knowledge hub templates.
- `recommended`: installs the Workflow Kernel and public knowledge hub.
- `full`: currently installs the same public content as `recommended`.
- `dev`: currently installs the same public content as `recommended`.

`full` and `dev` are reserved for future installable public domain packs and
developer maintenance tooling after the kernel release is stable.
