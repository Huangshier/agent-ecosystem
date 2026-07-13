# Project Memory Guide

Project behavior rules live exclusively in the root `AGENTS.md`. This guide
describes only the project-memory subsystem and must not duplicate the full
working, authorization, delivery, spec, commit, push, or PR contract.

## Project Memory Language
Project memory language: English.

Write project engineering memory in English by default. Keep file names,
directory names, Markdown field labels, commands, paths, API names, code
identifiers, and raw error text in English or their original form. Public-facing
artifacts follow the language required by their target repository or audience.

## Directory Responsibilities And Memory Routing
- `.agents/process.txt`: current operational status, blockers, and next action.
- `.agents/plan.md`: session-local active task pointer and checklist state.
- `.agents/notes.md`: verified decisions and stable facts worth retaining.
- `.agents/context/tech/`: stable technical facts and terminology.
- `.agents/context/business/`: durable product or business rules.
- `.agents/context/experience/`: repeated pitfalls, fixes, and reusable lessons.
- `.agents/context/experience/cases/`: structured troubleshooting cases.
- `.agents/commands/`: documented reusable project workflows and evidence expectations.
- `docs/specs/<slug>/`: durable work packages when the root contract and project workflow require them.
- `.agents/hub.lock.json`: template source, language, installed hashes, and refresh provenance.

Non-template context entries should include `## Summary` and `## Keywords` near
the top so they can be discovered without preloading the whole directory.

## Progressive Load Order
Load memory progressively after reading the root `AGENTS.md`:

1. **Hot**: `.agents/AGENTS.md`, `.agents/process.txt`, and, for non-trivial work, `.agents/plan.md`.
2. **Warm**: the active `docs/specs/<slug>/spec.md` and `tasks.md` referenced by hot memory.
3. **Cold discovery**: `.agents/context/README.md` and directory indexes, then only entries matching Summary, Keywords, or task relevance; read `.agents/notes.md` only when stable facts are relevant.
4. **Workflow discovery**: `.agents/commands/README.md`, then only the command cards relevant to the current workflow.

Do not preload the full `.agents/context/` or `.agents/commands/` trees.

## Template Source And Conservative Refresh
Canonical project-memory templates live under
`knowledge-hub/templates/languages/<language>/`. Installed runtimes may use the
byte-aligned bundled `project-bootstrap` snapshot. `.agents/hub.lock.json`
records the selected language, template source, and installed template hashes.

Use the project status/context entrypoints to inspect drift. When the root
contract authorizes a refresh, use `bootstrap_project.ps1 -RefreshUnmodifiedTemplates`:
files matching a recorded prior template hash may
be backed up and refreshed, while customized files or files without a trusted
prior hash remain unchanged and are reported for manual review. Use language
migration through its proposal-first, backup-first review flow. Reset is not a
refresh path and requires the explicit authorization defined by the root
`AGENTS.md`.
