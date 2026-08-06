---
name: project-workspace
description: Discover public-safe project Work, Context, Procedure, and Spec metadata through one deterministic read-oriented entrypoint.
compatibility: Requires PowerShell 7.6 or newer and a local project root.
---

# Project workspace

Use the scripts under `scripts/` as the single public entrypoint for Slice B:

```powershell
pwsh -NoProfile -NonInteractive -File skills/project-workspace/scripts/discover-project-assets.ps1 -ProjectRoot <project-root> -Query <query> -Json
pwsh -NoProfile -NonInteractive -File skills/project-workspace/scripts/check-project-workspace.ps1 -ProjectRoot <project-root> -Json
```

`discover` reads canonical Markdown metadata through the Slice A parser and may
maintain only the disposable `.agents/.cache/catalog.json` cache. `check` is
strictly read-only and never creates or refreshes that cache. Canonical Markdown
remains the content authority; `glossary.yaml` is used only when it is present,
evidence-backed, and valid.

The Slice B surface is dormant. It does not create assets, update Work items,
integrate with bootstrap or runtime defaults, or expose Procedure files as
native Skills.
