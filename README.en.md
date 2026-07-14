# Agent Ecosystem

English (current) | Simplified Chinese: [README.md](README.md)

> A lightweight Workflow Kernel for agent-assisted software projects.

Current release: `v0.6.0` (latest published release)

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
to read and maintain `.agents/`; it is not a second behavior contract.
`.agents/process.txt` and `.agents/plan.md` hold hot state,
`.agents/context/` holds discoverable knowledge, and target projects may use
`docs/specs/` for durable cross-session work packages.

See [Architecture](docs/architecture.md) and
[Runtime adoption bridge](docs/runtime-adoption-bridge.md) for the complete
boundary.

## 3. First Install

### Five-Minute Start

1. Install the `recommended` profile from the selected release/source
   checkout. Normal installs create independent copies by default and can be
   rerun incrementally:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -Profile recommended
   ```

   For evaluation, start with an isolated directory:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -Profile recommended -TargetDir <temp-runtime>
   ```

   Use `-DevLink` only when a contributor explicitly wants the runtime to
   follow the source checkout. `-Copy` remains a compatible spelling of the
   default copy mode. Use `-ReplaceManaged` only after reviewing conflicts and
   deciding to overwrite managed content.

2. If an agent client needs a dedicated skill directory, create the optional
   bridge explicitly:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\link-agent-skills.ps1 `
     -RuntimeDir <runtime> `
     -AgentSkillsDir <agent-skills-dir> `
     -Skill project-bootstrap,project-context-gate
   ```

   Both directories are mandatory; the helper never guesses a client path.
   See [Agent-specific skill link bridge](docs/agent-skill-bridge.md) for its
   preflight, conflict, and metadata contracts.

3. Bootstrap the target project with an explicit project-memory language:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File <runtime>\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -ProjectLanguage en
   ```

4. Run the context gate before the first non-trivial task:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File <runtime>\skills\project-context-gate\scripts\context_gate.ps1 -ProjectRoot <project>
   ```

On non-Windows systems, or when PowerShell 7+ is already available, replace the
command prefix with `pwsh -NoProfile -File`. See
[Shell strategy](docs/shell-strategy.md).

### Profiles

- `minimal`: installs the bootstrap skill and public knowledge hub templates.
- `recommended`: installs the Workflow Kernel and public knowledge hub.
- `full` and `dev`: currently match `recommended`; they reserve space for
  future public domain packs and maintainer tooling.

See [Domain pack governance](docs/domain-pack-governance.md) for the profile
lifecycle.

## 4. Daily Use

Use the same short path for every non-trivial task:

1. Read root `AGENTS.md`, the project's only complete behavior contract.
2. Run `project-context-gate` to load hot memory, active work packages, and
   relevant context progressively.
3. For work that needs durable goals, non-goals, risks, and acceptance across
   sessions, use `workflow-spec-lite` to create a target-project-local
   `docs/specs/<slug>/spec.md`.
4. Implement the change and run the target project's own validation.
5. At handoff or phase close, use `memory-governance` to compress hot memory and
   route stable facts and lessons to the right place.

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
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -Profile recommended -TargetDir <runtime>
   ```

2. Review `install-report.json`. The default incremental update restores
   missing managed files, updates source-changed files that were not locally
   modified, and preserves unknown and locally modified files. It never
   silently overwrites conflicts.
3. Inspect the runtime and bridge without changing them:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\status.ps1 -RuntimeDir <runtime>
   ```

4. Use `-ReplaceManaged` only after reviewing conflicts. Rerun the bridge helper
   with its existing explicit arguments only when bridge preflight still passes.

For upgrades from an older version, read the
[Old-release upgrade path](docs/old-release-upgrade-path.md) first.

## 6. Inspect And Refresh Existing Projects

Inspect first, then choose conservative refresh, migration, or reset:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\status.ps1 -RuntimeDir <runtime> -ProjectDir <project> -Json
powershell -NoProfile -ExecutionPolicy Bypass -File <runtime>\skills\project-context-gate\scripts\context_gate.ps1 -ProjectRoot <project>
```

- `current`: the checked project baseline and engineering memory need no
  refresh.
- `optional-refresh`: the template baseline drifted or scaffold files are
  missing. Default bootstrap preserves project-specific content;
  `-RefreshUnmodifiedTemplates` updates only files that still match old
  templates.
- `migration-required`: run `memory_upgrade.ps1 -Mode Analyze`, then use the
  reviewable, backup-first Plan → Apply → Validate flow.
- `unknown`: a helper, lock, language, or metadata source could not be trusted.
  Inspect it manually instead of guessing or forcing an overwrite.

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
| Project | `optional-refresh` | Use conservative refresh and preserve project-specific content. |
| Project | `migration-required` | Follow Analyze → Plan → backup → Apply → Validate. |
| Project | `unknown` | Inspect helper availability, the hub lock, project language, and diagnostic output; remain fail-soft. |

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
