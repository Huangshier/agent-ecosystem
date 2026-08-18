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

Use the classifier-owned local plan instead of manually composing validators:

```powershell
.\invoke-local-validation.ps1 -Stage iteration -BaseRef origin/main -HeadRef HEAD -DryRun
.\invoke-local-validation.ps1 -Stage pre-push -BaseRef origin/main -HeadRef HEAD
.\invoke-local-validation.ps1 -Stage release -ChangedPath CHANGELOG.md
```

`iteration` never invokes the full release validator. `pre-push` runs affected
checks for Tier 0-2 and preserves the PowerShell 7.6 validation full boundary
for Tier 3. `release` always preserves that single-host full validation
boundary. `-DryRun -Json` reports each command, host, suite, reason, skipped
action, and non-negative observational timing without executing validation.
Executed stages checkpoint `local-validation-result.json` after every completed
action so a caller timeout does not erase earlier evidence.

The classifier, local-plan orchestrator, and normative repository validation
entrypoints use the C3.3 PowerShell Core 7.6 control plane through
`pwsh -NoProfile -NonInteractive -File` without a `powershell.exe` fallback.
The default cutover has completed: the installer, Runtime, bootstrap, bridge,
status, uninstall, and Skill execution contracts documented in this file now
reflect the active C3.3 Runtime authority (`project-bootstrap` +
`project-workspace`). Earlier Slice A0 transitional surfaces have been
migrated or retired by the cutover; this is not a commitment to long-lived
dual-host or dual-semantics support.

The heavyweight classifier regression entrypoint is
`test-heavy-targeted-regression.ps1`; `test-validate-change.ps1` remains the
lightweight routing-contract entrypoint. The complete sensitive scan fixture
runs only from the heavy self-protection path when validation control surface
paths change; the classifier still performs the real PR diff scan.

Slice A provides the read-only project asset parser and its self-contained
fixture suite:

```powershell
pwsh -NoProfile -NonInteractive -File .\skills\project-workspace\scripts\read-project-assets.ps1 -ProjectRoot <project-root> -Json
pwsh -NoProfile -NonInteractive -File .\scripts\test-project-workspace-parser.ps1 -Json
```

The parser reads only YAML frontmatter at the four canonical asset roots. It
does not execute Markdown bodies, write assets, migrate projects, join the
installer or bootstrap flow, or expose a discoverable `SKILL.md` entrypoint.

The schemas use JSON Schema Draft 2020-12 syntax. The read-only parser deterministically enforces the repository-owned subset used by the four canonical asset schemas; it is not a general-purpose Draft 2020-12 validator.

The centralized Tier 0–3 contract and hosted-cost examples are documented in
[`docs/pr-validation-risk-tiers.md`](../docs/pr-validation-risk-tiers.md).
`validate-release.ps1` remains the authoritative validator and accepts
`-ValidationShard Full`, `PlatformNeutral`, `RuntimePlatform`,
`RepositoryCheckpoint`, `RepositoryCheckpointNeutral`, or
`RepositoryCheckpointRuntime`. Hosted Tier 3
pull-request validation runs the classifier-selected affected suites and the
independent self-protection oracle when required. Pushes to `main` use the
thin `validate-main-health.ps1` entrypoint; manual dispatch and release
checkpoints retain the complete validator on every required host.

Explicitly bridge installed-copy skills into an agent client's verified skill
directory:

```powershell
.\link-agent-skills.ps1 -RuntimeDir <runtime> -AgentSkillsDir <agent-skills-dir> -Skill project-bootstrap,project-workspace
```

This helper is separate from ordinary installation. See
[`docs/agent-skill-bridge.md`](../docs/agent-skill-bridge.md) for its full
preflight and local metadata contract.

Manifest-based uninstall:

```powershell
.\uninstall.ps1 -TargetDir <runtime>
```

Read-only runtime and Agent skill bridge status:

```powershell
.\status.ps1
.\status.ps1 -RuntimeDir <runtime>
.\status.ps1 -RuntimeDir <runtime> -ProjectDir <project-root>
.\status.ps1 -RuntimeDir <runtime> -Json
```

