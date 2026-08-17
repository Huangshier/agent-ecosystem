# Old-Release Upgrade Path

本文定义从旧 public release 升级到当前 C3.3 Runtime 时的支持矩阵，并明确
Runtime install state 与 existing project workspace state 的不同处理方式。

New user 应使用 [how-to-adapt](how-to-adapt.md) 或
[minimal project adoption walkthrough](walkthroughs/minimal-project-adoption.md)。
本文面向已经从 previous public release 安装过 Runtime 的 user。

## Upgrade Support Matrix

| Source version | Runtime install upgrade | Target-project C3.3 workspace |
| --- | --- | --- |
| `v0.4.6` | **Direct Runtime refresh**：按 installer contract 刷新。schema-1 copy Runtime 如果 content 与新 source 不同，必须 review `install.ps1 -ReplaceManaged`；默认运行会报告 conflict 并保留 schema 1。 | 不能仅按 `v0.4.6` 判断 project workspace 是否 current。Runtime 更新后必须执行当前 status、`project-workspace check` 和必要的 `discover`；current 时无需 migration，legacy 时进入下方 C3.3 migration flow。 |
| `v0.4.5` | **Direct Runtime refresh**：同一 installer contract；schema-1 conflict 仍需显式 review。 | 不能仅按历史版本号承诺 project 无需 migration。按 status / `project-workspace check` 结果处理：current 不迁移，legacy 使用 `scripts/migrate-project.ps1`。 |
| `v0.4.4` | **Direct Runtime refresh**：同一 installer contract；保留 unknown 和 locally modified content。 | 不能仅按历史版本号判断 workspace。Runtime 更新后执行 status / check；legacy project 统一走 Analyze -> explicit Apply -> guarded Rollback。 |
| `v0.4.3` | **Direct Runtime refresh**：同一 installer contract；发生 managed-content conflict 时 fail closed。 | 不能仅按历史版本号判断 workspace。只有当前 check 识别为 current 时才无需 migration；否则按 analyzer evidence 处理。 |
| `v0.4.2` | **Direct Runtime refresh**：这是 language-scoped template model（`templates/languages/`）的首个 release；Runtime install 可按 installer contract 刷新。 | `v0.4.2` 不构成 project workspace 无需 migration 的承诺。更新 Runtime 后先执行 status / `project-workspace check` / `discover`；legacy 统一进入 `scripts/migrate-project.ps1`。 |
| `v0.4.1` | **Best-effort Runtime refresh**：使用 installer 并 review `install-report.json`；旧 layout（flat `templates/` without language prefix）可能产生 conflict。 | 不按版本号承诺 project 兼容。对 legacy content 运行 Analyze，review evidence 后才可 explicit Apply；unsupported 或 ambiguous content 留给 human disposition。 |
| `v0.4.0` | **Best-effort Runtime refresh**：language migration workflow 已出现，但 template 尚未 language-scoped；先 review installer result。 | 先执行当前 status / check / discover。只有 analyzer 给出 supported plan 才可迁移；不支持的内容保持 best-effort / human disposition。 |
| `v0.3.0`, `v0.3.1` | **Best-effort Runtime refresh**：project structure 差异较大；刷新 Runtime 后检查 install result。 | 不按版本号承诺 workspace migration 结果。使用当前 workspace checks 和 `scripts/migrate-project.ps1` Analyze；Apply 需要 review evidence。 |
| `v0.1.0`, `v0.2.0` | **Unsupported / manual disposition**：Runtime 可在适当时备份后尝试刷新，但不承诺自动 install upgrade。 | project structure 差异很大；备份 project-specific content，获取 human disposition，只对明确 supported 的 Analyze result 进行 migration，不把 force reset 当作自动升级。 |

### Terminology

- **Direct Runtime refresh**：表示 Runtime install 可以按照 installer contract
  直接刷新，不表示 target project 已是 current C3.3 workspace，也不表示 project
  无需 migration。schema-2 Runtime 会增量刷新；schema-1 copy manifest 没有可靠
  的 per-file baseline，target/source difference 在 review 并显式提供
  `-ReplaceManaged` 前都是 conflict。
- **Best-effort Runtime refresh**：重新运行 `install.ps1`，review
  `install-report.json`，解决 Runtime conflict，然后检查 project workspace。
  旧 project 可能含 stale template reference 或 missing field；运行 C3.3
  migration Analyze，review evidence 后再决定是否 Apply。
- **Unsupported / manual disposition**：install script 可能能够替换 Runtime
  file，但 project content 太旧，无法生成 automatic migration plan。先备份
  project-specific content 并获取 human disposition；对 unsupported 或
  ambiguous material，migration command fail closed。
