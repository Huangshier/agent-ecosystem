# Release Process

本流程让 public release 可重复执行，同时将 private migration state、sensitive
audit detail 和 local runtime path 留在 public repository 之外。

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

从最近已发布版本 `vX.Y.Z` 出发，按 `Unreleased` 中的最高 impact 确定目标版本：

- `none`：本身不产生版本号递增；如果 `Unreleased` 全部为 `none`，默认不创建版本化 Release。maintainer 若明确决定仍需发布，最低使用 `patch`。
- `patch`：`vX.Y.Z` -> `vX.Y.(Z+1)`。
- `minor`：`vX.Y.Z` -> `vX.(Y+1).0`。
- `major`：`vX.Y.Z` -> `v(X+1).0.0`，必须由 maintainer 显式决定。

对于 `0.x`：

- `breaking change` 可以按 `minor` 表达，并要求迁移或兼容性说明；
- 只有 maintainer 明确决定进入新的 `major/stability line` 时才使用 `major`。

当前事实可按同一规则确定推导：`v0.7.1` + highest impact `minor` -> `v0.8.0`。

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

使用 live Runtime 之外的 scratch directory。validator 拒绝使用当前 user 的
`$HOME\.agents` Runtime path。它为每个 temporary install 写入
`install-manifest.json` 和 `install-report.json`，并在 scratch directory 下写入
最终的 `validation-result.json`。
C3.3 validation control plane 和 normative repository validation entrypoint
（包括本 release validator）要求 PowerShell Core 7.6 或更高版本，并通过
`pwsh -NoProfile -NonInteractive -File` 运行。

当前 Runtime authority 是 `project-bootstrap` + `project-workspace`。
`project-context-gate`、`workflow-spec-lite` 和 `memory-governance` 已从 current
Runtime authority retired；validator fixture 或 release record 中保留的相关
名称只是 historical/compatibility evidence。legacy project migration 通过
`scripts/migrate-project.ps1` 的 Analyze -> explicit Apply -> guarded Rollback
执行。

当前 non-PowerShell policy 见 [Shell strategy](shell-strategy.md)：public release
line 尚未提供 Bash or Zsh wrappers；未来 wrapper 应通过 `pwsh` 委托给 canonical
`.ps1` script。

当 maintainer 有意复用 persistent scratch parent 时，删除前先检查 retention：

```powershell
pwsh -NoProfile -NonInteractive -File .\scripts\prune-validation-scratch.ps1 -ScratchRoot <scratch-parent> -RetainLatest 10
```

pruning helper 默认是 dry run。只有 review evidence 后才添加 `-Apply`。它只处理
包含 `validation-result.json` 的 direct child directory，拒绝 live Runtime 和
repository-root target，并通过 `-Json` 输出 JSON evidence。

validator 检查：

- public repository structure 和 release documentation entrypoint
- target version 在 `README.md`、`README.en.md`、release note、release readiness
  和 release notes index 中的 publish-ready metadata 对齐
- root `.agents/` Runtime memory 未被 track，同时 generated/template `.agents`
  path 仍被允许
- public Spec file 避免明显的 volatile active-state record，除非由 historical
  evidence、stop-rule 或 retrospective allowlist 覆盖
- Workflow Kernel skill metadata
- `minimal`、`recommended`、`full` 和 `dev` 的 installer profile matrix
- default copy install 与显式 development link/junction install
- recommended copy 和 link install 中 bootstrap、`project-workspace`
  check/discover、active C3.3 status、retired-Skill absence 和 explicit
  migration boundary 的 Runtime smoke coverage
- incremental installer rerun、unknown/local-modified protection、conflict
  exit behavior、`-AllowPartial` 和 managed replacement compatibility
- hub initialization Git mode，包括 default no-Git behavior 和显式 Git
  initialization
- temporary git-backed hub 中 `hub.lock` 的 in-sync、missing-lock、invalid-hub、
  drift 和 multi-project batch check
- temporary project 上的 legacy project migration Analyze、explicit Apply 和
  guarded Rollback flow
- knowledge catalog、pattern 和 standard entry coverage
- public domain-pack catalog coverage
- public experience index search
- temporary hub copy 上的 experience promotion、index rebuild 和 search closure
- 保持 registry file hash 的 no-op experience index rebuild
- Claude Code hooks guardrails contract、executable lifecycle setting 和
  runner、bundled snapshot，以及 public-safe deterministic stdin/stdout fixture
- PowerShell parser check 和 JSON parsing
- non-ASCII PowerShell script 的 UTF-8 encoding
- public sensitive-pattern audit
- duplicate helper script hash
- repository guidance 和 bootstrap output 中的 language policy template coverage
- 由 agent 或 workflow 显式提供 `-ProjectLanguage` 值驱动的 English 与
  Simplified Chinese temporary project first-session language write capability
