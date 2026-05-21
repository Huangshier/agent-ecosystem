# Agent Ecosystem Evolution Plan

## Summary

Evolve the agent workspace into a lightweight public engineering system built
around a thin runtime, a Workflow Kernel, a layered knowledge hub, optional
domain packs, and project-local overlays.

This public roadmap describes the reusable product direction. Local migration
state, private repository mappings, machine-specific paths, and sensitive audit
notes belong in the private overlay repository.

## Target Operating Model

```text
agent-ecosystem/
  README.md
  LICENSE
  scripts/
  skills/
  knowledge-hub/
  docs/
  examples/

private-overlay/
  profiles/
  knowledge/
  skills/
  docs/migration/
```

## Layer Model

- Runtime Rules: minimal behavior rules installed into the runtime layer.
- Workflow Kernel: reusable core skills for bootstrap, context loading, spec
  routing, and memory governance.
- Knowledge Hub: cross-project templates, experience, patterns, and standards.
- Domain Packs: optional domain-specific knowledge or skills after repeated use
  proves they are stable.
- Project Overlay: project-local `.agents/` memory and `docs/specs/` work
  packages.

## First Public Release

The first public release should include only the Workflow Kernel and public
knowledge templates:

- `project-bootstrap`
- `project-context-gate`
- `workflow-spec-lite`
- `memory-governance`

Domain skills are deferred until the public kernel is stable.

## Knowledge Hub Phase 3

The next public knowledge-hub layer is catalog-first:

- `knowledge-hub/knowledge-catalog.md` is the reading map for agents and
  maintainers.
- `knowledge/experience/` keeps workflow lessons and its script-search
  `index.json`.
- `knowledge/patterns/` keeps reusable engineering workflows.
- `knowledge/standards/` keeps stable cross-project rules and boundaries.

`index.json` remains generated registry state for experience search. The
Markdown catalog remains the curated reading surface.

## Domain Pack Incubation

Public domain packs start as Markdown knowledge bundles under
`knowledge-hub/knowledge/domain-packs/`. A pack can describe reusable domain
vocabulary, checklists, and boundaries, but it should not contain private
environment assumptions or become a skill until repeated usage proves a stable
workflow. The authoritative lifecycle, manifest, promotion, public-safety,
validation, and profile-boundary rules live in
[Domain pack governance](../domain-pack-governance.md).

The first public scaffold is `embedded-core`, a public-safe embedded validation
checklist. SDK-specific automation and private domain skills remain outside the
public kernel.

Promotion from a Markdown domain pack to a scriptable public skill follows the
domain-pack governance lifecycle. The minimum current gate is:

- the workflow has been used successfully in at least two independent projects
  or by two independent maintainers
- the inputs, outputs, stop rules, and validation commands are stable enough to
  document without private environment assumptions
- public-safe fixtures or examples exist for the expected success and failure
  paths
- the workflow can pass the release validator without requiring private
  credentials, local-only paths, or hardware-specific access

## Installation Direction

The long-term quick start should be:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -Profile recommended
```

Planned profiles:

- `minimal`: smallest bootstrap support.
- `recommended`: Workflow Kernel and public knowledge hub.
- `full`: all public skills and public domain packs when public packs become
  installable content.
- `dev`: development and migration support tools.

## Shell Direction

The public Workflow Kernel remains PowerShell-first. Windows users can use
Windows PowerShell 5.1; cross-platform users should use PowerShell 7+ with
`pwsh -NoProfile -File`.

Bash or Zsh wrappers are deferred until a later release. When added, they should
be thin launchers that locate `pwsh` and delegate to the canonical `.ps1`
entrypoints rather than reimplementing install, uninstall, context-gate, or
release validation behavior.

## Language Policy

The repository homepage is Simplified Chinese in `README.md`, with
`README.en.md` as the English entrypoint and `README.zh-CN.md` kept as a
compatibility redirect. Deeper public documentation may remain English-first
unless a file or issue explicitly targets another language.

Project memory language is project-local and should be declared in the
project's `.agents/AGENTS.md` under a `Project Language Policy` section when
that template is installed.

## Open Source Readiness

Before public release:

- Remove machine-specific paths and private repository details.
- Audit for credentials, tokens, internal URLs, private project names, and
  sensitive reverse-engineering details.
- Verify that the public quick start works without the private overlay.
- Verify that private overlays can be layered on top without copying the public
  tree.

## Test Plan

- Validate repository structure.
- Install the recommended profile into a temporary runtime directory.
- Bootstrap an empty test project.
- Run a simulated task through context gate, spec-lite, implementation intent,
  and memory governance.
- Verify sensitive audit checks before public release.
