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
| `v0.4.6` | **Supported direct** | `install.ps1 -Force` replaces the runtime. Existing project memory is compatible without migration. |
| `v0.4.5` | **Supported direct** | Same as `v0.4.6`. Template structure is identical. |
| `v0.4.4` | **Supported direct** | Same as `v0.4.5`. Template structure is identical. |
| `v0.4.3` | **Supported direct** | Same as `v0.4.4`. Template structure is identical. |
| `v0.4.2` | **Supported direct** | First release with language-scoped template model (`templates/languages/`). Existing project memory from this model is forward-compatible. |
| `v0.4.1` | **Best-effort** | Install script works, but templates used the pre-language-scoped layout (historical: flat `templates/` without language prefix). After upgrading the runtime, run memory upgrade analyze to detect stale template references. |
| `v0.4.0` | **Best-effort** | Similar to `v0.4.1`. The language migration workflow was introduced here but templates were not yet language-scoped. |
| `v0.3.0`, `v0.3.1` | **Best-effort** | Install script exists but project structure differs significantly. After upgrading the runtime, run memory upgrade analyze and review the proposal before applying. |
| `v0.1.0`, `v0.2.0` | **Unsupported / manual reinstall** | Early releases with substantially different project structure. Use `install.ps1 -Force` to replace the runtime, then re-bootstrap project memory with `-ForceResetScaffold` after backing up any project-specific content. |

### Terminology

- **Supported direct**: `install.ps1 -Force` replaces the runtime. Existing
  project memory is forward-compatible without migration. Hub lock drift check
  reports `in_sync` or a predictable hash change.
- **Best-effort**: `install.ps1 -Force` replaces the runtime. Existing project
  memory may contain stale template references or missing fields. Run memory
  upgrade analyze after upgrading and review the proposal before applying.
- **Unsupported / manual reinstall**: The install script can replace the runtime
  files, but the existing project memory structure is too old for the automatic
  upgrade flow. Back up project-specific content, then re-bootstrap with
  `-ForceResetScaffold`.

## Runtime Install Upgrade

### Same-Machine Refresh (Most Common)

Replace an existing runtime install on the same machine:

```powershell
# Clone or pull the latest release
git checkout v0.5.0  # or the target tag

# Force-replace the existing runtime
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install.ps1 -Profile recommended -Force
```

This replaces all skill directories, the knowledge hub, and the install
manifest. The `-Force` flag is required when the target directory already
exists. Without `-Force`, the installer refuses to modify an existing
installation.

### Copy Mode Install

To install into a separate directory (for testing or isolation):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install.ps1 -Profile recommended -TargetDir <path> -Copy -Force
```

Copy mode creates independent file copies. It does not create junctions or
symbolic links, so the install is fully portable.

### Link / Junction Mode Install

The default install mode uses `Junction` on Windows and `SymbolicLink` on
other platforms. Link mode installs point back to the source repository, so
they reflect the checked-out version at access time. After checking out a
new tag or branch, link-mode installs automatically reflect the new content.

If link creation fails, the installer falls back to copy mode for that item
and records `copy-fallback` in the manifest.

### Manifest After Upgrade

After upgrading, the install manifest records the current profile, install
mode, and each installed item. Verify the manifest:

```powershell
Get-Content ~/.agents/install-manifest.json | ConvertFrom-Json
```

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

The `v0.4.6` → current `main` upgrade path has been rehearsed. See
[Old-Release Rehearsal Evidence](old-release-rehearsal-evidence.md) for
the full results.

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