The status command reads `install-manifest.json` once and emits a schema-1
payload or a text view derived from that payload. When local bridge metadata is
present, it also reads `agent-skill-bridge-manifest.json` once and verifies only
the links explicitly managed there against runtime ownership and live link
state. It does not auto-discover agent clients or scan client skill directories.
It does not install, create, repair, refresh, rebuild, or delete links; scan
managed files; access the network; or write runtime or client content.
`manifest_status = current` means only that the recognized schema-2 runtime
status fields are valid. It does not mean the runtime matches the latest
Release, that managed files are unchanged, or that no live conflicts exist; the
command does not scan managed files. Missing Git provenance, including installs
from GitHub Release source archives, is reported as `not-recorded` rather than
guessed. Bridge status is `not-configured` only when this runtime has no bridge
manifest; it does not claim that manually created links do not exist. Bridge
records report `current`, `stale`, `broken`, `conflict`, or `unknown` without
exposing runtime, source, target, manifest, or home-directory paths. Bridge
health proves only the recorded filesystem discovery chain, not complete client
compatibility. Project status is opt-in through `-ProjectDir`; without it,
`project.status` is `unknown` with reason `not-requested`, and the command never
discovers or scans a project from the current directory. Under the active C3.3
Runtime authority, the top-level `project.status` follows the
`project.workspace` result: the workspace section is the active Project status
authority, and `project.baseline` / `project.memory` keep their schema-1 shape
but no longer drive the top-level status. It reports only stable status,
reason, language, counts, and finding codes; project paths, hub Git identity,
hashes, and raw helper output are never copied into the payload. The legacy
hub-lock machine contract, memory upgrade Analyze mode, and memory diagnostics
remain available only for non-C3.3 (legacy) runtimes as a compatibility path;
they are not part of the active C3.3 Project status default. After the runtime,
managed-file, bridge, and project sections are populated,
`recommended_next_action` is derived once from that same payload by a linear
first-match rule chain. The first matching manifest, managed-file, bridge, or
project rule wins; unrecognized or malformed state conservatively maps to
`inspect-manually`.
`not-configured` bridge state and project `unknown / not-requested` are neutral,
and missing provenance marked `not-recorded` does not imply reinstallation.
The recommendation is an enum-only read-only result: the command never executes
it or emits a command, path, URL, parameter, or free-text instruction for it.

For schema-2 copy runtimes, `runtime.managed_files` checks only files explicitly
recorded under managed copy items in `install-manifest.json`. It does not scan
unrecorded files or recursively inventory managed directories. `modified` means
the live file differs from an unchanged recorded installed/source baseline;
`conflict` means the manifest already records source/installed divergence or a
managed path is occupied by non-regular content. Managed file parents must
resolve exactly to their lexical location inside the owning item root; aliases
are never followed to hash a target file. Empty managed items still validate
their item root, so missing, non-directory, linked, or unresolvable roots affect
the section status even when `tracked_file_count` is zero. Development-link
runtimes are `unknown` because the source root is not recorded, and status does
not guess it.
This inspection is read-only: it does not repair or reinstall the runtime,
access a source repository, or use the network. `install-report.json` is an
installation result, not durable current-state authority.

Context gate benchmark:

```powershell
.\benchmark-context-gate.ps1 -ContextFileCount 500 -MaxSeconds 30
```

Profiles:

- `minimal`: `project-bootstrap` plus the public knowledge hub; a fresh
  bootstrap produces a minimal C3.3 workspace.
- `recommended`: the active C3.3 Runtime (`project-bootstrap` +
  `project-workspace`), project workspace templates/schemas, and the public
  knowledge hub.
- `full`: currently the same public skill set as `recommended`.
- `dev`: currently the same public skill set as `recommended`, intended for
  future development helpers.

`recommended` / `full` / `dev` are the only post-cutover C3.3 Runtime authority;
there is no `c3-3-candidate` profile and no compatibility alias. The retired
`project-context-gate`, `memory-governance`, and `workflow-spec-lite` Skills are
no longer installed or newly bridged.

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
