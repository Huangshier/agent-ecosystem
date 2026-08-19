# Old-Release Rehearsal Evidence

> **历史证据，非当前权威。** 本文是冻结的 old-release rehearsal evidence。
> 每个 rehearsal 只描述当时记录的 source tag、target SHA、commands 和 results；
> 文中的 “current main” 只表示该次 rehearsal 当时的 target，不表示今天的
> current `main`。retired Skills、旧 PowerShell 命令和旧 `-Force` 语义均属于
> 历史证据。当前 upgrade guidance 以
> [`docs/old-release-upgrade-path.md`](old-release-upgrade-path.md) 为准，当前
> Release authority 以 [`docs/release-process.md`](release-process.md) 为准。

This frozen document records old-release upgrade rehearsal results for the
public `agent-ecosystem` repository. Each rehearsal exercises a real published
tag against the target `main` commit recorded at rehearsal time.

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

## Rehearsal: v0.7.0 → v0.7.1 candidate

**Date**: 2026-08-04

**Source tag**: `v0.7.0` (commit
`2eb63eab87def3678f67d0d2e261b63c4bc08f3c`)

**Target**: `v0.7.1` publish-finalization candidate based on public `main`
`42c6662b3e705554d21598cb7323122c382d2d10`; final candidate evidence is
recorded by the publish-finalization PR.

**Install mode**: copy

**Profile**: `recommended`

### Isolated runtime lifecycle

1. A fresh candidate install created a schema-2 `recommended` copy runtime with
   exact source identity and no conflicts.
2. Runtime status reported managed-file, source-provenance, bridge, and project
   facts without inferring remote-latest state.
3. Uninstall preserved unknown content and removed the isolated managed runtime.

Result: **PASS**. Fresh install, status, managed-file accounting, provenance, and
uninstall remain conservative and deterministic.

### Runtime upgrade and content protection

1. Installed the published `v0.7.0` `recommended` profile into an isolated copy
   runtime.
2. Re-ran the candidate installer through the ordinary default incremental path,
   without `-ReplaceManaged` or its deprecated compatibility alias.
3. The clean runtime updated source-changed managed files, preserved unchanged
   files, reported no conflicts, and produced a current schema-2 copy manifest.
4. A separate protection case preserved unknown content and a locally modified
   managed file, reported the managed conflict, and did not silently replace the
   local change.

Result: **PASS**. A clean `v0.7.0` copy runtime upgrades directly, while unknown
and locally modified content remains protected by default.

### Existing project memory and context metadata

Two Simplified Chinese projects were created from the isolated `v0.7.0` runtime
before the runtime upgrade. One remained unmodified; the other customized a
project-root template before refresh.

- Candidate status and the installed context gate reported the project-template
  state through trusted managed-copy provenance.
- The conservative `-RefreshUnmodifiedTemplates` path updated eligible old
  templates, created backups for accepted changes, and preserved the customized
  file hash.
- Hub-lock inspection, memory-upgrade analysis, context gate, and memory
  diagnosis completed without requiring forced project migration.
- Optional `-Query` matching returned deterministic Summary / Keywords metadata
  evidence for a known match and a fail-soft empty result for a miss. Matches did
  not load or apply entry bodies.

Result: **PASS**. Project state remains visible, conservative refresh respects
local customization, and metadata matching stays optional and read-only.

### Agent skill bridge

An explicit bridge for `project-bootstrap` and `project-context-gate` completed
with both links current and no stale, broken, conflicting, or unknown entries.
The ordinary installer did not create an implicit client bridge.

Result: **PASS**. The bridge remains opt-in and status-visible after upgrade.

### Final candidate binding

The publish-finalization PR records the final candidate commit and the completed
PowerShell 7, Windows PowerShell 5.1, and hosted evidence for that head. A branch
commit is review evidence only; the final tag target is determined by the later
authorized merge.

### Limitations

- The rehearsal used the `recommended` profile on Windows; full release
  validation separately covers every install profile, supported hosted operating
  system, and both PowerShell runtimes.
- The rehearsal exercised representative unmodified and customized projects. It
  does not replace project-specific review before accepting a suggested template
  refresh.
- Bridge targets were isolated client directories, not production client
  runtimes.

## Rehearsal: v0.7.1 → current C3.3 main

**Date**: 2026-08-13

**Source tag**: `v0.7.1` (commit
`df1de467ea0b19ca98d6994b5fb19001d4ec0334`)

**Target**: current `main` (commit
`96d167321e512bd99bc911e78fd3c7a11e78cf7e`)

**Install mode**: copy

**Profile**: `recommended`, plus an isolated `c3-3-candidate` runtime for the
project migration stage.

### Runtime upgrade

1. Installed the published `v0.7.1` `recommended` profile into an isolated copy
   runtime, producing a schema-2 manifest with exact `v0.7.1` provenance.
