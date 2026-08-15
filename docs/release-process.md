# Release Process

This process keeps public releases repeatable while keeping private migration
state, sensitive audit details, and local runtime paths out of the public
repository.

## Release impact 与版本决策

每个拉取请求记录一个机器可读的决策字段：
`Release impact: none / patch / minor / major`。

下一版本类型取上一个已发布 Release 之后所有公开变更的最高影响级别，
不按拉取请求数量或固定日历决定。

- `none`：不单独触发 Release。
- `patch`：向后兼容修复，不改变公开默认架构或行为。
- `minor`：新增公开能力，或改变默认 Runtime、项目或安装器契约。
- `major`：重大稳定性或兼容性承诺，由 maintainer 显式决定。

在 `0.x` 阶段，重大不兼容变化至少按 `minor` 处理，并要求迁移或兼容性说明；
如果公开兼容性承诺需要，maintainer 可选择更高影响级别。

Release trigger 仅限：

1. 完整且可消费的功能或架构批次完成；
2. 需要及时交付的修复；或
3. maintainer 判断 `Unreleased` 已形成稳定点。

不按拉取请求数量或固定周期强制发布。普通治理类拉取请求不会仅因修改治理文本
就默认运行完整 Release 验证。通过
`scripts/invoke-local-validation.ps1` 在 `iteration` 和 `pre-push` 阶段执行
分类器选择的 affected-surface 路径；只有明确作出 Release/checkpoint 决定时才
使用 `release` stage 或完整验证。

## Release Gate

准备普通分支或拉取请求时使用 affected-surface 本地验证路径。对于明确的
Release/checkpoint，或创建 tag、发布 Release 之前，运行 Release validation
gate。进行可发布收尾时传入即将创建 tag 的版本号：

```powershell
pwsh -NoProfile -NonInteractive -File .\scripts\validate-release.ps1 -ScratchRoot <scratch-root> -TargetVersion <target-version>
```

Use a scratch directory outside the live runtime. The validator refuses to use
the current user's `$HOME\.agents` runtime path. It writes an
`install-manifest.json` plus `install-report.json` for each temporary install and a final
`validation-result.json` under the scratch directory.
The C3.3 validation control plane and normative repository validation
entrypoints, including this release validator, require PowerShell Core 7.6 or
later through `pwsh -NoProfile -NonInteractive -File`.

Slice A0 does not change the current v0.7.1 Runtime, installer, bootstrap,
bridge, or legacy Skill execution contracts. Those surfaces remain
transitional and will be migrated or retired only in their designated later
slices. This transition is not a commitment to long-lived dual-host or
dual-semantics support.

See [Shell strategy](shell-strategy.md) for the current non-PowerShell policy:
the public release line does not ship Bash or Zsh wrappers yet, and future
wrappers should delegate to the canonical `.ps1` scripts through `pwsh`.

When a maintainer intentionally reuses a persistent scratch parent, inspect
retention before deleting anything:

```powershell
pwsh -NoProfile -NonInteractive -File .\scripts\prune-validation-scratch.ps1 -ScratchRoot <scratch-parent> -RetainLatest 10
```

The pruning helper is a dry run by default. Add `-Apply` only after reviewing
the evidence. It only considers direct child directories that contain
`validation-result.json`, rejects live runtime and repository-root targets, and
emits JSON evidence with `-Json`.

The validator checks:

- public repository structure and release documentation entrypoints
- publish-ready release metadata alignment for the target version across
  `README.md`, `README.en.md`, release notes, release readiness, and the release
  notes index
- root `.agents/` runtime memory is not tracked, while generated/template
  `.agents` paths remain allowed
- public spec files avoid obvious volatile active-state records unless covered
  by historical evidence, stop-rule, or retrospective allowlists
