# Project Context Gate

Repository context gate for long-running agent work.

## Purpose

This skill makes project guidance explicit before non-trivial repository tasks. It tells the agent to reload root `AGENTS.md`, `.agents/AGENTS.md`, project memory, active specs, and git state before planning or continuing a long task.

## When It Runs

- Before non-trivial implementation, debugging, migration, research, or multi-file edits
- Before memory governance or `.agents/` project-memory edits
- After a phase commit when continuing to the next phase
- After context compaction, resume, or interruption
- After the user corrects a project rule or workflow assumption

Do not run it mechanically before every search, edit, validation command, or commit. Within one continuous objective, reuse the already-loaded context unless a phase boundary, resume, correction, repository/toolchain switch, or active spec change makes the context stale.

## Files

```
project-context-gate/
|-- SKILL.md
|-- README.md
|-- agents/
|   `-- openai.yaml
`-- scripts/
    `-- context_gate.ps1
```

## Helper

Run the helper from a repository root to list the context files that should be loaded:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/context_gate.ps1 -ProjectRoot .
```

Use `pwsh -NoProfile -File` with the same arguments on non-Windows systems or
when PowerShell 7+ is already available.

The helper inventories files and git state; the agent still reads and applies the listed context. It also reports a read-only project template status by invoking only the trusted runtime/source `scripts/status.ps1` derived from the current skill path. It does not search for or execute a target-project helper.

For a compact, copyable agent brief, request brief output:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/context_gate.ps1 -ProjectRoot . -Brief
```

It reports context in progressive disclosure tiers:
- Hot: load immediately for most non-trivial work.
- Warm: active `docs/specs` work package.
- Cold: context indexes, notes, and other memory to open only when relevant.

Optional flags:
- `-Json`: structured output.
- `-Brief`: compact agent brief with gate type, project root, git state,
  hot/warm/cold context responsibilities, warnings, and next action.
- `-IncludeTemplates`: include every `.agents/context/` file for audits.

## Project Template Status

Default text, `-Brief`, and `-Json` output all include the project template status. The JSON contract is:

```text
project_template
|-- status
|-- reason
|-- project_language
|-- guidance
|-- command
`-- helper
    |-- availability
    `-- trust
```

`current` has no warning or command. `optional-refresh` warns and may provide a quoted `bootstrap_project.ps1 -RefreshUnmodifiedTemplates` command when `project_language` is validated. `migration-required` provides only the read-only `memory_upgrade.ps1 -Mode Analyze -Json` command. `unknown` requests manual inspection and never guesses a language or command.

Status invocation and payload validation are fail-soft. Missing helpers, non-zero exits, malformed JSON, incompatible schemas, invalid status/reason/language values, and helper exceptions do not stop normal context inventory. Raw helper output, exceptions, stderr, findings, messages, and paths are not copied into context-gate output. Suggested commands are advisory and are never executed by the context gate.

## License

MIT
