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

## Installation Direction

The long-term quick start should be:

```powershell
.\scripts\install.ps1 -Profile recommended
```

Planned profiles:

- `minimal`: smallest bootstrap support.
- `recommended`: Workflow Kernel and public knowledge hub.
- `full`: all public skills and public domain packs.
- `dev`: development and migration support tools.

## Language Policy

Community-facing public documentation is English-first. Chinese documentation
may live in `README.zh-CN.md` or `docs/zh-CN/`.

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
