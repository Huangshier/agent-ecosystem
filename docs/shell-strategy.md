# Shell Strategy

Agent Ecosystem automation is PowerShell-first for the public Workflow Kernel.
The canonical install, uninstall, validation, bootstrap, context-gate, and
maintenance entrypoints are the checked-in `.ps1` scripts.

## Current Support

- Required runtime: PowerShell 7.6 LTS with `pwsh -NoProfile -File` on Windows,
  Ubuntu, macOS, and other environments where PowerShell 7.6 is available.
- Windows PowerShell 5.1 is not supported and `powershell.exe` is not used by
  the public scripts.
- CI path: `.github/workflows/release-validation.yml` runs the release validator
  with `pwsh` on Windows, Ubuntu, and macOS.

## Non-PowerShell Shells

No Bash or Zsh wrappers are shipped in the current public release line. Users in
POSIX shells should install PowerShell 7.6 and call the canonical `.ps1`
entrypoints through `pwsh -NoProfile -File`.

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
