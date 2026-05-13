# Release Process

This process keeps public releases repeatable while keeping private migration
state, sensitive audit details, and local runtime paths out of the public
repository.

## Release Gate

Run the release validation gate before any push, tag, or published release:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-release.ps1 -ScratchRoot <scratch-root>
```

Use a scratch directory outside the live runtime. The validator refuses to use
the current user's `$HOME\.agents` runtime path. It writes an
`install-manifest.json` for each temporary install and a final
`validation-result.json` under the scratch directory.
Windows PowerShell 5.1 is supported. On non-Windows systems, or when PowerShell
7+ is already available, use `pwsh -NoProfile -File` with the same script
arguments. The Windows `-ExecutionPolicy Bypass` flag is process-scoped and
helps when local execution policy or Mark-of-the-Web blocks downloaded scripts.
See [Shell strategy](shell-strategy.md) for the current non-PowerShell policy:
the public release line does not ship Bash or Zsh wrappers yet, and future
wrappers should delegate to the canonical `.ps1` scripts through `pwsh`.

When a maintainer intentionally reuses a persistent scratch parent, inspect
retention before deleting anything:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\prune-validation-scratch.ps1 -ScratchRoot <scratch-parent> -RetainLatest 10
```

The pruning helper is a dry run by default. Add `-Apply` only after reviewing
the evidence. It only considers direct child directories that contain
`validation-result.json`, rejects live runtime and repository-root targets, and
emits JSON evidence with `-Json`.

The validator checks:

- public repository structure and release documentation entrypoints
- Workflow Kernel skill metadata
- installer profile matrix for `minimal`, `recommended`, `full`, and `dev`
- copy mode and default link/junction mode installs
- runtime smoke coverage for bootstrap, context gate, workflow spec creation,
  and memory diagnosis in both recommended copy and link installs
- installer no-`-Force` conflict behavior and forced reinstall behavior
- hub initialization Git mode, including default no-Git behavior and explicit
  Git initialization
- `hub.lock` in-sync, missing-lock, invalid-hub, drift, and multi-project
  batch checking against temporary git-backed hubs
- memory upgrade Analyze, Plan, and Apply flow against a temporary project
- knowledge catalog, pattern, and standard entry coverage
- public domain-pack catalog coverage
- public experience index search
- experience promotion, index rebuild, and search closure against a temporary
  hub copy
- no-op experience index rebuilds that preserve registry file hashes
- PowerShell parser checks and JSON parsing
- Windows PowerShell 5.1-compatible encoding for non-ASCII PowerShell scripts
- public sensitive-pattern audit
- duplicate helper script hashes
- language policy template coverage in both repository guidance and bootstrap
  output
- first-session language write capability for English and Simplified Chinese
  temporary projects, driven by an explicit `-ProjectLanguage` value supplied by
  the agent or workflow
- conservative project-memory language migration between `en` and `zh-CN`,
  including proposal-first, backup-first, apply, validate, mixed-memory, and
  project-specific preservation fixtures
- project-bootstrap operating modes, including missing-template refresh,
  unmodified-template refresh, compatibility overwrite warnings, and
  backup-first force reset behavior
- localized context discovery headings in memory diagnosis and upgrade analysis
- bilingual public/private routing guidance in language policy and bundled
  knowledge assets
- workflow-spec-lite spec validation against complete, Loop Contract,
  Simplified Chinese, and intentionally broken fixtures
- anti-drift template and memory-governance coverage for scope drift, unrelated
  refactors, and skipped acceptance checks
- validation scratch retention pruning dry-run/apply behavior
- adoption guide and minimal project example coverage
- v0.2.0 release notes coverage
- v0.3.0 release notes coverage
- v0.3.1 release notes coverage
- v0.4.0 release notes coverage
- v0.4.1 release notes coverage
- v0.4.2 release notes coverage
- legacy template-path reference audit coverage

## CI Gate