2. Re-ran the current-main installer through the ordinary default incremental
   path, without `-ReplaceManaged` or its deprecated compatibility alias.
3. The upgrade reported 9 updated and 172 unchanged managed files with 0
   conflicts. Untracked files and a locally modified managed file were preserved,
   and the resulting schema-2 manifest recorded the current-main source identity
   without inventing a release version.

Result: **PASS**. A clean `v0.7.1` copy runtime upgrades directly, while unknown
and locally modified content remains protected by default.

### Existing project migration to C3.3 workspace

A representative existing project was created from the isolated `v0.7.1` runtime,
then migrated with the current C3.3 runtime path:

1. `migrate-project.ps1` Analyze reported the project eligible with no human
   dispositions for its real Work, Context, Procedure, and Spec content.
2. Apply with explicit confirmation created a complete project-owned backup,
   applied the reviewed plan, and returned a passing migrated-workspace check.
3. The final canonical workspace check passed and reported the Work, Context,
   Procedure, and Spec assets; discovery and read returned the migrated assets
   with valid canonical schemas and no parser findings.
4. The project `hub.lock` recorded the C3.3 workspace model and dormant state
   without enabling `default` or `recommended`.

Result: **PASS**. A `v0.7.1` existing project enters the canonical C3.3 workspace
through the ordinary Analyze → Apply path, and its canonical assets remain
checkable, discoverable, and readable.

### Uninstall boundary

After migration, uninstalling the isolated `c3-3-candidate` runtime removed only
the runtime-owned content and left every project Work, Context, Procedure, and
Spec file byte-for-byte unchanged.

Result: **PASS**. Runtime uninstall does not delete project canonical assets.

### Limitations

- This rehearsal ran on Windows in copy mode. Cross-platform hosted evidence for
  the C3.3 runtime and workspace is covered by the Slice G validation closure.
- The rehearsal exercised one representative existing project. It does not
  replace project-specific review before accepting a migration plan.
- C3.3 remains dormant. This rehearsal does not perform the `default` or
  `recommended` cutover, which requires a separate explicit maintainer decision.

## Rehearsal: v0.7.1 → v0.8.0 candidate

**Date**: 2026-08-19

**Source tag**: `v0.7.1` (commit
`df1de467ea0b19ca98d6994b5fb19001d4ec0334`)

**Target**: current `main` (commit
`be91fd279aca2b983bc714a0ff4a44fffa966236`)

**Install mode**: copy

**Profile**: `recommended`

This rehearsal is part of Issue #345 Stage A (release-candidate / evidence) for
`v0.8.0`. It runs entirely in isolated scratch directories; no live `~/.agents`
runtime, real user project, real agent client skill directory, or private
repository content is touched.

### Runtime upgrade (v0.7.1 → current main)

1. Installed the published `v0.7.1` `recommended` profile into an isolated copy
   runtime, producing a schema-2 manifest with exact `v0.7.1` provenance
   (`df1de467ea0b19ca98d6994b5fb19001d4ec0334`) and the four kernel skills:
   `project-bootstrap`, `project-context-gate`, `workflow-spec-lite`,
   `memory-governance`.
2. Re-ran the current-main installer through the ordinary default incremental
   path, without `-ReplaceManaged` or its deprecated compatibility alias.
3. The upgrade updated 51 managed files and left 156 unchanged with 0 conflicts.
   The resulting schema-2 manifest recorded the current-main source commit
   (`be91fd279aca2b983bc714a0ff4a44fffa966236`) without inventing a release
   version, listed only `project-bootstrap` and `project-workspace` as installed
   skills, and declared `workspace.architecture=c3.3`, `lifecycle=active`,
   `default_cutover=true` with `project-context-gate`, `memory-governance`, and
   `workflow-spec-lite` in `retired_from_c3_3_authority`.
4. Runtime status after upgrade reported all 191 managed files as `current` with
   0 modified / 0 missing / 0 conflict, manifest status `current`, and workspace
   ownership `manifest-scoped`. The only finding was `release_not_recorded`
   (`info`), expected because the target `main` commit is not a version tag.

Result: **PASS**. A clean `v0.7.1` copy runtime converges to the current C3.3
runtime through the ordinary default installer path, without manual file
deletion or `-ReplaceManaged`.

### Managed-content protection

1. A separate protection case added an unknown file at the runtime root and
   appended content to a managed knowledge file.
2. Re-running the ordinary installer preserved the unknown file, skipped the
   locally modified managed file, reported 0 conflicts, and exited with status
   `warning` instead of overwriting local content.
3. Restoring the test changes and re-running the installer returned to
   `success` with 191 unchanged files and no conflicts.

Result: **PASS**. Unknown and locally modified content remains protected by
default; no source-colliding unknown or manual deletion was needed.

### Agent skill bridge transition

