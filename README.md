# Agent Ecosystem

Agent Ecosystem is a workflow kernel for agent-assisted software projects.

[简体中文](README.zh-CN.md)

It provides a small, installable, and validated base flow for project memory,
context loading, lightweight specs, memory maintenance, and reusable knowledge.
It is meant to be adapted: teams can start with the public kernel, then adjust
their `.agents/` memory, specs, domain knowledge, and custom skills to fit their
own project workflow.

Current release: `v0.3.0`.

## What It Is

- A Workflow Kernel for agent-assisted software projects.
- Project memory scaffolding through `project-bootstrap`.
- Progressive context loading through `project-context-gate`.
- Lightweight durable work packages through `workflow-spec-lite`.
- Memory cleanup and reusable lesson routing through `memory-governance`.
- Public-safe knowledge hub templates and a domain-pack scaffold.
- PowerShell-first install, uninstall, and release validation tooling.

## What It Is Not

- Not an agent runtime.
- Not a model orchestration framework.
- Not a task scheduler.
- Not a universal workflow that every project must follow unchanged.
- Not a place for private overlays, local migration notes, or machine-specific
  runtime state.

## Extension Model

Use the public kernel as a stable starting point, then adapt locally:

- Keep project-local memory in each project's `.agents/` directory.
- Keep long-lived work packages in `docs/specs/`.
- Add project or domain knowledge under local `.agents/context/`.
- Incubate custom skills privately until their workflow is stable and
  public-safe.
- Promote reusable public knowledge only after repeated use proves the pattern.

## Repository Model

- Public source: this repository.
- Runtime layer: generated under `$HOME/.agents` or another target by the
  installer.
- Project local layer: each project's `.agents/` and `docs/specs/` directories.
- Private overlay: optional sibling repository for private profiles, knowledge,
  experimental skills, and local migration records.

## Quick Start

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -Profile recommended
```

For safe testing, install into a temporary runtime first:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -Profile recommended -TargetDir <temp-runtime> -Copy -Force
```

On non-Windows systems, or when PowerShell 7+ is already available, use
`pwsh -NoProfile -File` with the same script arguments. See
[Shell strategy](docs/shell-strategy.md) for the current non-PowerShell policy.

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

Current public profiles:

- `minimal`: installs the bootstrap skill and public knowledge hub templates.
- `recommended`: installs the Workflow Kernel and public knowledge hub.
- `full`: currently installs the same public content as `recommended`.
- `dev`: currently installs the same public content as `recommended`.

`full` and `dev` are reserved for future installable public domain packs and
developer maintenance tooling after the kernel base flow is stable.

## Project Docs

- [Architecture](docs/architecture.md)
- [How to adapt](docs/how-to-adapt.md)
- [Language policy](docs/language-policy.md)
- [Release process](docs/release-process.md)
- [Release readiness](docs/release-readiness.md)
- [Shell strategy](docs/shell-strategy.md)
- [v0.3.0 release notes](docs/releases/v0.3.0.md)
- [v0.2.0 release notes](docs/releases/v0.2.0.md)
- [Knowledge catalog](knowledge-hub/knowledge-catalog.md)
- [Examples](examples/README.md)
