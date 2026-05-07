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
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1 -Profile recommended -TargetDir <temp-runtime> -Copy -Force
```

For PowerShell changes, parse scripts before committing:

```powershell
Get-ChildItem -Recurse -File -Include *.ps1 scripts,skills,knowledge-hub |
  ForEach-Object {
    $text = Get-Content -LiteralPath $_.FullName -Raw
    [scriptblock]::Create($text) | Out-Null
  }
```
