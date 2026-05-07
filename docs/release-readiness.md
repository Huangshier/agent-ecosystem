# Release Readiness

Status: not release-ready yet.

## Completed

- Workflow Kernel skills are present under `skills/`.
- Kernel skill metadata includes `category`, `stability`, and `scope`.
- Public knowledge hub templates and selected generic maintenance scripts are present.
- One public-safe workflow experience entry is indexed.
- Public installer supports `minimal`, `recommended`, `full`, and `dev` profiles.
- Recommended profile has been validated against a temporary runtime in copy mode.

## Required Before First Public Release

- Decide the first public version number.
- Decide whether Chinese public documentation ships in the first release.
- Run a final sensitive information audit over the public tree.
- Run a bootstrap smoke test from a temporary runtime install.
- Review duplicated knowledge-hub helper scripts in `project-bootstrap` assets
  and top-level `knowledge-hub/scripts`.
- Confirm installer link/junction fallback metadata behavior.

## Current Quick Start Preview

```powershell
.\scripts\install.ps1 -Profile recommended
```

Safe validation form:

```powershell
.\scripts\install.ps1 -Profile recommended -TargetDir <temp-runtime> -Copy -Force
```