1. Using the `v0.7.1` bridge helper, an explicit bridge was created in an
   isolated client skill directory for all four `v0.7.1` kernel skills,
   including the three later retired from C3.3 authority
   (`project-context-gate`, `workflow-spec-lite`, `memory-governance`).
2. The runtime was upgraded to current main through the ordinary default path.
   The upgrade preserved the bridge manifest as unknown content and did not
   delete client links.
3. Post-upgrade status reported the bridge as `stale` with
   `manifest_status=current`: `project-bootstrap` stayed `current`, and the
   three retired skills were reported `stale` (not `current`), with
   `bridge.skill.not_managed` warnings. The transition state is visible and
   fails closed.
4. The current bridge helper rejected newly bridging a retired skill
   (`project-context-gate`) with a fail-closed preflight error and created no
   links, and it successfully bridged `project-workspace` as a current managed
   skill. Final status showed the two current skills `current` and the three
   retired skills `stale`.

Result: **PASS**. A legal `v0.7.1` bridge transitions to a visible, safe state
after upgrade without undocumented manual deletion. Newly bridging active
skills keeps the stale retired records visible in status; it is not itself the
cleanup path.

### Bridge recovery path after upgrade (v0.7.1 → current main)

The recovery flow below was rehearsed in isolation after the stale-after-upgrade
state above. It is the supported way to leave the transition state:

1. **Manifest-owned uninstall**: current
   `scripts/uninstall.ps1 -TargetDir <isolated-runtime>` recognized the old
   bridge manifest ownership (`runtime` binding and per-record source / target
   path checks), safely removed the four manifest-owned client links including
   the three stale retired links and the bridge manifest, completed the runtime
   uninstall, and did not require any manual deletion. A user file placed in the
   same isolated client skill directory was preserved byte-for-byte, and no
   nested-unknown or locally-modified content blocked the run.
2. **Reinstall current Runtime**: current `scripts/install.ps1 -Profile
   recommended -TargetDir <isolated-runtime>` installed the current C3.3
   runtime fresh.
3. **Rebridge active skills**: current
   `scripts/link-agent-skills.ps1` bridged only `project-bootstrap` and
   `project-workspace`. The bridge manifest contained only those two active
   records; the three retired links were absent from the client directory;
   status reported `bridge.status=current` with both links `current`; and the
   user file in the client directory remained unchanged.

Result: **PASS**. A stale-after-upgrade bridge transitions cleanly through the
supported path: manifest-owned uninstall, reinstall the current runtime, and
re-bridge the active skills. No manual link or manifest deletion is required,
and unrelated client content is never touched.

### Legacy project migration (Analyze → Apply → check/discover → Rollback)

A representative existing project was created from the isolated `v0.7.1`
runtime (`ProjectLanguage zh-CN`), then upgraded runtime and migrated with the
current C3.3 runtime path:

1. `migrate-project.ps1` Analyze reported the project `eligible` with no human
   dispositions for its real Work (process.txt / plan.md), Context
   (notes.md and context entries), Procedure (command cards), and Spec content.
2. Apply with explicit confirmation created a complete project-owned backup,
   applied the reviewed plan, and returned `workspace_check=PASS`.
3. Post-Apply `check-project-workspace.ps1` reported `PASS` with all canonical
   Work / Context / Procedure / Spec assets `canonical_valid`;
   `discover-project-assets.ps1` refreshed the disposable catalog and returned
   the migrated assets; `read-project-assets.ps1` parsed all four sampled
   assets with 0 findings.
4. The project `hub.lock` recorded `workspace_model=c3.3`,
   `workspace_state=active`, and the project language.
5. Guarded Rollback by `-BackupId` restored the project, and re-running Analyze
   on the rolled-back project returned `eligible` with file hashes identical to
   the pre-migration state. The backup directory was retained after rollback.
6. Rollback is intentionally guarded: running `discover` (which writes the
   disposable catalog) after Apply makes later Rollback fail closed with
   `STATE_CONFLICT` until the catalog state is restored, confirming the
   unchanged-project protection contract.

Result: **PASS**. A `v0.7.1` existing project completes the canonical C3.3
workspace migration through the ordinary Analyze → Apply → Rollback path, and
Rollback restores the pre-migration state byte-for-byte while retaining the
backup.

### Limitations

- This rehearsal ran on Windows in copy mode with the `recommended` profile;
  full release validation separately covers every install profile and supported
  hosted operating system under the current PowerShell Core 7.6+ validation
  control plane.
- The rehearsal exercised one representative existing project; it does not
  replace project-specific review before accepting a migration plan.
- The Stage A candidate note (`docs/releases/v0.8.0.md`) is a release candidate;
  it does not claim a published release, tag target, or GitHub Release URL, and
  it does not change any publish-finalization version entrypoint.
- The rehearsal used isolated client skill directories, not production client
  runtimes.
