# Project Bootstrap Command Boundaries

This design note answers issue #119. It defines the command ownership boundary
for `project-bootstrap` before the project adds more upgrade, update, or
old-release orchestration flows.

The goal is to preserve the existing public CLI while preventing
`bootstrap_project.ps1` from becoming the default home for every future
project-memory operation.

## Scope

This note covers command ownership for:

- scaffold creation;
- safe refresh;
- explicit force reset;
- legacy memory upgrade wrappers;
- conservative project-memory language migration wrappers;
- future old-release upgrade orchestration.

It does not implement #96 release-validator or language-migration
modularization, #97 shared PowerShell helper ownership, #118 old-release
upgrade validation, or any release-candidate work.

## Ownership Boundary

| Flow | Primary home | `bootstrap_project.ps1` role | Boundary |
| --- | --- | --- | --- |
| Empty scaffold creation | `bootstrap_project.ps1` | Owner | Create missing project-root and `.agents/` scaffold files from runtime templates, write `hub.lock.json`, and initialize missing hub templates from bundled assets when needed. |
| Safe missing-template refresh | `bootstrap_project.ps1` | Owner | Copy missing scaffold files, preserve existing project memory, update lock metadata, and keep default memory analysis read-only. |
| Unmodified-template refresh | `bootstrap_project.ps1` | Owner | Refresh only files that still match prior installed template hashes. Modified files stay preserved for manual review. `-OverwriteTemplates` remains a warning-emitting compatibility alias for this mode. |
| Explicit force reset | `bootstrap_project.ps1` | Owner | Replace scaffold/template files only when `-ForceResetScaffold` is supplied, after backup evidence is written. This remains incompatible with upgrade and migration modes. |
| Legacy memory upgrade | `memory_upgrade.ps1` | Thin wrapper and compatibility entrypoint | Analyze, plan, and apply logic belongs in `memory_upgrade.ps1`. Bootstrap may continue exposing `-AnalyzeMemoryUpgrade`, `-PlanMemoryUpgrade`, `-ApplyMemoryUpgrade`, and `-AutoUpgrade` so existing callers can discover the flow from one command. |
| Project-memory language migration | `language_migration.ps1` and `audit_memory_language.ps1` | Thin wrapper and compatibility entrypoint | Migration analysis, planning, apply, validation, narrative proposal handling, and body-language audit logic belong in dedicated helpers. Bootstrap may route existing migration switches to those helpers without running the normal scaffold write path for read-only analyze modes. |
| Hub lock drift checks | `check_hub_lock.ps1` | No owner role | Lock drift validation stays a standalone read-only helper. Bootstrap writes lock metadata but should not become the general drift-audit command. |
| Experience promotion and index rebuild | `knowledge-hub/scripts/` runtime helpers; compatibility copies under `skills/project-bootstrap/scripts/` | Compatibility copy only | Routine global experience maintenance belongs in the installed knowledge hub, not in bootstrap. Bootstrap can install or copy the helper surface needed for standalone runtime setup. |
| Candidate intake and triage | `knowledge-hub/scripts/manage_candidates.ps1`; compatibility copy under `skills/project-bootstrap/scripts/` | Compatibility copy only | Candidate intake writes only an explicit runtime inbox, treats explicit project roots as read-only, and remains separate from formal experience promotion. |
| Future old-release upgrade orchestration | Dedicated upgrade orchestration helper | Compatibility alias only if needed | Release-to-release upgrade rehearsals should live in a dedicated helper or command card that composes workspace inspection, bootstrap refresh, memory upgrade, language migration, and validation steps. Do not add more orchestration logic to `bootstrap_project.ps1` by default. |

## Compatibility Rules

- Keep existing public switches unless a separate PR introduces a documented
  compatibility or deprecation plan.
- Do not remove or rename `-AnalyzeMemoryUpgrade`, `-PlanMemoryUpgrade`,
  `-ApplyMemoryUpgrade`, `-AutoUpgrade`, language migration switches,
  `-RefreshUnmodifiedTemplates`, `-OverwriteTemplates`, or
  `-ForceResetScaffold` in this boundary PR.
- New wrappers should preserve backup-first and proposal-first behavior.
- Refresh or upgrade wording must continue to preserve project-specific memory
  by default.
- Reset or reinitialize wording must not imply destructive overwrite unless
  the caller explicitly confirms old memory can be discarded.

## Future Upgrade Orchestration

Old-release upgrade work should be designed as an orchestration flow, not as a
new set of bootstrap modes. The orchestration should:

- choose the target project and release baseline;
- run active `project-workspace` `check` / `discover` or equivalent context reconstruction;
- run bootstrap refresh only for scaffold and lock surfaces;
- call `memory_upgrade.ps1` for legacy memory normalization;
- call `language_migration.ps1` and `audit_memory_language.ps1` for language
  changes or audit evidence;
- run public release validation or target-project validation;
- record a public-safe summary that omits local scratch paths, local-only
  evidence, and auth material.

The helper may live under `skills/project-bootstrap/scripts/` while the flow is
specific to project-memory upgrade support. If later work from #97 establishes
a shared runtime script owner, the orchestration helper can move behind that
ownership model without changing the bootstrap command boundary.

## Standalone Runtime Packaging

The boundary must keep installed skills usable outside the source checkout.

- Runtime helpers must resolve paths relative to their own script or installed
  runtime root, not a maintainer checkout.
- Any helper used by a bootstrap wrapper must be included in the installed
  `project-bootstrap` skill package or in the installed `knowledge-hub/scripts`
  runtime surface.
- Shared helper extraction from #97 must preserve copy-mode and link-mode
  installer behavior before bootstrap depends on it.
- Public validation should cover both the command-boundary documentation and
  the standalone packaging model before new upgrade/update flows are added.

## Relation To Other Issues

- #96 covers staged modularization for release validation and language
  migration internals. This note does not move those functions.
- #97 covers shared PowerShell path helpers and runtime script ownership. This
  note only states that future shared helper dependencies must preserve
  standalone packaging.
- `docs/powershell-helper-ownership.md` defines the first-stage #97 helper
  ownership model and the intentional `Join-PathParts` duplication allowlist.
- #118 covers old-release upgrade validation. This note defines where that
  orchestration should live before #118 implementation begins.

## Validation Expectation

Public changes that alter this boundary should run:

```powershell
git diff --check
pwsh -NoProfile -File scripts/validate-release.ps1 -ScratchRoot <scratch-root>
```

The release validator checks that this design note, the project-bootstrap skill
documentation, and the existing-project upgrade guide continue to expose the
boundary and standalone packaging constraints.
