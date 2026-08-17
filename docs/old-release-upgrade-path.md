# Old-Release Upgrade Path

This document defines the support matrix for upgrading from older public
releases to the current C3.3 Runtime, and the expected behavior for runtime
install state and existing project workspace state.

New users should follow the
[quick start](release-readiness.md#current-quick-start) or the
[minimal project adoption walkthrough](walkthroughs/minimal-project-adoption.md)
instead. This guide is for users who already have a runtime install from a
previous public release.

## Upgrade Support Matrix

| Source version | Category | Expected upgrade path |
| --- | --- | --- |
| `v0.4.6` | **Supported direct** | Existing project content is compatible with the current runtime refresh. A schema-1 copy runtime whose content differs from the new source requires reviewed `install.ps1 -ReplaceManaged` migration; a default run reports conflict and keeps schema 1. If the project workspace is legacy, use the explicit C3.3 migration flow below. |
| `v0.4.5` | **Supported direct** | Same as `v0.4.6`. Template structure is identical. |
| `v0.4.4` | **Supported direct** | Same as `v0.4.5`. Template structure is identical. |
| `v0.4.3` | **Supported direct** | Same as `v0.4.4`. Template structure is identical. |
| `v0.4.2` | **Supported direct** | First release with language-scoped template model (`templates/languages/`). Existing project memory from this model is forward-compatible. |
| `v0.4.1` | **Best-effort** | Install script works, but templates used the pre-language-scoped layout (historical: flat `templates/` without language prefix). After upgrading the runtime, inspect the workspace and run the explicit C3.3 migration Analyze step for legacy content. |
| `v0.4.0` | **Best-effort** | Similar to `v0.4.1`. The language migration workflow was introduced here but templates were not yet language-scoped. Review migration evidence before applying it. |
| `v0.3.0`, `v0.3.1` | **Best-effort** | Install script exists but project structure differs significantly. Refresh the runtime, inspect the workspace, and use the C3.3 migration authority only after reviewing its Analyze evidence. |
| `v0.1.0`, `v0.2.0` | **Unsupported / manual disposition** | Early releases with substantially different project structure. Back up runtime and project-specific content, refresh the runtime if appropriate, and use `scripts/migrate-project.ps1` only for an explicitly reviewed supported plan. Do not force-reset project content as an automatic upgrade step. |

### Terminology

- **Supported direct**: existing project content is forward-compatible without
  migration. Schema-2 runtimes refresh incrementally. Schema-1 copy manifests
  do not contain a reliable per-file baseline, so any target/source difference
  is a conflict until the user reviews the runtime and explicitly supplies
  `-ReplaceManaged`.
- **Best-effort**: rerun `install.ps1`, review `install-report.json`, and resolve
  any runtime conflicts before continuing. Existing project content may contain
  stale template references or missing fields. Run the C3.3 migration Analyze
  step and review its evidence before applying.
- **Unsupported / manual disposition**: The install script can replace runtime
  files, but the existing project content is too old for an automatic migration
  plan. Back up project-specific content and obtain a human disposition; the
  migration command fails closed for unsupported or ambiguous material.

## Runtime Install Upgrade

### Same-Machine Refresh (Most Common)

Incrementally refresh an existing runtime install on the same machine:

```powershell
# Clone or pull the target release
git checkout v0.7.1  # or the target tag

# Refresh managed files and preserve unknown or locally modified content
pwsh -NoProfile -NonInteractive -File scripts/install.ps1 -Profile recommended
```

For schema-2 manifests, the installer restores missing managed files, updates
files whose source changed while the installed copy remained unchanged, and
does not rewrite unchanged files. Unknown files and locally modified managed
files are preserved. A file changed both locally and in the source is reported
as a conflict and returns non-zero unless `-AllowPartial` is supplied.

Schema-1 copy manifests have no trustworthy installed-content baseline. If a
managed target differs from the new source, the default run returns conflict,
does not overwrite the target, and leaves the schema-1 manifest in place.
`-AllowPartial` still leaves that migration incomplete. After reviewing or
backing up local runtime changes, rerun with `-ReplaceManaged` to overwrite only
managed content, preserve unknown files, and complete schema-2 migration.

### Copy Mode Install

To install into a separate directory (for testing or isolation):

```powershell
pwsh -NoProfile -NonInteractive -File scripts/install.ps1 -Profile recommended -TargetDir <path>
```

Copy mode is the default and creates independent file copies without junctions
or symbolic links. The existing `-Copy` switch remains compatible.

### Explicit Development Link Install

Contributors can explicitly opt into source-linked runtime items:

```powershell
pwsh -NoProfile -NonInteractive -File scripts/install.ps1 -Profile recommended -TargetDir <dev-runtime> -DevLink
```

This creates `Junction` items on Windows and `SymbolicLink` items on other
platforms. Link creation failure is an error; the explicit development request
does not silently fall back to copy mode.

### Manifest After Upgrade

After a successful migration, schema-2 `install-manifest.json` records the
profile, actual strategy, runtime-relative managed items, and content hashes
that match the installed files. Schema-1
`install-report.json` records the current run's status and file lists. Verify
both artifacts:

```powershell
Get-Content ~/.agents/install-manifest.json | ConvertFrom-Json
Get-Content ~/.agents/install-report.json | ConvertFrom-Json
```

`-Force` remains accepted only as a deprecated compatibility alias for
`-ReplaceManaged`; it no longer deletes the whole runtime before reinstalling.

## Project Workspace Migration

After upgrading the runtime, inspect the existing project before choosing a
refresh or legacy migration. Current C3.3 authority is `project-workspace` for
read-only workspace checks and discovery, and the Runtime-level
`scripts/migrate-project.ps1` for legacy migration. The top-level Project
status from `scripts/status.ps1` follows the `project.workspace` authority and
does not consult retired memory helpers.

### Supported Direct Sources (v0.4.2+)

For projects created with `v0.4.2` or later, the project structure is normally
forward-compatible. Run these checks after upgrading:

```powershell
# 1. Read-only status
pwsh -NoProfile -NonInteractive -File <runtime>/scripts/status.ps1 -RuntimeDir <runtime> -ProjectDir <project> -Json

# 2. Read-only workspace contract check
pwsh -NoProfile -NonInteractive -File <runtime>/skills/project-workspace/scripts/check-project-workspace.ps1 -ProjectRoot <project> -Json

# 3. Progressive canonical asset discovery
pwsh -NoProfile -NonInteractive -File <runtime>/skills/project-workspace/scripts/discover-project-assets.ps1 -ProjectRoot <project> -Query <query> -Json
```

If the workspace check is current and discovery finds the expected canonical
assets, no legacy migration is needed. A durable work package belongs in a
project-local Spec created with `project-workspace create-spec`.

### Best-Effort Sources (v0.3.x–v0.4.1)

For projects from older releases, inspect first and run the explicit migration
flow only when Analyze identifies a supported legacy plan:

```powershell
# 1. Analyze (strictly read-only)
pwsh -NoProfile -NonInteractive -File <runtime>/scripts/migrate-project.ps1 -Mode Analyze -ProjectRoot <project> -Json

# 2. Review the evidence, then apply explicitly
pwsh -NoProfile -NonInteractive -File <runtime>/scripts/migrate-project.ps1 -Mode Apply -ProjectRoot <project> -AnalyzeEvidence <analyze-json> -ConfirmMigration -Json

# 3. Validate the resulting workspace
pwsh -NoProfile -NonInteractive -File <runtime>/skills/project-workspace/scripts/check-project-workspace.ps1 -ProjectRoot <project> -Json
pwsh -NoProfile -NonInteractive -File <runtime>/skills/project-workspace/scripts/discover-project-assets.ps1 -ProjectRoot <project> -Query <query> -Json
```

See [Existing Project Upgrade Path](existing-project-upgrade.md) for the
full conservative upgrade flow and local memory preservation rules.

### Unsupported Sources (v0.1.0, v0.2.0)

For projects from early releases:

1. Back up any project-specific `.agents/` content (process.txt, plan.md,
   notes.md, context entries, local specs).
2. Obtain a human disposition and run the migration authority only with an
   explicitly supported Analyze result. Do not use a retired Skill or an
   implicit bootstrap reset as a migration substitute.

   ```powershell
   pwsh -NoProfile -NonInteractive -File <runtime>/scripts/migrate-project.ps1 -Mode Analyze -ProjectRoot <project> -Json
   ```

3. Restore project-specific content from backup.
4. Validate with `project-workspace` check/discover. If the migration is
   applied, rollback is guarded by the unchanged-project check:

   ```powershell
   pwsh -NoProfile -NonInteractive -File <runtime>/scripts/migrate-project.ps1 -Mode Rollback -ProjectRoot <project> -BackupId <backup-id> -ConfirmRollback -Json
   ```

### Fresh-Machine Install

A fresh-machine install has no existing runtime or project memory. Use the
standard quick start:

```powershell
pwsh -NoProfile -NonInteractive -File scripts/install.ps1 -Profile recommended
```

Then bootstrap any project:

```powershell
pwsh -NoProfile -NonInteractive -File ~/.agents/skills/project-bootstrap/scripts/bootstrap_project.ps1 -ProjectDir <project> -ProjectLanguage en
```

No upgrade or migration steps are needed for fresh installs. The active Runtime
authority is `project-bootstrap` + `project-workspace`.

## Rehearsal Evidence

The `v0.7.0` → `v0.7.1` upgrade path was rehearsed for that release.
Earlier rehearsals remain in
[Old-Release Rehearsal Evidence](old-release-rehearsal-evidence.md) as retained
historical evidence; they are not deleted or rewritten. The rehearsal covers the
ordinary schema-2 copy upgrade, managed and locally modified content protection,
project-state and conservative-refresh boundaries, deterministic context metadata
matching, and the explicit skill bridge. Its old helper references are historical
evidence, not current C3.3 Runtime authority. A publish-finalization branch SHA
is provisional review evidence, not the final tag target. The final tag target is
determined only after the authorized merge.

## Release Process Implications

Starting with `v0.5.0`, a release that changes the install contract, template
structure, project workspace schema, hub lock format, or install profiles
requires at least one old-release upgrade rehearsal before tagging. This
rehearsal:

- Exercises the most recent supported-direct tag against the target release.
- Validates both runtime install upgrade and project workspace migration.
- Records results as public-safe evidence in this repository.
- Is a manual checklist today; scripted automation is a future enhancement.

Patch or docs-only releases that do not change the above surfaces may skip
the rehearsal if the maintainer records the deferral. A documentation PR still
uses affected `iteration` / `pre-push` validation; the full Release validator is
not an ordinary PR requirement.

See [Release Process](release-process.md#old-release-upgrade-rehearsal) for
the rehearsal requirement.

## Non-Goals

- This document does not define an online auto-updater.
- It does not promise indefinite support for every historical tag.
- It does not change install profile behavior.
- It does not cover private overlay or local migration state.
