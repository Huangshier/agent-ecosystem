# How To Adapt Agent Ecosystem

This guide shows how to use the public Workflow Kernel in another project
without copying this repository's private workflow.

## 1. Install A Runtime

Install the recommended public runtime:

```powershell
.\scripts\install.ps1 -Profile recommended
```

For evaluation, use a temporary runtime first:

```powershell
.\scripts\install.ps1 -Profile recommended -TargetDir <temp-runtime> -Copy -Force
```

## 2. Bootstrap A Project

Run `project-bootstrap` from the installed runtime:

```powershell
pwsh -NoProfile -File <runtime>\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project>
```

Set project memory language explicitly during the first non-trivial memory
write when the agent or workflow knows the user's primary language:

```powershell
pwsh -NoProfile -File <runtime>\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -ProjectLanguage en
pwsh -NoProfile -File <runtime>\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -ProjectLanguage zh-CN
```

The script does not infer chat language by itself.

## 3. Use The Workflow Kernel

- Start non-trivial work with `project-context-gate`.
- Use `workflow-spec-lite` for work that needs durable goals, non-goals,
  acceptance evidence, risks, or multi-phase execution.
- Use `memory-governance` to keep `.agents` files small and route durable
  lessons into `.agents/context/`.
- Use the public `knowledge-hub/knowledge-catalog.md` before opening individual
  reusable knowledge entries.

## 4. Keep Layers Separate

- Public source: reusable kernel and public-safe knowledge.
- Runtime: generated install under `$HOME/.agents` or another target.
- Project local: `.agents/` and `docs/specs/` inside the target project.
- Private overlay: optional private profiles, skills, and knowledge outside this
  public repository.

Do not copy the public tree into a private overlay. Add only private increments.

## 5. Validate Your Setup

Recommended checks:

```powershell
pwsh -NoProfile -File <runtime>\skills\project-context-gate\scripts\context_gate.ps1 -ProjectRoot <project>
pwsh -NoProfile -File <runtime>\skills\memory-governance\scripts\memory_diagnose.ps1 -ProjectRoot <project>
```

For release-quality changes to this public repository, run:

```powershell
.\scripts\validate-release.ps1 -ScratchRoot <scratch-root>
```

## Example

See [examples/minimal-project](../examples/minimal-project/README.md) for a
small project-local scaffold that shows the intended file layout.