- `en` 与 `zh-CN` 之间的 conservative project-memory language migration，包括
  proposal-first、backup-first、apply、validate、mixed-memory 和
  project-specific preservation fixture
- read-only body-level project-memory language audit coverage，包括 metadata/body
  mismatch、fenced code、protected literal 和 mixed narrative fixture
- project-bootstrap operating mode，包括 missing-template refresh、
  unmodified-template refresh、compatibility overwrite warning 和 backup-first
  force reset behavior
- legacy diagnostic 和 upgrade analysis 保留的 historical localized context discovery headings
- language policy 和 bundled knowledge asset 中的 bilingual public/private routing guidance
- 为 compatibility 和 negative validation 保留的 historical
  `workflow-spec-lite` 与 memory-governance fixture；它们不定义 current Runtime
  authority
- validation scratch retention pruning 的 dry-run/apply behavior
- adoption guide 和 minimal project example coverage
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

repository 会在 pull request、push 到 `main` 和 manual dispatch 时运行
`.github/workflows/release-validation.yml`。这些 event 有意承担不同的 validation
responsibility：

| Surface | Responsibility | Hosted path |
|---|---|---|
| Pull request | 证明 diff 及其 affected behavior | classifier-selected quick/affected suite，以及需要时的 control-plane self-protection；validation-routing change 还会执行 Windows main-health smoke；PR A 的 direct bootstrap regression 仍在 affected path。 |
| `main` push | 证明 repository healthy | 一个 Windows `main health` job，检查 PowerShell/JSON parsing、public-safe/sensitive scanning，以及小型 copy-install/bootstrap/C3.3 workspace smoke。 |
| Release/checkpoint | 证明完整 publication surface | manual run 保留 `RepositoryCheckpointNeutral` 和 `RepositoryCheckpointRuntime` validator shard，包括 required cross-platform Runtime matrix 和 release-only check。 |

main health job 有意不是 Release candidate。`main` push 不运行
`PlatformNeutral` 或 three-platform `RuntimePlatform` release shard，也不调用
完整的 `scripts/validate-release.ps1` suite。固定的 `validation gate` 仍是唯一
required result check。main 不运行 lineage shadow，普通 PR job 也不为后续
aggregation step 上传 per-job evidence manifest。

对 pull request，deterministic classifier 选择 affected suite 及这些 suite 声明
的 host。validation routing 或其他 validation control-plane surface 变更还会
运行 independent self-protection oracle；validation-routing change 在 merge 前
另外执行 Windows main-health smoke。其他 PR 不运行该 job。权威 routing 和
conservative fallback rule 见 [PR validation risk tiers](pr-validation-risk-tiers.md)。

固定的 `validation gate` 评估 classifier-selected job；当 classification、required
execution、conditional main-health 或 self-protection result 不完整时 fail
closed。classifier 和选中的 PR validation job 保留 direct exact-candidate
identity check；gate 只 aggregate job result。完整 hosted release-validation
matrix 不是 per-PR hard gate。

每次 `main` push 只运行 thin main health contract，不选择 Release profile。manual
dispatch 使用更宽的 `RepositoryCheckpoint` profile，覆盖 release archive、
governance、evaluation、benchmark、historical 及其他 checkpoint-only assertion。

workflow 使用 event-aware GitHub Actions concurrency。新的 pull-request 和
manual dispatch run 可以取消同 event、同 ref 的旧 run；每次 `push` 到 `main`
都有 unique concurrency identity。

成功的 manual Release/checkpoint job 上传 explicit evidence allowlist；失败的
Release job 保留完整 scratch directory 供 diagnosis。普通 PR validation 由 job
result 和 direct candidate check 表示。除非 maintainer 明确为 pre-release
calibration run 记录 platform-specific deferral，否则 evaluator failure 和其他
required CI failure 都应视为 release blocker。

validation-sensitive text file 由 `.gitattributes` 统一为 LF，使 experience
registry 中的 content hash 在 hosted Windows、Ubuntu 和 macOS runner 上稳定。

只有 capability 尚不存在时才允许 deferred check。可发布 Release 的 release
validator 应报告 zero deferred check，除非 maintainer 明确记录新的 deferral。

workflow 保留 always-run fixed `validation gate`，不依赖可能使 required check
保持 pending 的 workflow-level path filter。未来任何 routing change 都必须保留
fail-closed required gate，并在同一个 reviewed change 中同步更新本流程和
repository required-check setting。

## Public Reader Review

对于 public-facing documentation 和 release metadata change，merge 前完成简短的
reader-oriented review：

- **First-time reader**：README 和 docs index 说明 project 的定位、非目标以及
  下一步去哪里。
