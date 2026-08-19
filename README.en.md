# Agent Ecosystem

English (current) | Simplified Chinese: [README.md](README.md)

> A lightweight Workflow Kernel for agent-assisted software projects.

Current release: `v0.8.0` (latest published release)

This README describes `main`. When using a published version, follow the README
and Release Notes from the corresponding tag.

## 1. What Problem Does This Project Solve?

### One-Line Summary

Agent Ecosystem provides a small, installable, validated, and extensible base
workflow that helps coding agents load project rules, restore context, capture
the intent of complex work, and keep project memory and reusable lessons at the
right layer.

It is for maintainers and teams that want to:

- help Codex, Claude Code, or another agent load the right project constraints
  before work starts;
- preserve state, scope, and acceptance evidence across sessions with hot
  memory and optional work packages;
- install, inspect, and update a shared runtime safely while preserving
  project-specific content;
- separate project lessons from reusable cross-project knowledge.

It is not an agent runtime, model orchestration framework, or task scheduler,
and it does not require every project to copy one process unchanged. This
public repository contains only the public-safe workflow kernel. Private
overlays, credentials, local migration records, sensitive audit material, and
generated runtime metadata belong outside it.

## 2. Release → Runtime → Agent Bridge → Project

### Layer Model

```text
Release → installed Runtime → optional Agent bridge → Project
```

- **Release**: a versioned, reviewable public source. Choose a release or an
  explicit source revision before installing; see the
  [Release notes](docs/releases/README.md).
- **Runtime**: an independent workflow copy installed under `$HOME/.agents` or
  another target, including skills, the knowledge hub,
  `install-manifest.json`, and `install-report.json`.
- **Agent bridge**: an optional, explicit discovery layer that links selected
  skills from the installed runtime into a verified agent-client skill
  directory. A normal install never creates it automatically.
- **Project**: the target project's own behavior contract, engineering memory,
  and optional work packages. They belong to the target project, not the
  runtime or this repository.

At the project layer, root `AGENTS.md` is the only complete project behavior
contract. `.agents/AGENTS.md` is an engineering-memory guide that explains how
to read and maintain `.agents/`; it is not a second behavior contract. The
canonical workspace assets are Work, Context, Procedure, and Spec;
`project-workspace` handles discover, check, continuity, and create-spec.
`.agents/process.txt`, `.agents/plan.md`, and `.agents/notes.md` are retired
paths after the C3.3 hot-memory convergence, not the current canonical
hot-state authority; `.agents/context/` holds discoverable knowledge, and
target projects may use `docs/specs/` for durable cross-session work packages.

See [Architecture](docs/architecture.md) and
[Runtime adoption bridge](docs/runtime-adoption-bridge.md) for the complete
boundary.

## 3. First Install

### Five-Minute Start

1. Install the `recommended` profile from the selected release/source
   checkout. Normal installs create independent copies by default and can be
   rerun incrementally:

   ```powershell
   pwsh -NoProfile -File .\scripts\install.ps1 -Profile recommended
   ```

   For evaluation, start with an isolated directory:

   ```powershell
   pwsh -NoProfile -File .\scripts\install.ps1 -Profile recommended -TargetDir <temp-runtime>
   ```

   Use `-DevLink` only when a contributor explicitly wants the runtime to
   follow the source checkout. `-Copy` remains a compatible spelling of the
   default copy mode. Use `-ReplaceManaged` only after reviewing conflicts and
   deciding to overwrite managed content.

