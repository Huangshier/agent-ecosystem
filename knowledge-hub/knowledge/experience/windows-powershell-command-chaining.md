# Windows PowerShell Command Chaining

Maturity: verified
Scope: cross-project
Source: migration backfill
Last reviewed: 2026-05-08
Decay policy: Re-review when PowerShell host handling or supported shell guidance changes; otherwise keep verified.

## Keywords
PowerShell, command chaining, &&, cmd /c, shell_command, Windows, parser error

## Problem
- In this Agent Windows host environment, `shell_command` requests are parsed by PowerShell.
- Using `&&` directly in a PowerShell command string can fail with a parser error instead of chaining commands.

## Root Cause
- Command chaining support differs across PowerShell versions and host integrations.
- Agent code that assumes `&&` is always valid in the current PowerShell session is not portable across these environments.

## Fix
- Do not rely on bare `&&` in PowerShell-issued `shell_command` calls.
- Prefer separate tool calls for sequential steps when practical.
- If one shell invocation must chain commands, wrap the chain explicitly with `cmd /d /c "cmd1 && cmd2"`.

## Verification
- Reproduced while committing updates in a Windows Agent session: `git ... add ... && git ... commit ...` failed under PowerShell parsing, while split commands succeeded.

## Prevention Rule
- On Windows, treat `shell_command` as PowerShell by default and only use `&&` when the command is explicitly executed through `cmd /d /c`.