- Workflow Kernel skill metadata
- installer profile matrix for `minimal`, `recommended`, `full`, and `dev`
- default copy installs and explicit development link/junction installs
- runtime smoke coverage for bootstrap, context gate, workflow spec creation,
  and memory diagnosis in both recommended copy and link installs
- incremental installer reruns, unknown/local-modified protection, conflict exit
  behavior, `-AllowPartial`, and managed replacement compatibility
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
- Claude Code hooks guardrails contract, executable lifecycle settings and
  runner, bundled snapshot, and public-safe deterministic stdin/stdout fixtures
- PowerShell parser checks and JSON parsing
- UTF-8 encoding for non-ASCII PowerShell scripts
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
- read-only body-level project-memory language audit coverage for
  metadata/body mismatches, fenced code, protected literals, and mixed
  narrative fixtures
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
- v0.4.3 release notes coverage
- v0.4.4 published release notes coverage
- target-version publish-ready alignment coverage
- legacy template-path reference audit coverage
- existing project upgrade path coverage

## CI Gate

The repository runs `.github/workflows/release-validation.yml` for pull
requests, pushes to `main`, and manual dispatches. These
events have deliberately different validation responsibilities:

| Surface | Responsibility | Hosted path |
|---|---|---|
| Pull request | Prove the diff and its affected behavior | Classifier-selected quick/affected suites, plus control-plane self-protection when required; validation-routing changes also execute the Windows main-health smoke; PR A's direct bootstrap regression remains on the affected path. |
| `main` push | Prove that the repository is healthy | One Windows `main health` job for PowerShell/JSON parsing, public-safe/sensitive scanning, and a small copy-install/bootstrap/C3.3 workspace smoke. |
| Release/checkpoint | Prove the complete publication surface | Manual runs retain the `RepositoryCheckpointNeutral` and `RepositoryCheckpointRuntime` validator shards, including the required cross-platform runtime matrix and release-only checks. |

The main health job is intentionally not a Release candidate. A `main` push
does not run the `PlatformNeutral` or three-platform `RuntimePlatform` release
shards and does not call the complete `scripts/validate-release.ps1` suite.
The fixed `validation gate` remains the single required result check. Main does
not run a lineage shadow, and ordinary PR jobs do not upload per-job evidence
manifests for a later aggregation step.

For pull requests, the deterministic classifier selects the affected suites
and the hosts declared by those suites. Changes to validation routing or
other validation control-plane surfaces also run an independent
self-protection oracle; validation-routing changes additionally execute the
Windows main-health smoke before merge. Other PRs do not run that job. See
[PR validation risk tiers](pr-validation-risk-tiers.md) for the authoritative
routing and conservative fallback rules.

The fixed `validation gate` evaluates the classifier-selected jobs and fails
closed when classification, required execution, or the conditional main-health
or self-protection result is incomplete. The classifier and the selected PR
validation jobs retain the direct exact-candidate identity checks; the gate
only aggregates job results. A complete hosted release-validation matrix is
not a per-PR hard gate.

Every `main` push runs only the thin main health contract and does not select a
Release profile. Manually dispatched runs use the broader `RepositoryCheckpoint`
profile for release
archive, governance, evaluation, benchmark, historical, and other
checkpoint-only assertions.

The workflow uses event-aware GitHub Actions concurrency. New pull-request and
manually dispatched runs may cancel an older same-event, same-ref run, while
every `push` to `main` has a unique concurrency identity.

Successful manual Release/checkpoint jobs upload explicit evidence allowlists,
while failed Release jobs preserve their complete scratch directory for
diagnosis. Ordinary PR validation is represented by job results and direct
candidate checks. Treat evaluator failures and other required CI failures as
release blockers unless the
maintainer explicitly records a platform-specific deferral for a pre-release
calibration run.

Validation-sensitive text files are LF-normalized by `.gitattributes` so
content hashes in the experience registry are stable on hosted Windows, Ubuntu,
and macOS runners.

Deferred checks are allowed only when the capability does not exist yet. The
release validator should report zero deferred checks for a publishable release
unless a maintainer explicitly records a new deferral.

