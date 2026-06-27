# Release Readiness

Status: `v0.5.1` published public release.

The initial public release has been published as `v0.1.0`; `v0.2.0` closed the
public migration work. `v0.3.0` packaged backlog remediation and public
maintenance issues into the normal release flow. `v0.3.1` was published as a
public stabilization release. `v0.4.0` delivered the conservative `en` /
`zh-CN` engineering-memory language migration workflow, completing issue #30.
`v0.4.1` consolidated project-memory template authority, and `v0.4.2`
converged the template model to language-scoped project-root and project-agent
directories. `v0.4.3` was published as a stabilization release for release
record normalization, legacy template-path audit coverage, and existing project
upgrade guidance. `v0.4.4` was published as a stabilization / docs / governance
patch release for the post-`v0.4.3` guardrails, memory-language governance,
Chinese homepage, domain-pack governance, and spec-state reconciliation work.
`v0.4.5` packaged the issue triage label-sync, spec validator zh-CN anchor,
UTF-8 no-BOM, release-validation permissions, and issue template fixes.
`v0.4.6` packaged spec lifecycle governance, public-safe reusable knowledge
patterns, and release body hygiene. `v0.5.0` packages the stabilization-first
maintenance closeout, public maintenance-record boundary, release validator
modularization, old-release upgrade rehearsal evidence, Claude Code adoption
shim, agent issue triage hardening, and hosted PR identity guard. `v0.5.1`
packages memory governance hardening, public-safe write authorization boundary
clarification, testing capability foundations, and release validator
thin-entrypoint closeout.

## v0.5.1 Published State

Current `main` includes the post-`v0.5.0` memory-governance / authorization /
testing-foundations / release-validator changes summarized in
`docs/releases/v0.5.1.md`. `v0.5.1` is aligned for maintainer tag and GitHub
Release publication from the merge commit of the `v0.5.1` publish-finalization
PR.

GitHub Release `v0.5.1` has been published:
https://github.com/Huangshier/agent-ecosystem/releases/tag/v0.5.1

Tag target: merge commit for the `v0.5.1` publish-finalization PR.

Local release validation for this alignment passed with
`PASS=62 FAIL=0 WARN=0 DEFERRED=0`.

Release body source: `docs/releases/v0.5.1.md`, between
`RELEASE_BODY_START` and `RELEASE_BODY_END`.

## v0.5.0 Published State

Current `main` includes the post-`v0.4.6` stabilization / governance /
validation-infrastructure changes summarized in `docs/releases/v0.5.0.md`.
`v0.5.0` is aligned for maintainer tag and GitHub Release publication from the
merge commit of the `v0.5.0` publish-finalization PR.

GitHub Release `v0.5.0` has been published:
https://github.com/Huangshier/agent-ecosystem/releases/tag/v0.5.0

Tag target: merge commit for the `v0.5.0` publish-finalization PR.

Local release validation for this alignment passed with
`PASS=58 FAIL=0 WARN=0 DEFERRED=0`.

Release body source: `docs/releases/v0.5.0.md`, between
`RELEASE_BODY_START` and `RELEASE_BODY_END`.

## v0.4.4 Published State

Current `main` includes the post-`v0.4.3` stabilization / docs / governance
changes summarized in `docs/releases/v0.4.4.md`. `v0.4.4` has been tagged and
published as a public release.

Published GitHub Release:
https://github.com/Huangshier/agent-ecosystem/releases/tag/v0.4.4

Tag target: `71fabb372a4cbc024f07c920a0c17b903a77afc2`.

## Completed

- Workflow Kernel skills are present under `skills/`.
- Kernel skill metadata includes `category`, `stability`, and `scope`.
- Public knowledge hub templates and selected generic maintenance scripts are present.
- One public-safe workflow experience entry is indexed.
- Knowledge Hub Phase 3 structure is present:
  `knowledge-catalog.md`, `experience/`, `patterns/`, `standards/`, and
  `domain-packs/`.
- One reusable engineering pattern and one cross-project standard are present.
- One public-safe domain pack scaffold is present:
  `knowledge/domain-packs/embedded-core/`.
