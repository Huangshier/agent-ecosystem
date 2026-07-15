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

## Rehearsal: v0.5.2 → v0.6.0 candidate

**Date**: 2026-07-11

**Source tag**: `v0.5.2` (commit `e2716833c8c5d06fd21ec6215cf86aa86a579009`)

**Target**: `v0.6.0` publish-finalization branch based on public `main`
`334ff0010ab84aa5c2b68e1ae65f24d2b85706b8`

**Install mode**: copy

**Profile**: `recommended`

### Runtime migration

1. Installed `v0.5.2` into an isolated temporary runtime, producing a schema-1
   copy manifest.
2. Ran the current installer without replacement flags. It reported 22 managed
   differences as conflicts, preserved the runtime content, and retained schema
   1 instead of silently migrating.
3. Re-ran after review with `-ReplaceManaged`. The installer updated 22 managed
   files with 0 conflicts and produced a schema-2 `copy` manifest for the
   `recommended` profile.

Result: **PASS**. The default path is conservative; migration requires an
explicit reviewed replacement decision.

### Existing project memory

A project bootstrapped from the isolated v0.5.2 runtime and bundled knowledge
hub completed memory upgrade analysis with 0 findings. The installed-copy hub
is intentionally not a Git checkout, so hub lock inspection reports
`hub_not_git`; this is a runtime source-state result, not a project memory
content finding. Context gate discovered all expected hot and cold surfaces,
and memory diagnosis reported 0 findings.

Result: **PASS**. Existing v0.5.2 project memory does not require forced
scaffold migration for v0.6.0.

### Limitations

- The rehearsal used the `recommended` profile on Windows; full release
  validation separately covers every profile and both copy / explicit
  development-link strategies.
- Agent-specific skill bridge targets remain an explicit post-install opt-in
  and were validated by the dedicated release fixture matrix rather than a live
  client directory.

## Rehearsal: v0.6.0 → v0.7.0

**Date**: 2026-07-15

**Source tag**: `v0.6.0` (commit
`65a857e69df253f058baa4198cffc675c0018a11`)

**Target**: `v0.7.0` publish-finalization branch based on public `main`
`f77562f165dfd4799986f3bbb23bbbc08e31e085`

**Install mode**: copy

**Profile**: `recommended`

### Isolated runtime lifecycle

1. A fresh current-main install created a schema-2 copy runtime with 175
   managed files, exact source-commit identity, and no conflicts.
2. Runtime status reported all 175 managed files as current. Because the source
   was an untagged main commit, release provenance was correctly reported as
   not recorded instead of inventing a version.
3. Uninstall completed the schema-2 copy preflight, preserved unknown content,
   and removed the isolated runtime.

Result: **PASS**. Fresh install, status, managed-file accounting, provenance,
and uninstall remain conservative and deterministic.

### Runtime upgrade

1. Installed the `v0.6.0` `recommended` profile into an isolated runtime with
   171 managed files.
2. Re-ran the current-main installer with the ordinary default command and no
   replacement flag.
3. The upgrade updated 18 files, left 157 unchanged, reported 0 conflicts, and
   produced a current schema-2 copy manifest with 175 managed files.

Result: **PASS**. An existing `v0.6.0` copy runtime upgrades directly through
the default incremental path.

### Existing project memory

Two Simplified Chinese projects were created from the isolated `v0.6.0`
runtime before the runtime upgrade. One project remained unmodified; the other
customized `.agents/AGENTS.md` before refresh.

- Both projects reported `optional-refresh` with
  `template-baseline-drift` after the runtime upgrade.
- The installed context gate used the trusted manifest-managed-copy provider
  and offered the conservative `-RefreshUnmodifiedTemplates` action.
- The unmodified project refreshed all 25 template files.
- The customized project refreshed 24 of 25 files, skipped the customized
  `.agents/AGENTS.md`, and preserved its SHA-256 value exactly.
- Both projects ended in the `current` / `in-sync` state.

Result: **PASS**. Project drift is visible, unmodified templates can refresh,
and customized project memory remains protected.

### Agent skill bridge

An explicit bridge for `project-bootstrap` and `project-context-gate` completed
with both links current and no stale, broken, conflicting, or unknown entries.

Result: **PASS**. The bridge remains opt-in and status-visible after upgrade.

### Limitations

- The rehearsal used the `recommended` profile on Windows; full release
  validation separately covers all profiles, supported operating systems, and
  both PowerShell runtimes.
- The rehearsal exercised two representative existing projects. It does not
  replace project-specific review before accepting a suggested template
  refresh.
- Bridge targets were isolated client directories, not production client
  runtimes.
