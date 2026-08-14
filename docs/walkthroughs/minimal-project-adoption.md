# Minimal Project Adoption Walkthrough

This walkthrough starts from an empty project and adopts the public Agent
Ecosystem Workflow Kernel. It is meant for evaluation and first use. It does
not require a private overlay, GitHub App setup, domain packs, or custom skills.

Agent Ecosystem is not an agent runtime. It gives a project a small workflow
surface that an agent can follow: a canonical C3.3 workspace, asset discovery,
durable specs, work continuity, and reusable public knowledge.

## Prerequisites

- A local checkout of this repository, referred to as `<repo>`.
- An empty project directory, referred to as `<project>`.
- A runtime target directory, referred to as `<runtime>`.
- PowerShell.

C3.3 entrypoints use `pwsh -NoProfile -File` (PowerShell 7.6+):

```powershell
pwsh -NoProfile -File <script> <arguments>
```

Keep generated runtime directories, manifests, and reports out of your project
repository. They are runtime metadata even though their recorded file paths are
runtime-relative.

## 1. Install A Temporary Runtime

Start with the default copy runtime so evaluation does not alter your normal
agent home or point back to the source checkout:

```powershell
pwsh -NoProfile -File <repo>\scripts\install.ps1 -Profile recommended -TargetDir <runtime>
```

The `recommended` profile installs the active C3.3 Runtime: the
`project-bootstrap` and `project-workspace` Skills, the project workspace
templates and schemas, and the public knowledge hub.

Expected result:

- `<runtime>\skills\project-bootstrap`
- `<runtime>\skills\project-workspace`
- `<runtime>\templates\project`
- `<runtime>\schemas\project-workspace`
- `<runtime>\knowledge-hub`
- `<runtime>\install-manifest.json`
- `<runtime>\install-report.json`

## 2. Bootstrap The Empty Project

Create the canonical C3.3 workspace:

```powershell
pwsh -NoProfile -File <runtime>\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -ProjectLanguage en
```

Use `-ProjectLanguage zh-CN` instead when the project memory should be written
in Simplified Chinese. The bootstrap script does not infer chat language by
itself.

Expected project files:

```text
<project>/
  AGENTS.md
  .agents/
    README.md
    .gitignore
    work/
    context/
    procedures/
    skills/
  docs/
    specs/
```

Bootstrap creates this layout only; it does not create placeholder Work,
Context, Procedure, Spec, glossary, or promoted Skill content. `AGENTS.md` is
the project entrypoint, `.agents/README.md` explains the project-local
workspace surface, and the four canonical durable asset types are Work,
Context, Procedure, and Spec.

## 3. Discover And Check Project Assets

Before non-trivial work, read root `AGENTS.md`, then use `project-workspace` to
inspect the workspace without writing:

```powershell
pwsh -NoProfile -File <runtime>\skills\project-workspace\scripts\check-project-workspace.ps1 -ProjectRoot <project> -Json
pwsh -NoProfile -File <runtime>\skills\project-workspace\scripts\discover-project-assets.ps1 -ProjectRoot <project> -Query <query> -Json
```

`check` is strictly read-only. `discover` reads canonical Markdown metadata and
may maintain only the disposable `.agents/.cache/catalog.json` cache. Canonical
Markdown remains the content authority.

## 4. Create A First Spec

For work that needs durable goals, non-goals, risks, and acceptance across
sessions, use `project-workspace create-spec`:

```powershell
pwsh -NoProfile -File <runtime>\skills\project-workspace\scripts\project-workspace.ps1 -Operation create-spec -ProjectRoot <project> -Id <spec-id> -Title <title> -Summary <summary> -Json
```

A useful first spec records:

- the goal;
- non-goals;
- files likely to change;
- validation commands;
- risks and rollback notes;
- the stop rule for scope drift or skipped acceptance checks.

For a multi-session task, use the Work continuity operations (`create-work`,
`checkpoint`, `set-status`, `complete`) to record unfinished work instead of
leaving it in hot memory.

## 5. Record Work Continuity

Use the `project-workspace` Work/Context continuity operations to keep the
workspace current at handoff or phase close:

```powershell
pwsh -NoProfile -File <runtime>\skills\project-workspace\scripts\project-workspace.ps1 -Operation create-work -ProjectRoot <project> -Id <work-id> -Title <title> -Summary <summary> -Next <next-step> -ContinuityReason unfinished -Json
pwsh -NoProfile -File <runtime>\skills\project-workspace\scripts\project-workspace.ps1 -Operation checkpoint -ProjectRoot <project> -Id <work-id> -BaseRevision <sha256:...> -Summary <snapshot> -Json
```

Every update or deletion requires the current `BaseRevision`. A stale request
fails closed with a revision conflict and never merges or overwrites.

## 6. Route Knowledge Through The Hub

The public knowledge hub is a starting catalog, not a private memory dump.

Start with:

```text
<runtime>\knowledge-hub\knowledge-catalog.md
```

For reusable workflow lessons, use the public search script:

```powershell
pwsh -NoProfile -File <runtime>\knowledge-hub\scripts\search_experience.ps1 -HubDir <runtime>\knowledge-hub -Query "PowerShell command chaining"
```

When a lesson is project-specific, keep it under:

```text
<project>\.agents\context\
```

Promote a lesson into the public knowledge hub only after it is reviewed,
public-safe, and reusable outside the current project.

## 7. Validate The Adopted Workflow

For a first adoption smoke check, run:

```powershell
pwsh -NoProfile -File <runtime>\skills\project-workspace\scripts\check-project-workspace.ps1 -ProjectRoot <project> -Json
pwsh -NoProfile -File <runtime>\scripts\status.ps1 -RuntimeDir <runtime> -ProjectDir <project> -Json
```

If you are changing this public repository itself, use the full release gate:

```powershell
pwsh -NoProfile -File <repo>\scripts\validate-release.ps1 -ScratchRoot <scratch>
```

For an ordinary adopted project, define validation in that project's own spec.
The Workflow Kernel does not prescribe a universal test suite.

## 8. Clean Up Evaluation Artifacts

If the temporary runtime was only for evaluation, uninstall it with the
manifest-based uninstaller:

```powershell
pwsh -NoProfile -File <repo>\scripts\uninstall.ps1 -TargetDir <runtime>
```

For schema-2 copy installs, nested unknown or locally modified files inside a
managed destination block the entire uninstall before deletion. Clean copy
items and dev links use the basic manifest removal path, while paths outside
manifest destinations remain untouched. If the manifest is missing, the script
prints manual cleanup guidance instead of deleting files blindly.

Before committing the adopted project, review:

- `.agents/` for current project workspace state only;
- `docs/specs/` for durable work packages;
- `.gitignore` for generated runtime directories, local logs, and scratch
  output;
- no private overlay content, local migration notes, or machine-specific runtime
  state.

## 9. Next Steps

After the minimal path works:

- keep using `project-workspace` `discover` / `check` before non-trivial work;
- use `project-workspace create-spec` when work needs durable scope and
  acceptance;
- record unfinished work with the Work continuity operations;
- add local project knowledge under `.agents/context/`;
- incubate custom skills outside the public kernel until they are stable and
  public-safe.

The companion [minimal project example](../../examples/minimal-project/README.md)
shows the intended project-local file layout after bootstrap.