- Public installer supports `minimal`, `recommended`, `full`, and `dev` profiles.
- `full` and `dev` remain reserved future public scopes that currently install
  the same public content as `recommended` until a governance-approved
  expansion lands.
- Recommended profile has been validated against a temporary runtime in copy mode.
- Recommended profile has been smoke-tested by bootstrapping a new project from
  a temporary runtime install.
- First public release version selected: `v0.1.0`.
- First public Chinese documentation ships as `README.zh-CN.md`.
- Reusable release validation is available at `scripts/validate-release.ps1`.
- Release process guidance is available at `docs/release-process.md`.
- Latest local hardened release validation passed with 40 checks passing, no
  failures, warnings, or deferred checks.
- Narrative migration plan/apply/validate from Phase 1 manual-review artifacts
  is covered by the release validator, including hash verification, category
  routing, and unapproved-by-default behavior.
- Duplicate experience-maintenance helpers have been reviewed:
  `project-bootstrap` keeps compatibility copies, while `knowledge-hub/scripts`
  is the preferred runtime maintenance entrypoint.
- PowerShell helper ownership is documented: repository maintenance scripts use
  `scripts/lib/path-guard.ps1`, while installed skill and knowledge-hub runtime
  scripts keep local helpers or depend only on same-package helpers.
- The initial public experience entry is documented as a public-safe reindexed
  backfill with local source paths intentionally omitted from `index.json`.
- Installer fallback metadata behavior is documented: the runtime
  `install-manifest.json` records the install mode used for each item.
- Latest local high-risk public audit found no matches, and public PowerShell
  scripts parsed successfully.
- CI release validation workflow is present at
  `.github/workflows/release-validation.yml` and is configured for PowerShell 7
  on Windows, Ubuntu, and macOS, plus Windows PowerShell 5.1 on Windows.
- Hosted CI release validation passed on Windows, Ubuntu, and macOS:
  https://github.com/Huangshier/agent-ecosystem/actions/runs/25509636087
- `.gitattributes` pins validation-sensitive text files to LF endings so
  experience registry hash checks remain stable across hosted runners.
- Bootstrap templates install a `Project Language Policy` section into
  `.agents/AGENTS.md`; release validation checks both repository guidance and
  bootstrap output.
- `project-bootstrap` can write first-session language scaffolds when an agent
  or workflow supplies `-ProjectLanguage en` or `-ProjectLanguage zh-CN`; release
  validation checks both languages with temporary projects.
- `project-bootstrap` distinguishes empty initialization, missing-template
  refresh, unmodified-template refresh, conservative memory migration, and
  explicit force reset. Compatibility overwrite emits warnings, and force reset
  remains backup-first.
- `project-bootstrap` supports conservative `en` / `zh-CN` project-memory
  language migration with analyze, plan, proposal, backup, apply, and validate
  modes.
- `workflow-spec-lite` includes a read-only spec validator that checks goals,
  non-goals, risks, acceptance evidence, and Execution Contract stop rules.
- Spec templates and memory-governance guidance include scope drift, unrelated
  refactor, and skipped acceptance protections.
- Knowledge catalog coverage includes the `embedded-core` domain pack scaffold.
- Public adoption surface includes `docs/how-to-adapt.md` and
  `examples/minimal-project/`.
- Public release notes are present at `docs/releases/v0.2.0.md`.
- Manifest-based uninstall preserves unknown runtime files and provides manual
  cleanup guidance when no manifest exists.
- Shared PowerShell helper extraction keeps path guard logic consistent across
  installer, uninstaller, validator, and benchmark scripts.
- Release validation helper extraction keeps common test utilities in
  `scripts/validation/release-test-helper.ps1`.
- Large-context benchmark coverage validates context gate JSON behavior with
  500 generated context files.
- Cross-platform shell strategy documents PowerShell as the canonical public
  script surface and defers Bash or Zsh wrappers.
- Memory diagnostics and memory upgrade analysis accept localized context
  discovery headings while preserving English-first public templates.
- Bilingual Public/Private Routing guidance is documented in the public
  knowledge hub and language policy.
