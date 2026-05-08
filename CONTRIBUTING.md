# Contributing

Thanks for helping improve Agent Ecosystem.

## Scope

The first public release is focused on the Workflow Kernel:

- `project-bootstrap`
- `project-context-gate`
- `workflow-spec-lite`
- `memory-governance`

Domain-specific skills and private overlays are intentionally out of scope until
the public kernel and installer are stable.

No contributor license agreement is required for this project. By contributing,
you agree that your contribution can be distributed under the repository's MIT
license.

## Public-Safe Contributions

Before opening a change, make sure the public tree does not include:

- local machine paths
- private repository mappings
- credentials, tokens, cookies, keys, or account identifiers
- private audit notes or migration findings
- domain-specific sample names or private operational details

## Validation

Recommended checks before proposing a change:

```powershell
git diff --check
pwsh -NoProfile -File .\scripts\install.ps1 -Profile recommended -TargetDir <temp-runtime> -Copy -Force
```

Use PowerShell 7+ (`pwsh`) for validation commands. Some validation fixtures
include UTF-8 multilingual content.

For PowerShell changes, parse scripts before committing:

```powershell
Get-ChildItem -Recurse -File -Include *.ps1 scripts,skills,knowledge-hub |
  ForEach-Object {
    $text = Get-Content -LiteralPath $_.FullName -Raw
    [scriptblock]::Create($text) | Out-Null
  }
```