The repository also runs `.github/workflows/release-validation.yml` on pushes to
`main`, pull requests, and manual dispatch. The workflow executes the same
validator with PowerShell 7+ (`pwsh`) on:

- `windows-latest`
- `ubuntu-latest`
- `macos-latest`

It also runs the validator on `windows-latest` with Windows PowerShell 5.1
(`shell: powershell`) to keep the Windows bare-machine path covered.

Each job uploads the validator scratch directory as evidence. Treat CI failures
as release blockers unless the maintainer explicitly records a platform-specific
deferral for a pre-release calibration run.

Validation-sensitive text files are LF-normalized by `.gitattributes` so
content hashes in the experience registry are stable on hosted Windows, Ubuntu,
and macOS runners.

Deferred checks are allowed only when the capability does not exist yet. The
release validator should report zero deferred checks for a publishable release
unless a maintainer explicitly records a new deferral.

## Public Reader Review

For public-facing documentation and release metadata changes, include a short
reader-oriented review before merging:

- **First-time reader**: the README and docs index explain what the project is,
  what it is not, and where to go next.
- **Current release**: current docs do not rely on stale first-release framing
  when describing the active release line.
- **Validation summary**: release notes and readiness docs do not disagree with
  the validator output or with each other.
- **Public boundary**: docs do not include private overlay details, local
  migration state, machine-specific paths, or private review material.
- **Cross-platform onboarding**: PowerShell-first expectations are visible to
  non-Windows readers, with `pwsh` guidance where appropriate.

This review is intentionally lightweight. It is a checklist for adoption
surfaces, not a separate approval process.

## Validation Tiers

The required hosted release validation checks remain the hard merge gate for
pull requests to `main`. Pull requests must also report validation evidence in
the PR body. The tiers below guide local validation depth before opening or
updating a PR; they do not weaken the hosted checks, and maintainers may ask for
more validation when risk is unclear.

When a change spans multiple categories, use the highest tier that applies.

| Tier | Change type | Local validation expectation |
|---|---|---|
| 0 | Issue or PR metadata only, such as labels, comments, issue routing, or branch cleanup with no repository diff | Read back the GitHub state that changed. No local repository validation is needed unless files changed. |
| 1 | Low-risk text-only docs that do not affect README entrypoints, governance, release process, release notes, tracked `.agents` memory, scripts, installer behavior, CI, or generated runtime behavior | Run `git diff --check` and review links or changed prose manually. |
| 2 | Public adoption docs, README entrypoints, governance docs, release process docs, release notes, release readiness, tracked `.agents` memory, specs, issue/PR templates, or public/private boundary wording | Run `git diff --check`, the public reader review when relevant, and the full local release validator. |
| 3 | PowerShell scripts, installer or uninstaller behavior, release validator behavior, CI workflow files, skill metadata, knowledge hub generation/search behavior, templates that affect generated project memory, or release packaging | Run `git diff --check`, targeted parser or smoke checks for the changed surface, and the full local release validator before PR review. |

Release publication still requires the full release gate and maintainer
approval. Repository settings, secrets, GitHub App permissions, rulesets, and
release publishing are maintainer-controlled actions, not agent-only validation
tiers.

## Publishing Steps

1. Start from a clean local review branch or a clearly understood local diff.
2. Run the release validation gate with a temporary scratch directory.
3. Run the public reader review when the diff changes README, docs entrypoints,
   release notes, or release process text.
4. Review `validation-result.json` and any public diff.
5. Open or update a pull request when using CI for release review.
6. Confirm the release validation workflow passes on Windows, Ubuntu, and macOS.
7. Record only public-safe release status in this repository.
8. Push, tag, and publish release notes only after maintainer approval.

Do not publish if the validator reports a failed check. Fix the public tree or
record the release-blocking decision in private migration state, then rerun the
gate.

## Public Records

Public release records should describe the validation surface and final status.
Do not include local machine paths, private repository mappings, raw sensitive
audit findings, or private overlay details.
