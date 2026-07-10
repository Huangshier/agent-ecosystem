# Old-Release Rehearsal Evidence

This document records old-release upgrade rehearsal results for the public
`agent-ecosystem` repository. Each rehearsal exercises a real published tag
against the current `main` branch to validate the upgrade path.

## Rehearsal: v0.4.6 → current main

**Date**: 2026-06-09
**Source tag**: `v0.4.6` (commit `40c86ea`)
**Target**: current `main` (commit `f336d93` at rehearsal time)
**Install mode**: copy (`-Copy -Force`)
**Profile**: `recommended`

This section is historical evidence. At rehearsal time, `-Force` still meant a
full replacement. Current `main` treats `-Force` as a deprecated alias for
`-ReplaceManaged` and uses protected incremental copy installs by default.

### Scenario 1: Runtime Install Upgrade

Steps:

1. Install runtime from `v0.4.6` tag into a temporary directory.
2. Verify v0.4.6 install manifest (5 items, all `copy` mode).
3. Upgrade runtime from current `main` with `-Copy -Force`.
4. Verify post-upgrade manifest (5 items, all `copy` mode).

Result: **PASS**. The `-Force` flag replaced all runtime files cleanly. The
install manifest recorded 5 items (`knowledge-hub`, 4 skills) in copy mode
both before and after upgrade.

### Scenario 2: Fresh Project Bootstrap (v0.4.6 runtime)

Steps:

1. Create a temporary git-backed project directory.
2. Bootstrap project memory using the v0.4.6 runtime
   (`bootstrap_project.ps1 -ProjectLanguage en`).
3. Verify project memory structure (12 scaffold files under `.agents/`).
4. Verify `hub.lock.json` records the v0.4.6-era template hash and project
   language `en`.

Result: **PASS**. Bootstrap created the expected scaffold. Hub lock recorded
the correct template hash and `project_language: en`.

### Scenario 3: Project Memory Upgrade (v0.4.6 → current main)

Steps:

1. Using the upgraded runtime (current `main`), run memory upgrade analyze
   on the v0.4.6-bootstrapped project.
2. Run hub lock drift check.
3. Run context gate (brief mode).
4. Run memory diagnosis.

Results:

| Check | Result |
| --- | --- |
| Memory upgrade analyze | **PASS** — 0 findings |
| Hub lock drift | **PASS** — `in_sync` |
| Context gate | **PASS** — all expected hot/cold files listed |
| Memory diagnosis | **PASS** — 0 findings (0 warnings, 0 info) |

The v0.4.6 project memory structure and template hashes are fully
forward-compatible with current `main`. No migration steps were needed.

### Diff Surface Between v0.4.6 and main

The changes between `v0.4.6` and `main` (at rehearsal time) are:

- Validator modularization and check-group extraction (#96, #136–#140)
- PowerShell helper ownership documentation (#97, #134, #135)
- Context gate brief output (#117, #133)
- Project-bootstrap command boundary docs (#119, #130)
- Runtime adoption bridge docs (#116, #131)
- Issue triage decision commands (#122, #124, #126)
- v0.5.0 maintenance scope docs (#120, #129)

None of these changes alter the install contract, template structure, or
project memory schema. The upgrade surface is documentation, validator, and
workflow improvements — not breaking changes to the runtime or project
memory contract.

### Limitations

- This rehearsal tested only the `recommended` profile in copy mode. The
  `minimal`, `full`, and `dev` profiles install a subset or identical content.
- The then-default link/junction mode was not explicitly rehearsed. Current
  releases make links an explicit `-DevLink` contributor mode and validate it
  separately from the default copy contract.
- Only `en` project language was rehearsed. The `zh-CN` language path uses
  the same template structure with different content.
- The rehearsal used the live knowledge hub at `~/.agents/knowledge-hub`,
  which was already updated to current `main`. A fully isolated rehearsal
  would use a dedicated hub directory.
- Only the `v0.4.6` tag was rehearsed. Older tags (best-effort and
  unsupported categories) may require manual review or re-bootstrap.

## Future Rehearsals

Additional rehearsals should be added here when:

- A new release changes the install contract or template structure.
- A best-effort or unsupported source tag needs documented evidence.
- The rehearsal process is automated into a scripted fixture.

Each rehearsal should record: source tag, target commit, install mode,
profile, step-by-step results, and any limitations.
