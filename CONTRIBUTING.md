# Contributing

Thanks for helping improve Agent Ecosystem.

## Scope

The current public Runtime is the C3.3 Workflow Kernel:

- `project-bootstrap`
- `project-workspace`

`project-context-gate`, `workflow-spec-lite`, and `memory-governance` are retired
from C3.3 Runtime authority. They may remain in historical records or negative
validation fixtures, but current public profiles do not install them and current
project guidance must not route fresh work through them.

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
`pwsh -NoProfile -NonInteractive -File`. Fresh projects use
`project-bootstrap` and `project-workspace`; an existing legacy project uses
`scripts/migrate-project.ps1` through its explicit Analyze -> Apply -> guarded
Rollback flow.

Routine pull requests validate the affected diff through the classifier-selected
`iteration` and `pre-push` paths. The thin main-push health check and the full
Release/checkpoint validator are separate boundaries; do not run the complete
Release validator for an ordinary documentation pull request unless a
Release/checkpoint decision explicitly requires it.

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
