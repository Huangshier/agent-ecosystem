# Agent Ecosystem

English (current) | Simplified Chinese: [README.md](README.md)

> A lightweight Workflow Kernel for agent-assisted software projects.

Current release: `v0.5.1`

## One-Line Summary

Agent Ecosystem provides a small, installable, validated base workflow for
project memory, context loading, lightweight specs, memory maintenance, and
reusable knowledge.

It is not a demand that every project adopt the same process. Use the public
kernel as a stable starting point, then adapt project-local `.agents/` memory,
domain knowledge, and custom skills to fit the project. Target projects may
also keep local `docs/specs/` work packages when complex work needs durable
scope and acceptance evidence across sessions.

## Who It Is For

- Maintainers who want Codex or other coding agents to load project rules,
  retain context, and hand off reviewable work more reliably.
- Teams that need optional durable local work packages instead of ephemeral chat
  plans for complex work.
- Projects that want a layered model for memory, lessons, and cross-project
  knowledge.
- Users who want PowerShell-first installation, validation, and refresh tooling
  for a workflow kernel.

## What It Is Not

- Not an agent runtime.
- Not a model orchestration framework.
- Not a task scheduler.
- Not a universal workflow that every project must copy unchanged.
- Not a place for private overlays, local migration records, private auth
  material, sensitive audit findings, or generated runtime manifests.

## Core Workflow

1. Install a runtime under `$HOME/.agents` or another target directory.
2. Bootstrap a project with `project-bootstrap` to create project-level
   `AGENTS.md`, `.agents/`, and optional target-project spec scaffolds.
3. Start non-trivial work with `project-context-gate` so the agent loads
   instructions, hot memory, active specs, and relevant context progressively.
4. Use `workflow-spec-lite` to capture goals, non-goals, constraints, risks, and
   acceptance evidence for meaningful work.
5. Use `memory-governance` at handoff or closeout to keep hot memory concise and
   route durable facts and lessons to the right place.

## Five-Minute Start

Install the recommended profile:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -Profile recommended
```

For evaluation, install into a temporary runtime first:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -Profile recommended -TargetDir <temp-runtime> -Copy -Force
```

Bootstrap a project:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <runtime>\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project>
```

When the first memory write already knows the project memory language, pass it
explicitly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <runtime>\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -ProjectLanguage en
```

Run the context gate before project work:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <runtime>\skills\project-context-gate\scripts\context_gate.ps1 -ProjectRoot <project>
```

For complex work that should keep durable scope and acceptance evidence across
sessions, ask the agent to use `workflow-spec-lite` so it creates a
target-project-local `docs/specs/<slug>/spec.md` before implementation and
validation.

On non-Windows systems, or when PowerShell 7+ is already available, replace
`powershell -NoProfile -ExecutionPolicy Bypass -File` with
`pwsh -NoProfile -File`. See [Shell strategy](docs/shell-strategy.md) for the
current shell policy.

## What Adoption Creates

In the runtime layer, the installer writes skills, the knowledge hub, and an
`install-manifest.json`. The manifest can contain local absolute paths and
should not be committed to a project repository.

In a project, bootstrap usually creates or maintains:

- `AGENTS.md`: project-level agent entrypoint and fallback instructions.
- `CLAUDE.md` and `.claude/guardrails/`: Claude Code adoption surface and
  template reliability guardrails.
- `.agents/`: local runtime memory, context indexes, command cards, and lessons.
- `docs/specs/`: optional target-project work packages, task lists, and spec
  templates.

Each project can choose its own project memory language. Commands, paths, APIs,
filenames, code symbols, and raw error text may stay in their original form.

## Layer Model

- Public source: this repository, containing the public-safe kernel, scripts,
  templates, and docs.
- Runtime layer: generated install under `$HOME/.agents` or another target.
- Project local layer: each target project's `.agents/`, plus optional
  `docs/specs/`.
- Private overlay: optional private profiles, skills, knowledge, and migration
  records outside the public repository.

## Profiles

Current public profiles:

- `minimal`: installs the bootstrap skill and public knowledge hub templates.
- `recommended`: installs the Workflow Kernel and public knowledge hub.
- `full`: currently installs the same public content as `recommended`.
- `dev`: currently installs the same public content as `recommended`.

`full` and `dev` are reserved for future installable public domain packs and
developer maintenance tooling. They do not currently enable extra domain-pack
content. See [Domain pack governance](docs/domain-pack-governance.md) for the
lifecycle and profile boundary.

## Examples And Common Paths

- Start from an empty project: [Minimal project adoption walkthrough](docs/walkthroughs/minimal-project-adoption.md)
- Adapt an existing project: [Existing project upgrade path](docs/existing-project-upgrade.md)
- Refresh, migrate, or reset project memory: [Existing project upgrade path](docs/existing-project-upgrade.md#intent-quick-reference)
- Inspect the smallest project layout: [examples/minimal-project](examples/minimal-project/README.md)
- Learn the adaptation model: [How to adapt](docs/how-to-adapt.md)
- Maintain project memory: [Language policy](docs/language-policy.md) and
  [Agent governance](docs/agent-governance.md)

## Documentation

User adoption paths:

- [Architecture](docs/architecture.md)
- [How to adapt](docs/how-to-adapt.md)
- [Existing project upgrade path](docs/existing-project-upgrade.md)
- [Old-release upgrade path](docs/old-release-upgrade-path.md)
- [Minimal project adoption walkthrough](docs/walkthroughs/minimal-project-adoption.md)
- [Language policy](docs/language-policy.md)
- [Claude Code hooks guardrails](docs/claude-code-hooks-guardrails.md)

Maintainer and advanced references:

- [Agent governance](docs/agent-governance.md)
- [Domain pack governance](docs/domain-pack-governance.md)
- [Release process](docs/release-process.md)
- [Release readiness](docs/release-readiness.md)
- [Target-project spec lifecycle](docs/spec-lifecycle.md)
- [Shell strategy](docs/shell-strategy.md)
- [Release notes](docs/releases/README.md)
- [Knowledge catalog](knowledge-hub/knowledge-catalog.md)
- [Examples](examples/README.md)

## Contributing, Feedback, And Safety Boundary

Issues and pull requests are welcome for the public kernel. Keep changes
scoped, reviewable, and validated. Do not commit private overlays, local paths,
private auth material, sensitive audit material, or generated runtime manifests.

This repository carries reusable public-safe kernel content and knowledge.
Private project rules, internal environment assumptions, and experimental skills
belong in project-local memory or a private overlay.

## License

MIT
