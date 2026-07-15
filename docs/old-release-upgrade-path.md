# Old-Release Upgrade Path

This document defines the support matrix for upgrading from older public
releases to the current release, and the expected behavior for runtime
install state and existing project memory state.

New users should follow the
[quick start](release-readiness.md#current-quick-start) or the
[minimal project adoption walkthrough](walkthroughs/minimal-project-adoption.md)
instead. This guide is for users who already have a runtime install from a
previous public release.

## Upgrade Support Matrix

| Source version | Category | Expected upgrade path |
| --- | --- | --- |
| `v0.4.6` | **Supported direct** | Existing project memory is compatible without migration. A schema-1 copy runtime whose content differs from the new source requires reviewed `install.ps1 -ReplaceManaged` migration; a default run reports conflict and keeps schema 1. |
| `v0.4.5` | **Supported direct** | Same as `v0.4.6`. Template structure is identical. |
| `v0.4.4` | **Supported direct** | Same as `v0.4.5`. Template structure is identical. |
| `v0.4.3` | **Supported direct** | Same as `v0.4.4`. Template structure is identical. |
| `v0.4.2` | **Supported direct** | First release with language-scoped template model (`templates/languages/`). Existing project memory from this model is forward-compatible. |
| `v0.4.1` | **Best-effort** | Install script works, but templates used the pre-language-scoped layout (historical: flat `templates/` without language prefix). After upgrading the runtime, run memory upgrade analyze to detect stale template references. |
| `v0.4.0` | **Best-effort** | Similar to `v0.4.1`. The language migration workflow was introduced here but templates were not yet language-scoped. |
| `v0.3.0`, `v0.3.1` | **Best-effort** | Install script exists but project structure differs significantly. After upgrading the runtime, run memory upgrade analyze and review the proposal before applying. |
| `v0.1.0`, `v0.2.0` | **Unsupported / manual reinstall** | Early releases with substantially different project structure. Back up runtime and project-specific content, use `install.ps1 -ReplaceManaged`, then re-bootstrap project memory with `-ForceResetScaffold` only after confirming scaffold customizations may be discarded. |

### Terminology

- **Supported direct**: existing project memory is forward-compatible without
  migration. Schema-2 runtimes refresh incrementally. Schema-1 copy manifests
  do not contain a reliable per-file baseline, so any target/source difference
  is a conflict until the user reviews the runtime and explicitly supplies
  `-ReplaceManaged`.
- **Best-effort**: rerun `install.ps1`, review `install-report.json`, and resolve
  any runtime conflicts before continuing. Existing project memory may contain
  stale template references or missing fields. Run memory upgrade analyze after
  upgrading and review the proposal before applying.
- **Unsupported / manual reinstall**: The install script can replace the runtime
  files, but the existing project memory structure is too old for the automatic
  upgrade flow. Back up project-specific content, then re-bootstrap with
  `-ForceResetScaffold`.

## Runtime Install Upgrade

### Same-Machine Refresh (Most Common)

Incrementally refresh an existing runtime install on the same machine:

```powershell
# Clone or pull the latest release
git checkout v0.7.0  # or the target tag

# Refresh managed files and preserve unknown or locally modified content
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install.ps1 -Profile recommended
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
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install.ps1 -Profile recommended -TargetDir <path>
```

Copy mode is the default and creates independent file copies without junctions
or symbolic links. The existing `-Copy` switch remains compatible.

### Explicit Development Link Install

Contributors can explicitly opt into source-linked runtime items:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install.ps1 -Profile recommended -TargetDir <dev-runtime> -DevLink
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

## Project Memory Upgrade

After upgrading the runtime, existing project memory should be validated.

### Supported Direct Sources (v0.4.2+)

For projects created with `v0.4.2` or later, the project memory structure
is forward-compatible. Run these checks after upgrading:

```powershell
# 1. Check hub lock status
powershell -NoProfile -ExecutionPolicy Bypass -File <runtime>/skills/project-bootstrap/scripts/check_hub_lock.ps1 -ProjectDir <project> -Json

# 2. Run memory upgrade analyze (read-only)
powershell -NoProfile -ExecutionPolicy Bypass -File <runtime>/skills/project-bootstrap/scripts/memory_upgrade.ps1 -ProjectDir <project> -Mode Analyze

# 3. Run context gate
powershell -NoProfile -ExecutionPolicy Bypass -File <runtime>/skills/project-context-gate/scripts/context_gate.ps1 -ProjectRoot <project>

# 4. Run memory diagnosis
powershell -NoProfile -ExecutionPolicy Bypass -File <runtime>/skills/memory-governance/scripts/memory_diagnose.ps1 -ProjectRoot <project>
```

If analyze reports 0 findings and the hub lock is `in_sync`, no migration
is needed. The project memory is ready to use with the upgraded runtime.

### Best-Effort Sources (v0.3.x–v0.4.1)

For projects from older releases, run the full upgrade flow:

```powershell
# 1. Analyze
powershell -NoProfile -ExecutionPolicy Bypass -File <runtime>/skills/project-bootstrap/scripts/memory_upgrade.ps1 -ProjectDir <project> -Mode Analyze

# 2. Plan (generates a reviewable proposal)
powershell -NoProfile -ExecutionPolicy Bypass -File <runtime>/skills/project-bootstrap/scripts/bootstrap_project.ps1 -ProjectDir <project> -PlanMemoryUpgrade

# 3. Review the proposal, then apply
powershell -NoProfile -ExecutionPolicy Bypass -File <runtime>/skills/project-bootstrap/scripts/bootstrap_project.ps1 -ProjectDir <project> -ApplyMemoryUpgrade -UpgradePlan <proposal>

# 4. Validate
powershell -NoProfile -ExecutionPolicy Bypass -File <runtime>/skills/project-context-gate/scripts/context_gate.ps1 -ProjectRoot <project>
powershell -NoProfile -ExecutionPolicy Bypass -File <runtime>/skills/memory-governance/scripts/memory_diagnose.ps1 -ProjectRoot <project>
```

See [Existing Project Upgrade Path](existing-project-upgrade.md) for the
full conservative upgrade flow and local memory preservation rules.

### Unsupported Sources (v0.1.0, v0.2.0)

For projects from early releases:

1. Back up any project-specific `.agents/` content (process.txt, plan.md,
   notes.md, context entries, local specs).
2. Re-bootstrap with explicit force reset:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File <runtime>/skills/project-bootstrap/scripts/bootstrap_project.ps1 -ProjectDir <project> -ForceResetScaffold
   ```

3. Restore project-specific content from backup.
4. Validate with context gate and memory diagnosis.

### Fresh-Machine Install

A fresh-machine install has no existing runtime or project memory. Use the
standard quick start:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install.ps1 -Profile recommended
```

Then bootstrap any project:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ~/.agents/skills/project-bootstrap/scripts/bootstrap_project.ps1 -ProjectDir <project> -ProjectLanguage en
```

No upgrade or migration steps are needed for fresh installs.

## Rehearsal Evidence

The `v0.6.0` → `v0.7.0` upgrade path has been rehearsed for this release.
Earlier rehearsals remain in
[Old-Release Rehearsal Evidence](old-release-rehearsal-evidence.md) as retained
historical evidence; they are not deleted or rewritten. A publish-finalization
branch SHA is provisional review evidence, not the final tag target. The final
tag target is determined only after the authorized merge.

## Release Process Implications

Starting with `v0.5.0`, a release that changes the install contract, template
structure, project memory schema, hub lock format, or install profiles
requires at least one old-release upgrade rehearsal before tagging. This
rehearsal:

- Exercises the most recent supported-direct tag against the target release.
- Validates both runtime install upgrade and project memory upgrade.
- Records results as public-safe evidence in this repository.
- Is a manual checklist today; scripted automation is a future enhancement.

Patch or docs-only releases that do not change the above surfaces may skip
the rehearsal if the maintainer records the deferral.

See [Release Process](release-process.md#old-release-upgrade-rehearsal) for
the rehearsal requirement.

## Non-Goals

- This document does not define an online auto-updater.
- It does not promise indefinite support for every historical tag.
- It does not change install profile behavior.
- It does not cover private overlay or local migration state.
