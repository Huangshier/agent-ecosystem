# Scripts

Installer and maintenance scripts live here.

Public installer entrypoint:

```powershell
.\install.ps1 -Profile recommended
```

Useful validation form:

```powershell
.\install.ps1 -Profile recommended -TargetDir <temp-runtime>
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

Install modes and reruns:

- Default mode is copy-first. It creates an independent runtime and never links
  ordinary installs back to the source checkout.
- `-Copy` remains a compatible explicit spelling of the default behavior.
- `-DevLink` explicitly creates `Junction` items on Windows and `SymbolicLink`
  items on other platforms for contributor workflows.
- Reruns restore missing managed files, update source-changed files whose
  installed content is unchanged, and avoid rewriting unchanged files.
- Unknown files are preserved. Locally modified managed files are skipped;
  simultaneous source and local changes are conflicts.
- `-AllowPartial` accepts skipped conflicts without changing the report's
  `conflict` status. `-ReplaceManaged` replaces managed files but preserves
  unknown files. Deprecated `-Force` maps to `-ReplaceManaged` and prints a
  compatibility warning.

The generated schema-2 `install-manifest.json` records the selected profile,
actual install strategy, runtime-relative managed items, and source/installed
content hashes. The independent schema-1 `install-report.json` records status,
counts, and complete runtime-relative lists for updated, unchanged, preserved
unknown, skipped locally modified, and conflicting files. Do not commit
generated runtime directories or their metadata to project repositories.

The current uninstaller reads schema-1 absolute or schema-2 runtime-relative
item destinations, removes those destinations and installer metadata, and
prints manual cleanup guidance instead of deleting anything when the manifest
is missing. Its fuller copy-first local-modification and nested unknown-file
contract is intentionally deferred to a separate follow-up.

Helper layout:

- `lib/path-guard.ps1`: shared path joining and safety guards.
- `validation/release-test-helper.ps1`: common helper functions used by the
  release validator.

PowerShell helper ownership is documented in
`docs/powershell-helper-ownership.md`. Repository maintenance scripts may
dot-source `scripts/lib/path-guard.ps1`; installed skill and knowledge-hub
runtime scripts must remain usable without a source checkout, so some local
helper copies are intentional until a packaged runtime helper contract exists.