The workflow keeps an always-run fixed `validation gate` instead of relying on
workflow-level path filters, which can leave required checks pending. Any
future routing change must preserve a fail-closed required gate and update this
process plus repository required-check settings in the same reviewed change.

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

The fixed hosted `validation gate` remains the fail-closed merge result for
pull requests to `main`. The classifier and selected validation jobs choose
which affected suites and hosts must satisfy that gate; skipped suites are not
reported as passing. Pull requests must also report validation evidence in the
PR body. The tiers below guide local validation depth before opening or
updating a PR; maintainers may ask for more validation when risk is unclear.

When a change spans multiple categories, use the highest tier that applies.

| Tier | Change type | Local validation expectation |
|---|---|---|
| 0 | Issue or PR metadata only, such as labels, comments, issue routing, or branch cleanup with no repository diff | Read back the GitHub state that changed. No local repository validation is needed unless files changed. |
| 1 | Low-risk text-only docs that do not affect README entrypoints, governance, release process, release notes, tracked `.agents` memory, scripts, installer behavior, CI, or generated runtime behavior | Run `git diff --check` and review links or changed prose manually. |
| 2 | Public adoption docs, README entrypoints, governance docs, release process docs, release notes, release readiness, tracked `.agents` memory, specs, issue/PR templates, or public/private boundary wording | 执行 `git diff --check`、必要时进行公开读者审查，并执行分类器选择的 affected-surface `iteration` / `pre-push` validation；默认不运行完整 Release 验证。 |
| 3 | PowerShell scripts, installer or uninstaller behavior, release validator behavior, CI workflow files, skill metadata, knowledge hub generation/search behavior, templates that affect generated project memory, or release packaging | 执行 `git diff --check`、受影响表面的定向解析器或冒烟检查，以及分类器选择的 affected-surface validation；完整 Release 验证仅用于明确的 Release/checkpoint 决策。 |

Release publication still requires the full release gate and maintainer
approval. Repository settings, secrets, GitHub App permissions, rulesets, and
release publishing are maintainer-controlled actions, not agent-only validation
tiers.

## Release Finalization Alignment

Maintainer authorization to publish starts the finalization phase; it is not
authorization to tag or publish directly from release-planning metadata.

Before creating a tag or GitHub Release, the agent must complete publish-ready
alignment:

1. Update `README.md` and `README.en.md` so their current release fields match
   the target version.
2. Update the target release notes from planning copy to published-release
   metadata, including status, tag target, published GitHub Release URL, and
   final validation evidence.
3. Update release readiness and the release notes index so they no longer carry
   stale candidate, draft, unpublished, or older-current-release wording.
4. Run `scripts/validate-release.ps1 -TargetVersion <target-version>` and fix
   any alignment failure before continuing.
5. Review the final diff and validation result before creating the tag or
   GitHub Release.

If alignment cannot be completed or validation fails, stop before tag creation
and release publication.

## GitHub Release Body Hygiene

Start every future release note from
[`docs/releases/template.md`](releases/template.md). The two marker lines are a
machine-enforced publication boundary, not editorial hints:

- The text between `<!-- RELEASE_BODY_START -->` and
  `<!-- RELEASE_BODY_END -->` is the user-facing GitHub Release body. It must
  explain who the release is for, required upgrade actions, main changes,
  compatibility, known limitations, rollback, and the public boundary. A
  concise statement that validation succeeded is allowed.
- The `Internal Release Record` after the end marker is the maintainer-facing
  evidence record. Put issue/pull-request mapping, exact
  PASS/FAIL/WARN/DEFERRED counts, hosted run IDs, platform matrix details,
  evidence manifests and artifacts, tag target, release status, maintainer
  authorization, and other governance facts there.

