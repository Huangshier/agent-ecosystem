# Minimal Project Adoption Walkthrough

This walkthrough starts from an empty project and adopts the public Agent
Ecosystem Workflow Kernel. It is meant for evaluation and first use. It does
not require a private overlay, GitHub App setup, domain packs, or custom skills.

Agent Ecosystem is not an agent runtime. It gives a project a small workflow
surface that an agent can follow: project memory, context loading, durable work
specs, memory cleanup, and reusable public knowledge.

## Prerequisites

- A local checkout of this repository, referred to as `<repo>`.
- An empty project directory, referred to as `<project>`.
- A runtime target directory, referred to as `<runtime>`.
- PowerShell.

On Windows, the examples use Windows PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <script> <arguments>
```

On Linux, macOS, or Windows systems that already use PowerShell 7+, replace the
launcher with:

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
powershell -NoProfile -ExecutionPolicy Bypass -File <repo>\scripts\install.ps1 -Profile recommended -TargetDir <runtime>
```

The `recommended` profile installs the public Workflow Kernel skills and public
knowledge hub.

Expected result:

- `<runtime>\skills\project-bootstrap`
- `<runtime>\skills\project-context-gate`
- `<runtime>\skills\workflow-spec-lite`
- `<runtime>\skills\memory-governance`
- `<runtime>\knowledge-hub`
- `<runtime>\install-manifest.json`
- `<runtime>\install-report.json`

## 2. Bootstrap The Empty Project

Create the project memory scaffold:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <runtime>\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -ProjectLanguage en
```

Use `-ProjectLanguage zh-CN` instead when the project memory should be written
in Simplified Chinese. The bootstrap script does not infer chat language by
itself.

Expected project files:

```text
<project>/
  AGENTS.md
  .agents/
    AGENTS.md
    process.txt
    plan.md
    notes.md
    context/
  docs/
    specs/
      README.md
      _templates/
        spec-lite.md
        tasks-lite.md
```

At this point, `AGENTS.md` is the project entrypoint, `.agents/AGENTS.md` holds
project working rules, `.agents/process.txt` and `.agents/plan.md` hold current
session state, and `docs/specs/` is ready for durable work packages.

## 3. Run The Context Gate

Before non-trivial work, load the project rules and hot memory:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <runtime>\skills\project-context-gate\scripts\context_gate.ps1 -ProjectRoot <project>
```

For automation or compact inspection, request JSON:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <runtime>\skills\project-context-gate\scripts\context_gate.ps1 -ProjectRoot <project> -Json
```

For a copyable agent brief, request the compact brief output:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <runtime>\skills\project-context-gate\scripts\context_gate.ps1 -ProjectRoot <project> -Brief
```

The context gate should show the project root, git state, hot memory files,
active work package files, and discovered context files. In an agent session,
the agent should turn that output into a short constraint capsule before
editing. Use `-Json` for automation contracts and `-Brief` for a human/agent
handoff surface.

## 4. Create A First Spec-Lite Work Package

For a first real task, ask the agent to use `workflow-spec-lite` before editing.
For example:

```text
Use workflow-spec-lite for this project. Add a short CONTRIBUTING note that
explains how maintainers should record validation evidence for documentation
changes.
```

For a bounded task, the agent should choose a quick or standard route. For a
multi-step task, it should create:

```text
<project>/
  docs/
    specs/
      <slug>/
        spec.md
        tasks.md
```

A useful first spec records:

- the goal;
- non-goals;
- files likely to change;
- validation commands;
- risks and rollback notes;
- the stop rule for scope drift or skipped acceptance checks.

If you are working manually without an agent runtime, copy the templates from
`<project>\docs\specs\_templates\` and fill the same sections before editing.

## 5. Keep Project Memory Small

After one or two tasks, check whether `.agents` files are staying concise:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <runtime>\skills\memory-governance\scripts\memory_diagnose.ps1 -ProjectRoot <project>
```

Use `memory-governance` when:

- `.agents/process.txt` has old session history;
- `.agents/plan.md` duplicates a full spec;
- `.agents/notes.md` contains temporary narration instead of stable facts;
- a reusable lesson belongs in `.agents/context/experience/`.

Keep the durable task definition in `docs/specs/<slug>/`. Keep `.agents` as the
current working memory and routing layer.

## 6. Route Knowledge Through The Hub

The public knowledge hub is a starting catalog, not a private memory dump.

Start with:

```text
<runtime>\knowledge-hub\knowledge-catalog.md
```

For reusable workflow lessons, use the public search script:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <runtime>\knowledge-hub\scripts\search_experience.ps1 -HubDir <runtime>\knowledge-hub -Query "PowerShell command chaining"
```

When a lesson is project-specific, keep it under:

```text
<project>\.agents\context\experience\
```

Promote a lesson into the public knowledge hub only after it is reviewed,
public-safe, and reusable outside the current project.

## 7. Validate The Adopted Workflow

For a first adoption smoke check, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <runtime>\skills\project-context-gate\scripts\context_gate.ps1 -ProjectRoot <project>
powershell -NoProfile -ExecutionPolicy Bypass -File <runtime>\skills\memory-governance\scripts\memory_diagnose.ps1 -ProjectRoot <project>
```

If you are changing this public repository itself, use the full release gate:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <repo>\scripts\validate-release.ps1 -ScratchRoot <scratch>
```

For an ordinary adopted project, define validation in that project's own spec.
The Workflow Kernel does not prescribe a universal test suite.

## 8. Clean Up Evaluation Artifacts

If the temporary runtime was only for evaluation, uninstall it with the
manifest-based uninstaller:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <repo>\scripts\uninstall.ps1 -TargetDir <runtime>
```

For schema-2 copy installs, nested unknown or locally modified files inside a
managed destination block the entire uninstall before deletion. Clean copy
items and dev links use the basic manifest removal path, while paths outside
manifest destinations remain untouched. If the manifest is missing, the script
prints manual cleanup guidance instead of deleting files blindly.

Before committing the adopted project, review:

- `.agents/` for current project memory only;
- `docs/specs/` for durable work packages;
- `.gitignore` for generated runtime directories, local logs, and scratch
  output;
- no private overlay content, local migration notes, or machine-specific runtime
  state.

## 9. Next Steps

After the minimal path works:

- keep using `project-context-gate` before non-trivial work;
- use `workflow-spec-lite` when work needs durable scope and acceptance;
- run `memory-governance` periodically to keep `.agents` concise;
- add local project knowledge under `.agents/context/`;
- incubate custom skills outside the public kernel until they are stable and
  public-safe.

The companion [minimal project example](../../examples/minimal-project/README.md)
shows the intended project-local file layout after bootstrap.
