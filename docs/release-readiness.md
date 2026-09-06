# Release Readiness

Status: `v0.9.0` published public release.

## Current Release Pointer

- Latest published Release: `v0.9.0`。
- 当前 `main` 与 `v0.9.0` publish-finalization metadata 对齐；当前 `Unreleased`
  无新的 public changes。
- Current highest Release impact: `none`。
- 本页只记录当前状态和导航指针，不授权 `tag`、`publish` 或任何 GitHub
  Release 操作。

GitHub Release `v0.9.0` has been published:
https://github.com/Huangshier/agent-ecosystem/releases/tag/v0.9.0

已发布 Release 的正文与维护者记录位于
`docs/releases/v0.9.0.md`；本页不重复保存 tag target、验证计数或 hosted
run 记录。

## v0.9.0 Release

`v0.9.0` 是 `v0.8.0` 之后的 minor Release。它在既有 memory 但
`.agents/hub.lock.json` 缺失的项目上让 `project-bootstrap` fail closed，
legacy workspace 需要显式 `-LegacyWorkspace` 选择并在写入与迁移委托前校验
适用性；同时包含 `project-workspace` 的可靠性修复（canonical workspace 的
layout 有效性独立于可重建知识 Catalog 的新鲜度、`pwsh -File` 下的列表输入、
checkpoint 追加与替换语义）、`v0.8.0` 之后的 C3.3 adoption 文档收敛，以及
iteration / pre-push 重复本地重放消除与按风险面的 fail-closed 未知路由
收敛。

`v0.9.0` 不改变 C3.3 active Runtime authority（仍为 `project-bootstrap` 与
`project-workspace`）、PowerShell Core 7.6+ 基线、install profiles 或
default / recommended cutover。`v0.8.0` 之后曾准备的 `v0.8.1` 元数据从未
tag 或发布，其用户可见内容已并入本版本。

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
