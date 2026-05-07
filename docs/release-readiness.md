# Release Readiness

Status: local `v0.1.0` release candidate preparation.

Push, tag, and release publication are pending maintainer review.

## Completed

- Workflow Kernel skills are present under `skills/`.
- Kernel skill metadata includes `category`, `stability`, and `scope`.
- Public knowledge hub templates and selected generic maintenance scripts are present.
- One public-safe workflow experience entry is indexed.
- Public installer supports `minimal`, `recommended`, `full`, and `dev` profiles.
- Recommended profile has been validated against a temporary runtime in copy mode.
- Recommended profile has been smoke-tested by bootstrapping a new project from
  a temporary runtime install.
- First public release version selected: `v0.1.0`.
- First public Chinese documentation ships as `README.zh-CN.md`.
- Reusable release validation is available at `scripts/validate-release.ps1`.
- Release process guidance is available at `docs/release-process.md`.
- Latest local release validation for the `v0.1.0` candidate passed with
  12 checks passing, no failures, and one deferred non-blocking behavior check.
- Duplicate experience-maintenance helpers have been reviewed:
  `project-bootstrap` keeps compatibility copies, while `knowledge-hub/scripts`
  is the preferred runtime maintenance entrypoint.
- Installer fallback metadata behavior is documented: the runtime
  `install-manifest.json` records the install mode used for each item.
- Latest local high-risk public audit found no matches, and public PowerShell
  scripts parsed successfully.

## Required Before Publishing

- Re-run the final sensitive information audit if review changes the public tree.
- Re-run `scripts/validate-release.ps1` if installer, skill, template, release
  documentation, or audit rules change during review.
- Review the final local diff.
- Push, tag `v0.1.0`, and publish release notes only after maintainer approval.

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
.\scripts\validate-release.ps1 -ScratchRoot <scratch-root>
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
