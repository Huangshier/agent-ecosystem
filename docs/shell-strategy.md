# Shell Strategy

Agent Ecosystem automation is PowerShell-first for the public Workflow Kernel.
The canonical install, uninstall, validation, bootstrap, workspace, migration,
and maintenance entrypoints are the checked-in `.ps1` scripts.

## Current Support

- The C3.3 validation control plane and normative repository validation
  entrypoints require PowerShell Core 7.6 or later through
  `pwsh -NoProfile -NonInteractive -File`.
- Those validation entrypoints do not support a `powershell.exe` fallback.
- The active Runtime Skills are `project-bootstrap` and `project-workspace`.
  Retired `project-context-gate`, `workflow-spec-lite`, and
  `memory-governance` paths are not current Runtime entrypoints.
- Fresh projects bootstrap into the C3.3 workspace. Existing legacy projects
  migrate through `scripts/migrate-project.ps1` with Analyze -> explicit Apply
  -> guarded Rollback.
- Pull requests use classifier-selected affected validation at `iteration` and
  `pre-push`; a push to `main` runs only thin main health. The full Release
  validator is reserved for an explicit Release/checkpoint decision.

## Non-PowerShell Shells

No Bash or Zsh wrappers are shipped in the current public release line. Users
running the normative repository validation entrypoints from POSIX shells
should install PowerShell 7.6 and invoke them through
`pwsh -NoProfile -NonInteractive -File`.

Future Bash or Zsh support should be a thin compatibility layer, not a second
implementation. A wrapper may locate `pwsh`, normalize arguments, and delegate to
the canonical PowerShell script. It should not duplicate install, uninstall,
context discovery, release validation, or manifest cleanup logic.

## Future Options

Future releases may add one of these paths:

- Thin POSIX wrappers that delegate to `pwsh`.
- Package-manager installation snippets that install PowerShell 7.6 first and
  then call the canonical `.ps1` scripts.
- A small cross-platform binary only if repeated usage proves that script
  wrappers are not enough.

Before any non-PowerShell entrypoint ships, the release gate should validate it
on Ubuntu and macOS, document the same argument contract as the `.ps1` script,
and prove that it does not diverge from the canonical PowerShell behavior.
