# Project workspace continuity fixtures

`cases.json` lists the focused Slice C scenarios for Work CRUD, revision CAS,
four-class recovery, multi-Work isolation, and the existing Catalog/check
authority boundary. The verifier creates disposable projects under an isolated
scratch root and reuses the canonical workspace parser and Git helpers.

Run from the repository root with PowerShell 7.6:

```powershell
pwsh -NoProfile -File scripts/validation/project-workspace-continuity-checks.ps1 -Json
```