- Public release notes are present at `docs/releases/v0.3.0.md`.
- Public release notes are present at `docs/releases/v0.3.1.md`.
- Public release notes are present at `docs/releases/v0.4.0.md`.
- Public release notes are present at `docs/releases/v0.4.1.md`.
- Public release notes are present at `docs/releases/v0.4.2.md`.
- Public release notes are present at `docs/releases/v0.4.3.md`.
- Conservative `en` / `zh-CN` language migration is complete: Phase 1
  deterministic scaffold migration and Phase 2 narrative migration from
  manual-review artifacts. Issue #30 is closed.
- Final hosted CI release validation for the published `v0.4.0` main passed on
  Windows PowerShell 5.1, Windows pwsh, Ubuntu pwsh, and macOS pwsh:
  https://github.com/Huangshier/agent-ecosystem/actions/runs/25795197326
- Historical `v0.4.1` release state: project-memory template authority was
  consolidated in `v0.4.1`. At that point, public
  templates moved under `knowledge-hub/templates/project-memory/`, the bundled
  project-bootstrap snapshot was synchronized, and the standalone
  `skills/project-bootstrap/templates/project-memory/` tree was removed.
- Final hosted CI release validation for the published `v0.4.1` main passed on
  Windows PowerShell 5.1, Windows pwsh, Ubuntu pwsh, and macOS pwsh:
  https://github.com/Huangshier/agent-ecosystem/actions/runs/25801192289
- Language-scoped template directory convergence was published in `v0.4.2`:
  public templates and bundled snapshots now use
  `templates/languages/en|zh-CN/project-root|project-agent`.
- Final hosted CI release validation for the published `v0.4.2` main passed on
  Windows PowerShell 5.1, Windows pwsh, Ubuntu pwsh, and macOS pwsh:
  https://github.com/Huangshier/agent-ecosystem/actions/runs/25809635716
- Current README and `README.zh-CN.md` describe the project as a Workflow
  Kernel with an explicit extension model and non-runtime boundaries.
- Release process guidance includes a lightweight Public Reader Review checklist.
- Release validation workflow uses Node 24-compatible action versions:
  `actions/checkout@v6` and `actions/upload-artifact@v7`.
- Final hosted CI release validation for the published `v0.3.1` main passed on
  Windows PowerShell 5.1, Windows pwsh, Ubuntu pwsh, and macOS pwsh:
  https://github.com/Huangshier/agent-ecosystem/actions/runs/25598098034
- GitHub Release `v0.3.1` has been published:
  https://github.com/Huangshier/agent-ecosystem/releases/tag/v0.3.1
- GitHub Release `v0.4.0` has been published:
  https://github.com/Huangshier/agent-ecosystem/releases/tag/v0.4.0
- GitHub Release `v0.4.1` has been published:
  https://github.com/Huangshier/agent-ecosystem/releases/tag/v0.4.1
- GitHub Release `v0.4.2` has been published:
  https://github.com/Huangshier/agent-ecosystem/releases/tag/v0.4.2
- GitHub Release `v0.4.3` has been published:
  https://github.com/Huangshier/agent-ecosystem/releases/tag/v0.4.3
- Hub initialization now leaves template hubs as ordinary directories unless
  `-InitializeGit` or `-CommitInitial` is explicitly supplied.
- Experience index rebuilds preserve registry bytes on no-op rebuilds, avoiding
  timestamp-only diffs.
- Validation scratch retention can be inspected with
  `scripts/prune-validation-scratch.ps1`, which is dry-run by default and only
  prunes evidence-marked validation run directories when `-Apply` is supplied.
- Existing project upgrade guidance documents the post-`v0.4.2`
  language-scoped template model, conservative upgrade flow, local memory
  preservation, and old path handling.
- `v0.4.3` release validation passed with
  `PASS=46 FAIL=0 WARN=0 DEFERRED=0`.
- Hosted Release validation for the published `v0.4.3` tag target
  `26072b7f8e25e2a5b1092b6af45d47ae1c43cac8` passed on Windows PowerShell 5.1,
  Windows pwsh, Ubuntu pwsh, and macOS pwsh:
  https://github.com/Huangshier/agent-ecosystem/actions/runs/25841179794
- Post-`v0.4.3` closeout write-scope, cross-workspace, `/goal` evidence,
  high-risk evidence, bootstrap analyze, and memory-scope language governance
  guardrails have landed through issues #65, #66, #68, and #69.