- Runtime install upgrade 与 target-project workspace migration 是两个独立决策：
  能直接刷新 Runtime，不代表旧 project 已 current；必须以当前 status 和
  `project-workspace check` 结果决定是否 migration。

## Runtime Install Upgrade

### Same-Machine Refresh（最常见）

在同一台 machine 上增量刷新已有 Runtime install：

```powershell
# Clone or pull the target release
git checkout v0.7.1  # or the target tag

# Refresh managed files and preserve unknown or locally modified content
pwsh -NoProfile -NonInteractive -File scripts/install.ps1 -Profile recommended
```

对于 schema-2 manifest，installer 会恢复缺失的 managed file，更新 source 已变更
但 installed copy 未变更的 file，不重写 unchanged file。Unknown file 和本地已
修改的 managed file 会保留。如果 file 在本地和 source 中都发生变化，会报告
conflict；除非提供 `-AllowPartial`，否则返回 non-zero。

Schema-1 copy manifest 没有可信的 installed-content baseline。如果 managed target
与新 source 不同，default run 返回 conflict，不覆盖 target，并保留 schema-1
manifest。`-AllowPartial` 仍会使该 migration 保持 incomplete。review 或 backup
local Runtime change 后，使用 `-ReplaceManaged` 重新运行，只覆盖 managed
content、保留 unknown file，并完成 schema-2 migration。

### Copy Mode Install

要安装到独立 directory（用于 testing 或 isolation）：

```powershell
pwsh -NoProfile -NonInteractive -File scripts/install.ps1 -Profile recommended -TargetDir <path>
```

Copy mode 是 default，会创建不带 junction 或 symbolic link 的独立 file copy。
现有 `-Copy` switch 继续兼容。

### Explicit Development Link Install

Contributor 可以显式选择 source-linked Runtime item：

```powershell
pwsh -NoProfile -NonInteractive -File scripts/install.ps1 -Profile recommended -TargetDir <dev-runtime> -DevLink
```

Windows 上会创建 `Junction` item，其他 platform 上会创建 `SymbolicLink` item。
Link creation failure 是 error；显式 development request 不会静默 fallback 到
copy mode。

### Upgrade 后的 Manifest

成功 migration 后，schema-2 `install-manifest.json` 记录 profile、actual strategy、
runtime-relative managed item，以及与 installed file 匹配的 content hash。Schema-1
`install-report.json` 记录 current run 的 status 和 file list。验证两个 artifact：

```powershell
Get-Content ~/.agents/install-manifest.json | ConvertFrom-Json
Get-Content ~/.agents/install-report.json | ConvertFrom-Json
```

`-Force` 仍仅作为 `-ReplaceManaged` 的 deprecated compatibility alias 接受；它
不再在 reinstall 前删除整个 Runtime。

## Project Workspace Migration

Runtime 更新后，先检查 existing project，再决定是否需要 project workspace
migration。当前 C3.3 authority 是：`project-workspace` 负责 read-only workspace
check 和 discovery；Runtime-level `scripts/migrate-project.ps1` 负责 legacy
migration。`scripts/status.ps1` 的顶层 Project status 服从 `project.workspace`
authority，不查询 retired memory helper。

上述判断和 migration flow 不会把历史 `memory_upgrade`、`context-gate` 或
`memory-governance` 恢复为 current authority；这些名称只可作为 historical 或
compatibility evidence 出现。

### 每次 Runtime Refresh 后的 Project 状态判断

无论 project 来自哪个历史版本，直接刷新 Runtime 都不等于 target project 已是
current C3.3 workspace。Runtime 更新后按以下顺序执行：

```powershell
# 1. Read-only status
pwsh -NoProfile -NonInteractive -File <runtime>/scripts/status.ps1 -RuntimeDir <runtime> -ProjectDir <project> -Json

# 2. Read-only workspace contract check
pwsh -NoProfile -NonInteractive -File <runtime>/skills/project-workspace/scripts/check-project-workspace.ps1 -ProjectRoot <project> -Json

# 3. Progressive canonical asset discovery
pwsh -NoProfile -NonInteractive -File <runtime>/skills/project-workspace/scripts/discover-project-assets.ps1 -ProjectRoot <project> -Query <query> -Json
```

如果 status 和 workspace check 都表明 workspace current，且 discovery 找到预期的
canonical asset，则无需 migration。需要 durable work package 时，在 project-local
使用 `project-workspace create-spec` 创建 Spec。

### Legacy Workspace：统一 Migration Flow