2. If an agent client needs a dedicated skill directory, create the optional
   bridge explicitly:

   ```powershell
   pwsh -NoProfile -File .\scripts\link-agent-skills.ps1 `
     -RuntimeDir <runtime> `
     -AgentSkillsDir <agent-skills-dir> `
     -Skill project-bootstrap,project-workspace
   ```

   Both directories are mandatory; the helper never guesses a client path.
   See [Agent-specific skill link bridge](docs/agent-skill-bridge.md) for its
   preflight, conflict, and metadata contracts.

3. Bootstrap the target project with an explicit project-memory language:

   ```powershell
   pwsh -NoProfile -File <runtime>\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -ProjectLanguage en
   ```

4. Before the first non-trivial task, discover or check project assets with
   `project-workspace`:

   ```powershell
   pwsh -NoProfile -File <runtime>\skills\project-workspace\scripts\check-project-workspace.ps1 -ProjectRoot <project> -Json
   pwsh -NoProfile -File <runtime>\skills\project-workspace\scripts\discover-project-assets.ps1 -ProjectRoot <project> -Query <query> -Json
   ```

C3.3 entrypoints use `pwsh -NoProfile -File` (PowerShell 7.6+). See
[Shell strategy](docs/shell-strategy.md).

### Profiles

- `minimal`: installs the bootstrap skill and public knowledge hub templates; a
  fresh bootstrap produces a minimal C3.3 workspace.
- `recommended`: installs the active C3.3 Runtime (`project-bootstrap` +
  `project-workspace`), project workspace templates/schemas, and the public
  knowledge hub.
- `full` and `dev`: currently match `recommended`; they reserve space for future
  public domain packs and maintainer tooling.

`recommended` / `full` / `dev` are the only C3.3 Runtime authority after the
cutover; there is no `c3-3-candidate` profile and no compatibility alias.

See [Domain pack governance](docs/domain-pack-governance.md) for the profile
lifecycle.

## 4. Daily Use

Use the same short path for every non-trivial task:

1. Read root `AGENTS.md`, the project's only complete behavior contract.
2. Use `project-workspace` `discover` / `check` to progressively find Work,
   Context, Procedure, and Spec assets.
3. For work that needs durable goals, non-goals, risks, and acceptance across
   sessions, use `project-workspace create-spec` to create a
   target-project-local `docs/specs/<slug>/spec.md`.
4. Implement the change and run the target project's own validation.
5. At handoff or phase close, use the `project-workspace` Work/Context
   continuity operations to record unfinished work and stable facts.

Follow the [Minimal project adoption walkthrough](docs/walkthroughs/minimal-project-adoption.md)
for a complete empty-project example, and see [How to adapt](docs/how-to-adapt.md)
for adaptation principles.

## 5. Update The Runtime

Updating the runtime and refreshing a project are separate actions. A runtime
update never rewrites project memory automatically and never creates or repairs
an Agent bridge automatically.

1. Obtain the target release/source revision and rerun the installer from that
   checkout:

   ```powershell
   pwsh -NoProfile -File .\scripts\install.ps1 -Profile recommended -TargetDir <runtime>
   ```

2. Review `install-report.json`. The default incremental update restores
   missing managed files, updates source-changed files that were not locally
   modified, and preserves unknown and locally modified files. It never
   silently overwrites conflicts.
3. Inspect the runtime and bridge without changing them:

   ```powershell
   pwsh -NoProfile -File <runtime>\scripts\status.ps1 -RuntimeDir <runtime>
   ```

4. Use `-ReplaceManaged` only after reviewing conflicts. Rerun the bridge helper
   with its existing explicit arguments only when bridge preflight still passes.

For upgrades from an older version, read the
[Old-release upgrade path](docs/old-release-upgrade-path.md) first.

## 6. Inspect And Refresh Existing Projects

Inspect first, then choose conservative refresh, migration, or reset:

```powershell
pwsh -NoProfile -File <runtime>\scripts\status.ps1 -RuntimeDir <runtime> -ProjectDir <project> -Json
pwsh -NoProfile -File <runtime>\skills\project-workspace\scripts\check-project-workspace.ps1 -ProjectRoot <project> -Json
```

- `current`: the current C3.3 workspace is active-ready; no migration is needed.
- `migration-required`: the workspace is identified as legacy / not-c3-3. Run
  `scripts/migrate-project.ps1 -Mode Analyze` (read-only), review the evidence,
  then explicitly `Apply`, and use the guarded `Rollback` if needed; do not use
  retired memory helpers as the migration authority.
- `unknown`: the workspace could not be trusted (incomplete / malformed /
  unverifiable). Inspect it manually instead of guessing or forcing an overwrite.

Scaffold / template refresh is a separate conservative capability of
`project-bootstrap` for restoring missing or drifted scaffold files; it
preserves project-specific content by default, and `-RefreshUnmodifiedTemplates`
updates only files that still match old templates. It is not a legacy migration
path and is not bound to the active C3.3 top-level Project status.

A current C3.3 workspace needs no migration. A legacy workspace enters the
`scripts/migrate-project.ps1` Analyze → explicit Apply → guarded Rollback flow;
malformed, unavailable, or unverifiable states stay fail-closed.

By default, “refresh” means preserving project-specific content. Use the
backup-first `-ForceResetScaffold` path only when the caller explicitly allows
old scaffold customizations to be discarded. See the complete decision table
and commands in the
[Existing project upgrade path](docs/existing-project-upgrade.md#intent-quick-reference).

## 7. Common Statuses And Troubleshooting

`scripts/status.ps1` is a read-only aggregator. It never accesses the network,
installs, refreshes, repairs, or deletes content.

| Area | Common status | Next step |
| --- | --- | --- |
| Runtime managed files | `current` | No action is required. |
| Runtime managed files | `modified` / `missing` / `conflict` | Review managed problems and `install-report.json` before reinstalling. |
| Runtime provenance | `not-recorded` / `unknown` | This does not mean the runtime is broken; source archives may have no Git provenance. |
| Agent bridge | `not-configured` | This only means this runtime has no bridge manifest; configure one explicitly if client discovery is needed. |
| Agent bridge | `stale` / `broken` / `conflict` / `unknown` | Inspect the managed source, target link, and occupying content using the bridge guide; status does not repair it. |
| Project | `current` | The current C3.3 workspace is active-ready; no migration is needed. |
| Project | `migration-required` | Follow `migrate-project.ps1` Analyze → explicit Apply → guarded Rollback; do not use retired memory helpers. |
| Project | `unknown` | Inspect workspace readiness, the hub lock, project language, and diagnostic output; remain fail-closed. |

Add `-Json` for structured output. See [Scripts](scripts/README.md) for exact
status fields, [Agent-specific skill link bridge](docs/agent-skill-bridge.md)
for bridge failures, and
[Existing project upgrade path](docs/existing-project-upgrade.md) for project
migration failures.

## 8. Architecture And Maintainer Documentation

### Examples And Common Paths

- Start from an empty project:
  [Minimal project adoption walkthrough](docs/walkthroughs/minimal-project-adoption.md)
- Adapt an existing project: [How to adapt](docs/how-to-adapt.md)
- Inspect the smallest layout: [Examples](examples/README.md) and
  [examples/minimal-project](examples/minimal-project/README.md)
- Maintain project memory: [Language policy](docs/language-policy.md) and
  [Agent governance](docs/agent-governance.md)
- Understand target-project work packages:
  [Target-project spec lifecycle](docs/spec-lifecycle.md)

Advanced architecture:

- [Architecture](docs/architecture.md)
- [Runtime adoption bridge](docs/runtime-adoption-bridge.md)
- [Agent-specific skill link bridge](docs/agent-skill-bridge.md)
- [Knowledge catalog](knowledge-hub/knowledge-catalog.md)
- [Claude Code hooks guardrails](docs/claude-code-hooks-guardrails.md)

Maintainer entrypoints:

- [Release notes](docs/releases/README.md)
- [Release process](docs/release-process.md)
- [Release readiness](docs/release-readiness.md)
- [Domain pack governance](docs/domain-pack-governance.md)
- [Shell strategy](docs/shell-strategy.md)

Issues and pull requests should remain scoped, validated, and public-safe. Do
not commit private overlays, local paths, credentials, sensitive audit
material, or generated runtime metadata.

## License

MIT