- PR base guard and release-validation concurrency are present.
- Root `.agents/` is checkout-local runtime memory and untracked.
- The Simplified Chinese homepage is `README.md`; `README.en.md` remains the
  English entrypoint.
- Domain-pack governance lifecycle is documented without enabling profile
  expansion or new public domain packs.
- Body-level project-memory language audit and `en` / `zh-CN` migration review
  flow validation are covered.
- Completed `docs/specs/**` work-package state was reconciled, and #23 remains
  a deferred next-version planning umbrella.
- Public release notes are present at `docs/releases/v0.4.4.md` as bilingual
  published release notes.
- `v0.4.4` final local release validation passed with
  `PASS=51 FAIL=0 WARN=0 DEFERRED=0`.
- Final hosted Release validation for the published `v0.4.4` tag target
  `71fabb372a4cbc024f07c920a0c17b903a77afc2` passed on Windows PowerShell 5.1,
  Windows pwsh, Ubuntu pwsh, and macOS pwsh:
  https://github.com/Huangshier/agent-ecosystem/actions/runs/26269908157
- GitHub Release `v0.4.4` has been published:
  https://github.com/Huangshier/agent-ecosystem/releases/tag/v0.4.4

- Old-release upgrade support matrix defines supported direct (`v0.4.2`–`v0.4.6`),
  best-effort (`v0.3.x`–`v0.4.1`), and unsupported (`v0.1.0`, `v0.2.0`) categories
  with expected upgrade paths and validation steps.
- Old-release upgrade path documentation covers runtime install upgrade
  (same-machine refresh, copy mode, link/junction mode), project memory upgrade
  (analyze/plan/apply/validate), fresh-machine install, and manifest verification.
- `v0.4.6` → current `main` old-release upgrade rehearsal passed: runtime install
  upgrade, project memory analyze (0 findings), hub lock in-sync, context gate,
  and memory diagnosis (0 findings).
- Release process requires at least one old-release upgrade rehearsal before
  tagging releases that change the install contract, template structure, or
  project memory schema.
- Old-release rehearsal evidence is recorded in
  `docs/old-release-rehearsal-evidence.md`.
- Public release notes are present at `docs/releases/v0.5.1.md` as bilingual
  published release notes.
- `v0.5.1` final local release validation passed with
  `PASS=62 FAIL=0 WARN=0 DEFERRED=0`.
- Release validator thin-entrypoint closeout: `scripts/validate-release.ps1`
  refactored from 2,496 lines to 566 lines with 10 extracted validation helper
  modules; 62 checks preserved with identical output contract.
- Memory governance hardened: structural diagnostics design, phase-close
  integration, completed-list growth detection, stable notes preservation, and
  template governance guidance.
- Public-safe write authorization boundaries clarified in public governance
  documentation.
- Testing capability foundations established: TDD and test-strategy patterns,
  test workflow command cards, testing conventions, and workflow-spec-lite test
  guidance.

## v0.4.5 Published State

Current `main` includes the post-`v0.4.4` maintenance / compatibility /
governance changes summarized in `docs/releases/v0.4.5.md`. `v0.4.5` has
been tagged and published as a public release.

GitHub Release `v0.4.5` has been published:
https://github.com/Huangshier/agent-ecosystem/releases/tag/v0.4.5

Tag target: PR #110 merge commit.

## v0.4.6 Published State

Current `main` includes the post-`v0.4.5` documentation / governance /
release-hygiene changes summarized in `docs/releases/v0.4.6.md`. `v0.4.6` has
been tagged and published as a public release.

GitHub Release `v0.4.6` has been published:
https://github.com/Huangshier/agent-ecosystem/releases/tag/v0.4.6

Tag target: merge commit for the `v0.4.6` publish-finalization PR.

Local release validation for this alignment passed with
`PASS=54 FAIL=0 WARN=0 DEFERRED=0`.

## Required Before Future Publishing

- Re-run the final sensitive information audit if review changes the public tree.
- Re-run `scripts/validate-release.ps1` if installer, skill, template, release
  documentation, or audit rules change during review.
