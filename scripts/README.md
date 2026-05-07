# Scripts

Installer and maintenance scripts live here.

Public entrypoint:

```powershell
.\install.ps1 -Profile recommended
```

Useful validation form:

```powershell
.\install.ps1 -Profile recommended -TargetDir <temp-runtime> -Copy -Force
```

Profiles:

- `minimal`: `project-bootstrap` plus the public knowledge hub.
- `recommended`: the Workflow Kernel plus the public knowledge hub.
- `full`: currently the same public skill set as `recommended`.
- `dev`: currently the same public skill set as `recommended`, intended for
  future development helpers.
