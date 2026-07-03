# Claude Code Guardrail Hooks

`.claude/settings.json` registers `guardrail.ps1` for the `SessionStart`,
`PreToolUse`, and `Stop` lifecycle events. The runner reads the event JSON from
stdin and returns only the minimal structured stdout decision needed by Claude
Code. It does not persist hook input, transcripts, or an event ledger.

This README is operational documentation and is not imported by `CLAUDE.md`.
The settings file activates the runtime; `CLAUDE.md` keeps the project context
and static guardrails contract that the runtime validates but does not replace.

The runtime checks that the generated entrypoint and project context exist,
uses `.claude/guardrails/profile.json` as its write-authorization contract,
denies writes outside the project or obvious raw-artifact publication paths,
asks for confirmation before local-only external writes or dangerous memory
refresh operations, and reports `needs-human` when required context is absent.
Command-risk checks cover the native `Bash` and `PowerShell` tools plus the
command form of `Monitor`. A Monitor WebSocket source has no command and remains
under Claude Code's own host approval and network policy.

The default `local-only` profile does not authorize external writes. The
`public-contributor` profile keeps ordinary issue, fork pull request, CI, and
maintainer review paths available without requiring a bot. Projects may change
`default_profile` only when their own instructions declare that profile.

These hooks improve template reliability. They are not a security sandbox,
permission isolation, or a substitute for Claude Code permissions and
maintainer review. The runner intentionally stays silent when it has no
decision so the normal permission flow still applies.

PowerShell 7 (`pwsh`) must be available on `PATH`. Run the offline validator
after changing the settings, runner, profile, or templates:

```powershell
pwsh -NoProfile -File scripts/validation/test-claude-hooks-runtime.ps1
```
