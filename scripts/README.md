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

Manifest-based uninstall:

```powershell
.\uninstall.ps1 -TargetDir <runtime>
```

Context gate benchmark:

```powershell
.\benchmark-context-gate.ps1 -ContextFileCount 500 -MaxSeconds 30
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
Because this metadata includes local runtime and source paths, do not commit
generated runtime directories or manifests to project repositories.

The uninstaller reads `install-manifest.json` and removes only the destinations
listed there, then removes the manifest. It preserves unknown files and prints
manual cleanup guidance instead of deleting anything when the manifest is
missing.

Helper layout:

- `lib/path-guard.ps1`: shared path joining and safety guards.
- `validation/release-test-helper.ps1`: common helper functions used by the
  release validator.
