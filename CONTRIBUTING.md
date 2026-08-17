# Contributing

感谢你帮助改进 Agent Ecosystem。

## Scope

当前 public Runtime 是 C3.3 Workflow Kernel：

- `project-bootstrap`
- `project-workspace`

`project-context-gate`、`workflow-spec-lite` 和 `memory-governance` 已退出
C3.3 Runtime authority。它们可以保留在历史记录或 negative validation
fixtures 中，但当前 public profiles 不安装它们，当前项目指引也不得把新工作
路由到这些入口。

在 public kernel 和 installer 稳定前，domain-specific Skills 与 private
overlays 不在本范围内。

本项目不要求 contributor license agreement。提交贡献即表示同意该贡献可以
按照仓库的 MIT license 分发。

## Public-Safe Contributions

创建变更前，请确认 public tree 不包含：

- local machine paths
- private repository mappings
- credentials、tokens、cookies、keys 或 account identifiers
- private audit notes 或 migration findings
- domain-specific sample names 或 private operational details

## Validation

提议变更前建议运行：

```powershell
git diff --check
pwsh -NoProfile -NonInteractive -File .\scripts\invoke-local-validation.ps1 -Stage iteration
pwsh -NoProfile -NonInteractive -File .\scripts\invoke-local-validation.ps1 -Stage pre-push
```

installer-specific smoke 由 affected validation / classifier 决定，不作为所有
贡献的默认命令。

C3.3 validation control plane 和规范 repository validation entrypoints 要求
使用 PowerShell Core 7.6 或更高版本，并通过
`pwsh -NoProfile -NonInteractive -File` 调用。fresh project 使用
`project-bootstrap` 和 `project-workspace`；existing legacy project 使用
`scripts/migrate-project.ps1` 的 Analyze -> Apply -> guarded Rollback 流程。

普通 pull request 通过 classifier-selected 的 `iteration` 和 `pre-push` 路径
验证 affected diff。thin main-push health check 与完整 Release/checkpoint
validator 是两个独立边界；普通 documentation pull request 不要默认运行完整
Release validator，除非已有明确的 Release/checkpoint 决定。

修改 PowerShell 时，提交前先解析脚本：

```powershell
Get-ChildItem -Recurse -File -Include *.ps1 scripts,skills,knowledge-hub |
  ForEach-Object {
    $text = Get-Content -LiteralPath $_.FullName -Raw
    [scriptblock]::Create($text) | Out-Null
  }
```

修改 README、docs entrypoint、release notes 或 release process 时，还应在创建
pull request 前完成轻量的 [Public Reader Review](docs/release-process.md#public-reader-review)。