The validator inspects only the text inside the markers for internal evidence.
It fails closed when either marker is missing, duplicated, or reversed. Inside
the markers it rejects issue/PR mapping, exact validation counts, hosted run or
matrix evidence, merge waiting state, tag or publication instructions,
maintainer authorization, and similar internal workflow language. The same
facts are valid after the end marker in the maintainer record.

The tracked published release notes through `v0.6.0` predate this strict
contract and remain unchanged. The validator recognizes those files by an exact
closed allowlist; `template.md` and every unlisted release note use the strict
contract. A new or backdated note cannot gain compatibility treatment by using
an older version number or omitting its markers.

Body-only edits to existing GitHub Releases must be explicitly scoped as
body-only. They must not alter tags, tag targets, release assets, release dates,
latest/prerelease flags, repository settings, rulesets, secrets, or branch
protection.

## Old-Release Upgrade Rehearsal

Starting with `v0.5.0`, the release process requires at least one old-release
upgrade rehearsal before tagging a new public release. This rehearsal validates
the upgrade path from a published tag to the current `main`.

### When to Rehearse

- Before tagging any release that changes the install contract, template
  structure, project memory schema, or hub lock format.
- Before tagging any release that adds or removes install profiles.
- For patch or docs-only releases that do not change the above surfaces,
  a rehearsal from the most recent supported-direct tag is still recommended
  but may be skipped if the maintainer records the deferral.

### What to Rehearse

1. **Runtime install upgrade**: Install from the source tag, then upgrade from
   the target release source through the ordinary default incremental install
   path. A schema-2 runtime does not require `-Force`. Verify the install
   manifest.
2. **Project memory upgrade**: Bootstrap a project from the source tag's
   runtime, then upgrade the runtime and run memory upgrade analyze, hub
   lock check, context gate, and memory diagnosis.
3. **Record evidence**: Add results to
   `docs/old-release-rehearsal-evidence.md`.

For a schema-1 runtime whose managed content differs from the target source,
the default installer fails closed and preserves the existing content. The
maintainer must review or back up those differences first, and use
`-ReplaceManaged` only after explicitly accepting replacement of managed
content. `-Force` remains a deprecated compatibility alias for
`-ReplaceManaged`; it is not a required or recommended rehearsal path.

### Minimum Source Tag

The most recent supported-direct tag should be the primary rehearsal source.
For `v0.5.0`, this is `v0.4.6`. If the release changes the template
structure, also rehearse the earliest supported-direct source to confirm
forward compatibility.

### Checklist vs Automation

Today the rehearsal is a manual checklist. Steps are documented in
[Old-Release Upgrade Path](old-release-upgrade-path.md). Future enhancement
may script the rehearsal into the release validator as an optional fixture,
but this is not required for `v0.5.0`.

## Publishing Steps

1. Start from a clean local review branch or a clearly understood local diff.
2. Run the release validation gate with a temporary scratch directory.
3. Run the public reader review when the diff changes README, docs entrypoints,
   release notes, or release process text.
4. Review `validation-result.json` and any public diff.
5. Open or update a pull request when using CI for release review.
6. Confirm the PR classifier-selected suites and hosts, the fixed
   `validation gate`, and direct candidate identity checks pass for the final head.
7. Record only public-safe release status in this repository.
8. After maintainer authorization, complete release-finalization alignment and
   rerun the full local gate with `-TargetVersion <target-version>`.
9. Push, tag, and publish release notes only after the local full release gate,
   hosted required gate, final evidence review, and maintainer approval pass.

Do not publish if the validator reports a failed check. Fix the public tree or
record the release-blocking decision in private migration state, then rerun the
gate.

## Public Records

Public release records should describe the validation surface and final status.
Do not include local machine paths, private repository mappings, raw sensitive
audit findings, or private overlay details.

Root `.agents/` files are local runtime memory and are not public release
records. Public specs are durable work packages; use them for scope, decisions,
acceptance evidence, and completed results rather than local checkout or pull
request wait state.
