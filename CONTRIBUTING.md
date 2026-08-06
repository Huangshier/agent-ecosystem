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
pwsh -NoProfile -NonInteractive -File .\scripts\install.ps1 -Profile recommended -TargetDir <temp-runtime> -Copy -Force
```

The C3.3 validation control plane and normative repository validation
entrypoints require PowerShell Core 7.6 or later through
`pwsh -NoProfile -NonInteractive -File`.

Slice A0 does not change the current v0.7.1 Runtime, installer, bootstrap,
bridge, or legacy Skill execution contracts. Those surfaces remain
transitional and will be migrated or retired only in their designated later
slices. This transition is not a commitment to long-lived dual-host or
dual-semantics support.

For PowerShell changes, parse scripts before committing:

```powershell
Get-ChildItem -Recurse -File -Include *.ps1 scripts,skills,knowledge-hub |
  ForEach-Object {
    $text = Get-Content -LiteralPath $_.FullName -Raw
    [scriptblock]::Create($text) | Out-Null
  }
```

For README, docs entrypoint, release notes, or release process changes, also
run the lightweight [Public Reader Review](docs/release-process.md#public-reader-review)
check before opening a pull request.