- **Current release**：描述 active release line 时，current docs 不依赖过时的
  first-release framing。
- **Validation summary**：release note 和 readiness doc 与 validator output
  以及彼此之间保持一致。
- **Public boundary**：doc 不包含 private overlay detail、local migration state、
  machine-specific path 或 private review material。
- **Cross-platform onboarding**：非 Windows reader 能看到 PowerShell-first
  expectation，并在适当位置获得 `pwsh` guidance。

该 review 有意保持轻量，是 adoption surface 的 checklist，不是独立的 approval
process。

## Validation Tiers

固定的 hosted `validation gate` 仍是 pull request 到 `main` 的 fail-closed merge
result。classifier 和 selected validation job 决定哪些 affected suite 与 host
必须满足该 gate；skipped suite 不报告为 passing。pull request 还必须在 PR body
报告 validation evidence。以下 tier 指导打开或更新 PR 前的本地 validation
depth；风险不明确时，maintainer 可以要求更多 validation。

一个 change 跨越多个 category 时，使用适用的最高 tier。

| Tier | Change type | Local validation expectation |
|---|---|---|
| 0 | 仅 Issue 或 PR metadata，例如 labels、comments、issue routing，或没有 repository diff 的 branch cleanup | 回读发生变化的 GitHub state。除非文件发生变化，否则不需要本地 repository validation。 |
| 1 | 不影响 README entrypoint、governance、release process、release note、tracked `.agents` memory、script、installer behavior、CI 或 generated Runtime behavior 的低风险纯文本 doc | 运行 `git diff --check`，手动 review link 或变更正文。 |
| 2 | public adoption doc、README entrypoint、governance doc、release process doc、release note、release readiness、tracked `.agents` memory、Spec、issue/PR template 或 public/private boundary wording | 执行 `git diff --check`、必要时进行公开读者审查，并执行分类器选择的 affected-surface `iteration` / `pre-push` validation；默认不运行完整 Release 验证。 |
| 3 | PowerShell script、installer 或 uninstaller behavior、release validator behavior、CI workflow file、skill metadata、knowledge hub generation/search behavior、影响 generated project memory 的 template 或 release packaging | 执行 `git diff --check`、受影响表面的定向解析器或冒烟检查，以及分类器选择的 affected-surface validation；完整 Release 验证仅用于明确的 Release/checkpoint 决策。 |

Release publication 仍需要完整 release gate 和 maintainer approval。Repository
setting、secret、GitHub App permission、ruleset 和 release publishing 都是
maintainer-controlled action，不是 agent-only validation tier。

## Release Finalization Alignment

maintainer 对 publish 的授权会开始 finalization phase；它不等于可以直接从
release-planning metadata tag 或 publish。

创建 tag 或 GitHub Release 前，agent 必须完成 publish-ready alignment：

1. 更新 `README.md` 和 `README.en.md`，使 current release field 与 target
   version 匹配。
2. 将 target release note 从 planning copy 更新为 published-release metadata，
   包括 status、tag target、published GitHub Release URL 和 final validation
   evidence。
3. 更新 release readiness 和 release notes index，移除 stale candidate、draft、
   unpublished 或 older-current-release wording。
4. 运行 `scripts/validate-release.ps1 -TargetVersion <target-version>`，继续
   前修复所有 alignment failure。
5. 创建 tag 或 GitHub Release 前，review final diff 和 validation result。

如果无法完成 alignment 或 validation failure，必须在创建 tag 和 release
publication 前停止。

## GitHub Release Body Hygiene

未来每个 release note 都从 [`docs/releases/template.md`](releases/template.md)
开始。两行 marker 是 machine-enforced publication boundary，不是 editorial hint：

- `<!-- RELEASE_BODY_START -->` 与 `<!-- RELEASE_BODY_END -->` 之间的 text 是
  user-facing GitHub Release body。必须说明 release 面向谁、required upgrade
  action、主要变更、compatibility、known limitation、rollback 和 public
  boundary；可以简短说明 validation succeeded。
- end marker 之后的 `Internal Release Record` 是 maintainer-facing evidence
  record。Issue/pull-request mapping、exact PASS/FAIL/WARN/DEFERRED count、
  hosted run ID、platform matrix detail、evidence manifest 和 artifact、tag
  target、release status、maintainer authorization 及其他 governance fact 都
  放在这里。

validator 只检查 marker 内的 text 是否包含 internal evidence。任一 marker 缺失、
重复或顺序反转时会 fail closed。marker 内拒绝 issue/PR mapping、exact
validation count、hosted run 或 matrix evidence、merge waiting state、tag 或
publication instruction、maintainer authorization 及类似 internal workflow
language；相同 fact 可以放在 end marker 之后的 maintainer record 中。

