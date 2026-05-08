# Language Policy

## Public Documentation

Public documentation is English-first. Translations may be provided in
`README.zh-CN.md` or under `docs/zh-CN/`.

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

Filenames, directory names, Markdown field labels, commands, paths, API names,
and error text should remain in English or in their original form.
