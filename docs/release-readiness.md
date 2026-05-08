# Release Readiness

Status: `v0.2.0` release candidate.

The initial public release has been published as `v0.1.0`; `v0.2.0` closes the
public migration work and moves the project toward normal maintenance.

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
- `full` and `dev` are documented as `v0.1.0` placeholders that currently
  install the same public content as `recommended`.
- Recommended profile has been validated against a temporary runtime in copy mode.
- Recommended profile has been smoke-tested by bootstrapping a new project from
  a temporary runtime install.
- First public release version selected: `v0.1.0`.
- First public Chinese documentation ships as `README.zh-CN.md`.
- Reusable release validation is available at `scripts/validate-release.ps1`.
- Release process guidance is available at `docs/release-process.md`.
- Latest local hardened release validation passed with 21 checks passing, no
  failures, warnings, or deferred checks.
- Duplicate experience-maintenance helpers have been reviewed:
  `project-bootstrap` keeps compatibility copies, while `knowledge-hub/scripts`
  is the preferred runtime maintenance entrypoint.
- The initial public experience entry is documented as a public-safe reindexed
  backfill with local source paths intentionally omitted from `index.json`.
- Installer fallback metadata behavior is documented: the runtime
  `install-manifest.json` records the install mode used for each item.
- Latest local high-risk public audit found no matches, and public PowerShell
  scripts parsed successfully.
- CI release validation workflow is present at
  `.github/workflows/release-validation.yml` and is configured for Windows,
  Ubuntu, and macOS runners.
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
- `workflow-spec-lite` includes a read-only spec validator that checks goals,
  non-goals, risks, acceptance evidence, and Execution Contract stop rules.
- Spec templates and memory-governance guidance include scope drift, unrelated
  refactor, and skipped acceptance protections.
- Knowledge catalog coverage includes the `embedded-core` domain pack scaffold.
- Public adoption surface includes `docs/how-to-adapt.md` and
  `examples/minimal-project/`.
- Public release notes are present at `docs/releases/v0.2.0.md`.

## Required Before Future Publishing

- Re-run the final sensitive information audit if review changes the public tree.
- Re-run `scripts/validate-release.ps1` if installer, skill, template, release
  documentation, or audit rules change during review.
- Review the final local diff.
- Push, tag, and publish release notes only after maintainer approval.

## Current Quick Start

```powershell
.\scripts\install.ps1 -Profile recommended
```

Safe validation form:

```powershell
.\scripts\install.ps1 -Profile recommended -TargetDir <temp-runtime> -Copy -Force
```

Full release validation form:

```powershell
pwsh -NoProfile -File .\scripts\validate-release.ps1 -ScratchRoot <scratch-root>
```

Machine-readable output form:

```powershell
pwsh -NoProfile -File .\scripts\validate-release.ps1 -ScratchRoot <scratch-root> -Json
```

## Installer Metadata

By default, the installer prefers link-based installs: `Junction` on Windows
and `SymbolicLink` on other platforms. If link creation fails, it falls back to
copy mode for that item.

The generated `install-manifest.json` is runtime metadata. It records the
selected profile, skill names, whether link mode was preferred, and each
installed item's final mode (`junction`, `symboliclink`, `copy`, or
`copy-fallback`).

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
- `hub.lock` drift checking with a temporary git-backed hub
- experience promote -> rebuild -> search closure using a temporary hub copy
- knowledge catalog coverage for experience, patterns, and standards
- public domain-pack catalog coverage
- duplicate helper hashes, parser checks, JSON parsing, public structure,
  sensitive-pattern audit, and language policy templates
- first-session language write coverage for English and Simplified Chinese
  temporary projects
- workflow-spec-lite validator positive/negative fixtures
- anti-drift template and memory-governance coverage
- adoption guide and minimal project example coverage
- v0.2.0 release notes coverage
