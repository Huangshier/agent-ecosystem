# Language Policy

## Public Documentation

`README.md` is the project's chosen Simplified Chinese repository homepage.
`README.en.md` is the English entrypoint. `README.zh-CN.md` is kept as a
compatibility redirect for older links.

Deeper public documentation may remain English-first unless a file, issue, or
translation effort explicitly targets another language.

## Conversation And Artifact Routing

User-facing conversation can follow the user's current language. Repository
artifacts should follow the target artifact's audience and project policy
instead of copying the conversation language automatically.

For public/private workflows:

- root README routing follows the public documentation policy above
- deeper public community-facing docs, release notes, and knowledge hub entries
  may stay English-first unless they are explicit translations
- private control docs and private memory follow the private repository's
  `.agents/AGENTS.md`
- project-local memory follows the target project's `.agents/AGENTS.md`
- code identifiers, commands, paths, APIs, file names, Markdown field labels,
  and raw error text may stay in English or their original form

The reusable knowledge standard is
[Bilingual Public/Private Routing](../knowledge-hub/knowledge/standards/bilingual-public-private-routing.md).

## Project Memory

Project memory should follow the language declared by that project's
`Project Language Policy`. The authoritative declaration belongs in the
project's `.agents/AGENTS.md`.

Bootstrap templates install a `Project Language Policy` section into
`.agents/AGENTS.md`. If the project has not chosen a language yet, the first
non-trivial session that writes engineering memory should fill that section
from the user's primary language.

`project-bootstrap` provides a script-driven closeout path for that first
write. An agent or workflow can pass the user's primary language explicitly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -ProjectLanguage en
powershell -NoProfile -ExecutionPolicy Bypass -File .\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -ProjectLanguage zh-CN
```

On non-Windows systems, or when PowerShell 7+ is already available, use
`pwsh -NoProfile -File` with the same script arguments.

The helper does not infer chat language by itself. It writes the supplied
language into `.agents/AGENTS.md` and localizes the initial project memory
scaffolds for hot memory, `.agents/context/`, `.agents/commands/`, and
`docs/specs/`.

Project memory scaffolds are backed by tracked file templates under
`knowledge-hub/templates/languages/<language>/project-root|project-agent/` as
the repository authority, with a bundled runtime snapshot under
`skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/<language>/project-root|project-agent/`.
The only first-class template languages are `en` and `zh-CN`; this is not
arbitrary-language i18n. English is the public default and fallback language,
so plain bootstrap is equivalent to `-ProjectLanguage en`. If a `zh-CN`
template file is missing, the helper falls back to the matching English
template and reports fallback metadata so validation can flag the gap.

For established project memory, changing the project memory language is a
conservative migration task, not a scaffold overwrite. Bootstrap preserves
existing files by default; migration work should follow a backup, analyze,
plan, review, apply, and validate flow. Force reset options are only for
intentional scaffold reset scenarios where project-specific memory can be
discarded.

The supported conservative language migration flow is explicit about direction:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -AnalyzeLanguageMigration -SourceLanguage en -TargetLanguage zh-CN
powershell -NoProfile -ExecutionPolicy Bypass -File .\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -PlanLanguageMigration -SourceLanguage en -TargetLanguage zh-CN
powershell -NoProfile -ExecutionPolicy Bypass -File .\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -ApplyLanguageMigration -MigrationPlan <proposal.json>
powershell -NoProfile -ExecutionPolicy Bypass -File .\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -ValidateLanguageMigration -MigrationPlan <proposal.json>
powershell -NoProfile -ExecutionPolicy Bypass -File .\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -PlanNarrativeMigration -MigrationPlan <proposal.json>
powershell -NoProfile -ExecutionPolicy Bypass -File .\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -ApplyNarrativeMigration -MigrationPlan <narrative-proposal.json>
powershell -NoProfile -ExecutionPolicy Bypass -File .\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -ValidateNarrativeMigration -MigrationPlan <narrative-proposal.json>
```

Use `-SourceLanguage zh-CN -TargetLanguage en` for the reverse direction. Plan
mode writes a reviewable proposal and creates the backup required by apply.
Apply mode refuses to write if the proposal, backup, or planned source hashes no
longer match. Apply and validate also refuse a proposal whose recorded project
path differs from the current `-ProjectDir`.

The narrative follow-up reads retained manual-review artifacts and creates a
second proposal. It routes stable facts to durable context, active plan and
process state to concise hot memory updates, reusable lessons to
`.agents/context/experience/`, and durable specs to `docs/specs/`. Narrative
actions are unapproved by default; review the proposed target-language text
before applying it.

The file templates are structural baselines for scaffold generation, language
updates, and conservative migration planning. They are not a reason to replace
customized project memory with generic scaffolds. Exact source-template matches
can be replaced with target-language templates. Project-specific narrative that
cannot be safely migrated deterministically is preserved verbatim and routed to
manual review instead of being silently translated or dropped. Concise hot
memory files route original source content to migration artifacts instead of
appending the full source back into `.agents/plan.md`,
`.agents/process.txt`, or `.agents/notes.md`.

Memory governance and upgrade diagnostics recognize English discovery headings
and localized Simplified Chinese equivalents for context discovery metadata.
Public templates remain English-first.

Filenames, directory names, Markdown field labels, commands, paths, API names,
and error text should remain in English or in their original form.