tracked、截至 `v0.6.0` 的 published release note 早于此 strict contract，保持
不变。validator 通过 exact closed allowlist 识别这些 file；`template.md` 和未
列出的每个 release note 使用 strict contract。新的或 backdated note 不能仅靠
使用较旧 version number 或省略 marker 获得 compatibility treatment。

对已有 GitHub Release 的 body-only edit 必须显式限定为 body-only。不得修改 tag、
tag target、release asset、release date、latest/prerelease flag、repository
setting、ruleset、secret 或 branch protection。

## Old-Release Upgrade Rehearsal

从 `v0.5.0` 开始，release process 要求在新的 public release 创建 tag 前至少
完成一次 old-release upgrade rehearsal。该 rehearsal 验证从 published tag 到
当前 `main` 的 upgrade path。

### 何时进行 Rehearse

- 在 tag 任何改变 install contract、template structure、project memory schema 或
  hub lock format 的 release 前。
- 在 tag 任何增加或删除 install profile 的 release 前。
- 对不改变上述 surface 的 patch 或 docs-only release，仍建议从最近的 Runtime
  refresh source tag rehearsal；如果 maintainer 记录 deferral，可以跳过。

### Rehearse 什么内容

1. **Runtime install upgrade**：从 source tag 安装，然后从 target release source
   通过 ordinary default incremental install path 升级。schema-2 Runtime 不需要
   `-Force`。验证 install manifest。
2. **Project workspace migration**：从 source tag 的 Runtime bootstrap project，
   然后升级 Runtime 并运行 `project-workspace` check/discover。如果 project
   是 legacy，运行 `scripts/migrate-project.ps1` Analyze，review evidence，
   explicit Apply，并验证 guarded Rollback path。rehearsal record 中较旧的
   context-gate、workflow-spec 或 memory-diagnosis reference 是 historical
   evidence，不是 current C3.3 authority。
3. **Record evidence**：将结果加入 `docs/old-release-rehearsal-evidence.md`。

对 managed content 与 target source 不同的 schema-1 Runtime，default installer
fail closed 并保留 existing content。maintainer 必须先 review 或 backup 这些
difference，只有显式接受替换 managed content 后才使用 `-ReplaceManaged`。
`-Force` 仍是 `-ReplaceManaged` 的 deprecated compatibility alias，不是 required
或 recommended rehearsal path。

### Minimum Source Tag

最近的 Runtime refresh source tag 应作为 primary rehearsal source。对 `v0.5.0`，
该 source 是 `v0.4.6`。如果 release 改变 template structure，也应 rehearsal
最早的可用 Runtime refresh source，以检查迁移 evidence；不要把 source version
本身当作 target project 无需 migration 的承诺。

### Checklist 与 Automation

当前 rehearsal 是 manual checklist，步骤记录在
[Old-Release Upgrade Path](old-release-upgrade-path.md)。未来 enhancement 可以
将 rehearsal script 化为 release validator 的 optional fixture，但 `v0.5.0` 不
要求这样做。

## Publishing Steps

1. 从干净的 local review branch 或已明确理解的 local diff 开始。
2. 对普通 pull request，运行 `git diff --check`、classifier-selected affected
   `iteration` 和 `pre-push` validation，以及 targeted documentation consumer
   check。不要仅因为准备 docs PR 就运行完整 Release validator。
3. 当 diff 修改 README、docs entrypoint、release note 或 release process text
   时，运行 Public Reader Review。
4. 对明确的 Release/checkpoint decision，使用 temporary scratch directory
   运行 Release validation gate，并 review `validation-result.json`。
5. Review public diff；如果使用 CI review，则打开或更新 pull request。
6. 确认 PR classifier-selected suite 和 host、固定的 `validation gate` 以及
   direct candidate identity check 在 final head 上通过。
7. 在本 repository 中只记录 public-safe release status。
8. maintainer authorization 后，完成 release-finalization alignment，并使用
   `-TargetVersion <target-version>` 重跑完整 local gate。
9. 只有 local full release gate、hosted required gate、final evidence review 和
   maintainer approval 都通过后，才 push、tag 和 publish release note。

validator 报告 failed check 时不要 publish。修复 public tree，或在 private
migration state 中记录 release-blocking decision，然后重新运行 gate。

## Public Records

Public release record 应说明 validation surface 和 final status。不要包含 local
machine path、private repository mapping、raw sensitive audit finding 或 private
overlay detail。

root `.agents/` file 是 local Runtime memory，不是 public release record。Public
Spec 是 durable work package；应使用它记录 scope、decision、acceptance evidence
和 completed result，不要记录 local checkout 或 pull request wait state。
