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

Classify a pull request or explicit path set before choosing validation cost:

```powershell
.\validate-change.ps1 -BaseRef origin/main -HeadRef HEAD
.\validate-change.ps1 -ChangedPath README.md,scripts/install.ps1 -Json
```

The centralized Tier 0–3 contract and hosted-cost examples are documented in
[`docs/pr-validation-risk-tiers.md`](../docs/pr-validation-risk-tiers.md).
`validate-release.ps1` remains the complete Tier 3 and release-boundary entrypoint.

Explicitly bridge installed-copy skills into an agent client's verified skill
directory:

```powershell
.\link-agent-skills.ps1 -RuntimeDir <runtime> -AgentSkillsDir <agent-skills-dir> -Skill project-bootstrap
```

This helper is separate from ordinary installation. See
[`docs/agent-skill-bridge.md`](../docs/agent-skill-bridge.md) for its full
preflight and local metadata contract.

Manifest-based uninstall:

```powershell
.\uninstall.ps1 -TargetDir <runtime>
```

Read-only runtime manifest status:

```powershell
.\status.ps1
.\status.ps1 -RuntimeDir <runtime>
.\status.ps1 -RuntimeDir <runtime> -Json
```

The status command reads `install-manifest.json` once and emits a schema-1
payload or a text view derived from that payload. It does not install, repair,
refresh, scan managed files, access the network, or write runtime content.
`manifest_status = current` means only that the schema-2 manifest contract is
valid; it does not mean the runtime matches the latest Release or has no live
conflicts. Missing Git provenance, including installs from GitHub Release source
archives, is reported as `not-recorded` rather than guessed. Bridge health,
project drift, managed conflicts, and recommended actions are not included yet;
future sections must extend the same payload model instead of reparsing the
manifest.

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
- Schema-1 copy manifests have no trusted per-file baseline. A differing target
  conflicts and keeps schema 1 until `-ReplaceManaged` explicitly completes the
  migration.
- Profile reduction removes an excluded managed item only when its recorded
  files are unchanged and no nested unknown files exist. Otherwise the item and
  baseline remain in the manifest as a conflict, including with `-AllowPartial`.
- Unknown files are preserved. Locally modified managed files are skipped;
  simultaneous source and local changes are conflicts.
- `-AllowPartial` accepts skipped conflicts without changing the report's
  `conflict` status. `-ReplaceManaged` replaces managed files but preserves
  unknown files. Deprecated `-Force` maps to `-ReplaceManaged` and prints a
  compatibility warning.

The generated schema-2 `install-manifest.json` records the selected profile,
actual install strategy, runtime-relative managed items, source/installed
content hashes, and nullable source provenance. `source_commit` is recorded only
for a clean Git worktree whose selected runtime content matches `HEAD`;
`release_version` additionally requires exactly one matching `vX.Y.Z` tag at
that commit. Non-Git and dirty sources leave both fields `null`. The independent
schema-1 `install-report.json` records status,
counts, and complete runtime-relative lists for updated, unchanged, preserved
unknown, skipped locally modified, and conflicting files. Do not commit
generated runtime directories or their metadata to project repositories.

The current uninstaller reads schema-1 absolute or schema-2 runtime-relative
item destinations. Before deleting anything, schema-2 copy items are checked
for nested unknown files and locally modified managed files; either finding
blocks the whole uninstall and preserves runtime content plus installer
metadata. Clean schema-2 copy items and dev links keep the basic uninstall path.
Schema-1 manifests retain legacy item-boundary behavior without file-level
unknown protection. A fuller uninstall report and selective cleanup contract is
still deferred to a separate follow-up.

Helper layout:

- `lib/path-guard.ps1`: shared path joining and safety guards.
- `link-agent-skills.ps1`: explicit installed-copy to agent-specific skill
  directory bridge.
- `validation/release-test-helper.ps1`: common helper functions used by the
  release validator.

PowerShell helper ownership is documented in
`docs/powershell-helper-ownership.md`. Repository maintenance scripts may
dot-source `scripts/lib/path-guard.ps1`; installed skill and knowledge-hub
runtime scripts must remain usable without a source checkout, so some local
helper copies are intentional until a packaged runtime helper contract exists.