- Review the final local diff.
- Maintainer authorization to publish starts release-finalization alignment; it
  does not authorize an immediate tag or GitHub Release.
- Before creating a future tag or GitHub Release, align `README.md`,
  `README.en.md`, release notes, release readiness, and the release notes index
  to the target version, then run
  `scripts/validate-release.ps1 -TargetVersion <target-version>`.
- Push, tag, and publish release notes only after finalization alignment and
  release validation pass.

## Current Quick Start

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -Profile recommended
```

Safe validation form:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -Profile recommended -TargetDir <temp-runtime> -Copy -Force
```

Full release validation form:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-release.ps1 -ScratchRoot <scratch-root>
```

Machine-readable output form:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-release.ps1 -ScratchRoot <scratch-root> -Json
```

Use `pwsh -NoProfile -File` with the same arguments on non-Windows systems or
when PowerShell 7+ is already available.

## Installer Metadata

By default, the installer prefers link-based installs: `Junction` on Windows
and `SymbolicLink` on other platforms. If link creation fails, it falls back to
copy mode for that item.

The generated `install-manifest.json` is runtime metadata. It records the
selected profile, skill names, whether link mode was preferred, and each
installed item's final mode (`junction`, `symboliclink`, `copy`, or
`copy-fallback`).

`scripts/uninstall.ps1` uses that manifest as the only automatic cleanup
authority. It removes manifest-listed install destinations and the manifest,
preserves unknown runtime files, and prints manual cleanup guidance without
removing anything when the manifest is missing.

## Suggested Public Audit

Before publishing, scan the public tree for high-risk path and credential
patterns, then review any keyword matches manually. Security policy and audit
documentation may intentionally contain safety terms.

The release validator automates the current audit baseline and records a
machine-readable result in the scratch directory.

## Hardened Validation Coverage

The release validator now covers:

- profile matrix installs in copy and link modes
- recommended runtime smoke for copy and link installs
- no-`-Force` conflict behavior and forced reinstall behavior
- manifest-based uninstall behavior with unknown runtime files preserved
- context gate JSON performance with 500 generated context files
- cross-platform shell strategy docs aligned with CI shell coverage
- `hub.lock` drift checking with a temporary git-backed hub
- hub initialization Git mode coverage, ensuring default hub initialization
  does not create nested Git repositories
- experience promote -> rebuild -> search closure using a temporary hub copy
- no-op experience index rebuild coverage that preserves registry file hashes
- knowledge catalog coverage for experience, patterns, and standards
- public domain-pack catalog coverage
- duplicate helper hashes, shared helper wiring, parser checks, JSON parsing,
  public structure, sensitive-pattern audit, and language policy templates
- Windows PowerShell 5.1-compatible encoding for non-ASCII PowerShell scripts
- first-session language write coverage for English and Simplified Chinese
  temporary projects
- project-bootstrap operating-mode coverage for safe refresh, compatibility
  overwrite warnings, and backup-first force reset
- conservative project-memory language migration coverage for both `en` to
  `zh-CN` and `zh-CN` to `en`, mixed memory, project-specific preservation,
  proposal-first apply, backup-first apply, and narrative migration routing
- read-only body-level project-memory language audit coverage for
  metadata/body mismatches, fenced code, protected literals, and mixed
  narrative fixtures
- workflow-spec-lite validator positive/negative fixtures
- anti-drift template and memory-governance coverage
- validation scratch retention pruning dry-run/apply behavior
- adoption guide and minimal project example coverage
- v0.2.0 release notes coverage
- localized context discovery headings for memory diagnosis and upgrade
  analysis
- bilingual public/private routing documentation coverage
- v0.3.0 release notes coverage
- v0.3.1 release notes coverage
- v0.4.0 release notes coverage
- v0.4.1 release notes coverage
- v0.4.2 release notes coverage
- v0.4.3 release notes coverage
- v0.4.4 published release notes coverage
- publish-ready release metadata alignment coverage
- v0.4.5 published release notes coverage
- v0.4.6 published release notes coverage
- legacy template-path reference audit coverage
- existing project upgrade path coverage
- old-release upgrade support matrix and path documentation
- old-release rehearsal evidence for `v0.4.6` → current `main`
- release process old-release upgrade rehearsal requirement
