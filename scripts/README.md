# Scripts

Installer and maintenance scripts live here.

Public installer entrypoint:

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

Install modes:

- Default mode prefers links: `Junction` on Windows and `SymbolicLink` on other
  platforms.
- `-Copy` forces copy mode and is recommended for temporary-runtime validation.
- If default link creation fails, the installer falls back to copy mode for that
  item.

The generated `install-manifest.json` is runtime metadata. It records the
selected profile, installed skills, whether link mode was preferred, and each
item's final install mode.
