# Release Readiness

Status: `v0.8.0` published public release.

## Current Release Pointer

- Latest published Release: `v0.8.0`。
- 当前 `main` 已包含 `v0.8.0` 之后的变化；这些变化仍属于 `Unreleased`，不是
  已发布 Release。
- Current highest Release impact: `minor`。
- 本页只记录当前状态和导航指针，不授权 `tag`、`publish` 或任何 GitHub
  Release 操作。

GitHub Release `v0.8.0` has been published:
https://github.com/Huangshier/agent-ecosystem/releases/tag/v0.8.0

已发布 Release 的正文与维护者记录位于
`docs/releases/v0.8.0.md`；本页不重复保存 tag target、验证计数或 hosted
run 记录。

## v0.8.0 Release

`v0.8.0` 将 `v0.7.1` 之后的 C3.3 实现与一次性的 default / recommended runtime
cutover 收敛为新的版本基线。active Runtime authority 为 `project-bootstrap` 与
`project-workspace`；`project-context-gate`、`workflow-spec-lite`、
`memory-governance` 不再是当前 Runtime authority。既有项目通过
`scripts/migrate-project.ps1` 的 Analyze → explicit Apply → guarded Rollback
迁移。

从 `v0.7.1` 的旧版 Runtime、旧版 agent skill bridge 与旧版项目工作区到当前
C3.3 基线的升级路径已在 Issue #345 Stage A 演练并收口；演练证据记录在
`docs/old-release-rehearsal-evidence.md`。

## Unreleased

当前 `Unreleased` 没有新的公共变化。

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

## Current Validation Quick Reference

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
