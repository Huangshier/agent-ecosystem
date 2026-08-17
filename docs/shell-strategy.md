# Shell Strategy

Agent Ecosystem automation 对 public Workflow Kernel 采用 PowerShell-first
策略。canonical install、uninstall、validation、bootstrap、workspace、migration
和 maintenance entrypoints 都是仓库中受版本控制的 `.ps1` scripts。

## Current Support

- C3.3 validation control plane 和规范 repository validation entrypoints 要求
  使用 PowerShell Core 7.6 或更高版本，并通过
  `pwsh -NoProfile -NonInteractive -File` 调用。
- 这些 validation entrypoints 不支持 `powershell.exe` fallback。
- active Runtime Skills 是 `project-bootstrap` 和 `project-workspace`。
  retired 的 `project-context-gate`、`workflow-spec-lite` 和
  `memory-governance` 路径不是当前 Runtime entrypoints。
- fresh project 直接进入 C3.3 workspace。existing legacy project 通过
  `scripts/migrate-project.ps1` 执行 Analyze -> explicit Apply -> guarded
  Rollback。
- pull request 在 `iteration` 和 `pre-push` 执行 classifier-selected affected
  validation；push 到 `main` 只运行 thin main health。完整 Release validator
  仅保留给明确的 Release/checkpoint 决定。

## Non-PowerShell Shells

当前 public release line 不提供 Bash 或 Zsh wrappers（No Bash or Zsh wrappers）。通过 POSIX shell 运行
规范 repository validation entrypoints 的用户应安装 PowerShell 7.6，并通过
`pwsh -NoProfile -NonInteractive -File` 调用它们。

未来的 Bash 或 Zsh 支持只能是 thin compatibility layer，而不是第二套
implementation。wrapper 可以定位 `pwsh`、规范化参数并委托给 canonical
PowerShell script，但不得复制 install、uninstall、context discovery、release
validation 或 manifest cleanup logic。

## Future Options

未来 Release 可以考虑以下路径之一：

- Thin POSIX wrappers that delegate to `pwsh`.
- Package-manager installation snippets that install PowerShell 7.6 first and
  then call the canonical `.ps1` scripts.
- A small cross-platform binary only if repeated usage proves that script
  wrappers are not enough.

任何 non-PowerShell entrypoint 发布前，release gate 都应在 Ubuntu 和 macOS
上验证它，记录与 `.ps1` script 相同的 argument contract，并证明其行为没有
偏离 canonical PowerShell behavior。