如果 check 识别为 legacy，或 status 表示 `migration-required`，统一使用
Runtime-level `scripts/migrate-project.ps1`：先 Analyze，再 review evidence，
然后 explicit Apply，最后验证并保留 guarded Rollback。不要按历史版本号直接
承诺 project workspace 无需 migration。

```powershell
# 1. Analyze (strictly read-only)
pwsh -NoProfile -NonInteractive -File <runtime>/scripts/migrate-project.ps1 -Mode Analyze -ProjectRoot <project> -Json

# 2. Review the evidence, then apply explicitly
pwsh -NoProfile -NonInteractive -File <runtime>/scripts/migrate-project.ps1 -Mode Apply -ProjectRoot <project> -AnalyzeEvidence <analyze-json> -ConfirmMigration -Json

# 3. Validate the resulting workspace
pwsh -NoProfile -NonInteractive -File <runtime>/skills/project-workspace/scripts/check-project-workspace.ps1 -ProjectRoot <project> -Json
pwsh -NoProfile -NonInteractive -File <runtime>/skills/project-workspace/scripts/discover-project-assets.ps1 -ProjectRoot <project> -Query <query> -Json
```

完整的保守升级 flow 和 local memory preservation rule 见
[Existing Project Upgrade Path](existing-project-upgrade.md)。

### Best-Effort / Unsupported 或 Ambiguous Content

对于过旧 release、analyzer 不支持的 content，或 Analyze 结果含 ambiguous
material：

1. 备份 project-specific `.agents/` content（process.txt、plan.md、notes.md、
   context entry、local Spec）。
2. 获取 human disposition；只有 Analyze 明确给出 supported result 时才运行
   migration authority。不要使用 retired Skill 或 implicit bootstrap reset
   代替 migration。

   ```powershell
   pwsh -NoProfile -NonInteractive -File <runtime>/scripts/migrate-project.ps1 -Mode Analyze -ProjectRoot <project> -Json
   ```

3. 从 backup 恢复 project-specific content（如果操作需要恢复）。
4. 使用 `project-workspace` check/discover 验证。如果 migration 已 Apply，
   rollback 受 unchanged-project check 保护：

   ```powershell
   pwsh -NoProfile -NonInteractive -File <runtime>/scripts/migrate-project.ps1 -Mode Rollback -ProjectRoot <project> -BackupId <backup-id> -ConfirmRollback -Json
   ```

### Fresh-Machine Install

fresh-machine install 没有 existing Runtime 或 project memory，使用 standard quick
start：

```powershell
pwsh -NoProfile -NonInteractive -File scripts/install.ps1 -Profile recommended
```

然后 bootstrap project：

```powershell
pwsh -NoProfile -NonInteractive -File ~/.agents/skills/project-bootstrap/scripts/bootstrap_project.ps1 -ProjectDir <project> -ProjectLanguage en
```

fresh install 不需要 upgrade 或 migration step。active Runtime authority 是
`project-bootstrap` + `project-workspace`。

## Rehearsal Evidence

`v0.7.0` → `v0.7.1` upgrade path 已为该 release 完成 rehearsal。更早的 rehearsal
保留在 [Old-Release Rehearsal Evidence](old-release-rehearsal-evidence.md) 中，
作为 historical evidence，不删除也不重写。rehearsal 覆盖普通 schema-2 copy
upgrade、managed 和 locally modified content protection、project-state 与
conservative-refresh boundary、deterministic context metadata matching，以及
explicit skill bridge。其中的 old helper reference 是 historical evidence，不是
current C3.3 Runtime authority。publish-finalization branch SHA 只是 provisional
review evidence，不是 final tag target；final tag target 只能在 authorized merge
之后确定。

## Release Process Implications

从 `v0.5.0` 开始，改变 install contract、template structure、project workspace
schema、hub lock format 或 install profile 的 release，在 tag 前至少需要一次
old-release upgrade rehearsal。该 rehearsal：

- 使用最近的 Runtime refresh source 对 target release 执行验证。
- 同时验证 Runtime install upgrade 和 project workspace migration。
- 将结果作为 public-safe evidence 记录在本 repository 中。
- 当前是 manual checklist；scripted automation 属于 future enhancement。

不改变上述 surface 的 patch 或 docs-only release，如果 maintainer 记录 deferral，
可以跳过 rehearsal。文档 PR 仍使用 affected `iteration` / `pre-push` validation；
完整 Release validator 不是普通 PR 的要求。

rehearsal requirement 见 [Release Process](release-process.md#old-release-upgrade-rehearsal)。

## Non-Goals

- 本文不定义 online auto-updater。
- 本文不承诺无限期支持每个 historical tag。
- 本文不改变 install profile behavior。
- 本文不覆盖 private overlay 或 local migration state。
