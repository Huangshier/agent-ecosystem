# Release Readiness

Status: `v0.7.1` published public release；当前 `main` 已领先 `v0.7.1`。

## Current Release Pointer

- Latest published Release: `v0.7.1`。
- 当前 `main` 已包含 `v0.7.1` 之后的 C3.3、default cutover 和 PR #340
  status alignment；这些变化仍属于 `Unreleased`，不是已发布 Release。
- Current highest Release impact: `minor`。
- Next target: `v0.8.0` release review。
- 本页只记录当前状态和导航指针，不授权 `tag`、`publish` 或任何 GitHub
  Release 操作。

GitHub Release `v0.7.1` has been published：
https://github.com/Huangshier/agent-ecosystem/releases/tag/v0.7.1

已发布 Release 的正文与维护者记录位于
`docs/releases/v0.7.1.md`；本页不重复保存 tag target、验证计数或 hosted
run 记录。

## Unreleased

当前 `Unreleased` 的主要公共变化包括：

- C3.3 Workflow Kernel 已成为当前 Runtime 基线；active Runtime Skills 为
  `project-bootstrap` 和 `project-workspace`。
- default / recommended runtime cutover 已完成；`project-context-gate`、
  `workflow-spec-lite`、`memory-governance` 不再是当前 Runtime authority。
- PR #340 已修复有效 C3.3 workspace 的 status authority，使顶层 Project
  status 服从 `project.workspace`，并将 legacy migration 指向
  `scripts/migrate-project.ps1`。
- 普通 PR 使用 classifier-selected affected `iteration` / `pre-push`
  validation；`main` push 只运行 thin main health；完整 Release/checkpoint
  validation 仅在明确 Release 决策时运行。

这些变化使 `Unreleased` 达到 `minor` 级别，但本 Issue 和本 PR 都不发布
`v0.8.0`，也不构成 tag 或 publish 授权。

## Current C3.3 Authority

- PowerShell baseline：PowerShell Core 7.6+，通过
  `pwsh -NoProfile -NonInteractive -File`。
- fresh project：`project-bootstrap` + `project-workspace`。
- existing legacy project：`scripts/migrate-project.ps1` 的 Analyze → explicit
  Apply → guarded Rollback。
- workspace checks：`project-workspace` 的 `check-project-workspace` 和
  `discover-project-assets`。
- durable Spec：`project-workspace create-spec`。
- status：当前顶层 Project status 服从 `project.workspace` authority，不依赖
  retired memory helpers。

## Authority and Records Pointers

- `docs/release-process.md`：版本号、Release impact、Release review 和发布
  授权边界。
- `CHANGELOG.md`：`Unreleased` 与已发布版本的变化摘要。
- `docs/releases/**`：已发布 Release notes 与未来 Release note template。
- `docs/old-release-rehearsal-evidence.md`：历史升级 rehearsal evidence；它是
  historical evidence，不是当前 authority。
- `docs/language-policy.md`：public governance artifact 的中文优先和机器契约
  保留规则。

## Validation Pointer

普通文档 PR 运行 `git diff --check`、classifier-selected affected
`iteration` / `pre-push`、必要的 targeted documentation consumers 和 Public
Reader Review。不要因为普通 PR 触发完整 Release validator；只有明确的
Release/checkpoint 决定才进入 `release` stage。

为兼容现有机械消费者，以下术语仍作为历史或路由指针保留：
`Bilingual Public/Private Routing`、`localized context discovery headings`。
它们不构成新的 Runtime 或 Release authority。

## Current Quick Start

当前仅用于本地验证和文档导航，不表示发布授权：

```powershell
pwsh -NoProfile -NonInteractive -File .\scripts\install.ps1 -Profile recommended -TargetDir <temp-runtime>
pwsh -NoProfile -NonInteractive -File .\scripts\invoke-local-validation.ps1 -Stage iteration
pwsh -NoProfile -NonInteractive -File .\scripts\invoke-local-validation.ps1 -Stage pre-push
```

完整 Release validation 只在明确 Release/checkpoint 决定下运行：

```powershell
pwsh -NoProfile -NonInteractive -File .\scripts\validate-release.ps1 -ScratchRoot <scratch-root> -TargetVersion <target-version>
```
