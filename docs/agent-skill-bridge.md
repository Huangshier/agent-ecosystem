# Agent-Specific Skill Link Bridge

The agent-specific skill bridge is a separate, explicit opt-in step. Ordinary
`scripts/install.ps1` runs do not inspect, create, or update Codex, Claude Code,
Qwen, Gemini, or any other agent client's skill directory.

## Preconditions

Install a public runtime in copy mode first. The bridge validates that the
selected runtime has a schema-2 `install-manifest.json`, uses
`install_strategy: copy`, and owns every selected
`skills/<skill>` directory. It rejects source checkouts, `-DevLink` runtimes,
unlisted skills, linked runtime skill sources, and manifest items whose managed
destination is not exactly `skills/<skill>`.

Skill ownership is canonical and case-exact across the manifest's `skills`,
`items[].name`, and `items[].destination` fields. A differently cased request
cannot borrow another skill's ownership. Link targets follow platform path
semantics: comparisons are case-insensitive on Windows and case-sensitive on
Linux and macOS.

Both locations are mandatory. The helper has no default for a maintainer or
client-specific user directory:

```powershell
pwsh -NoProfile -File ./scripts/link-agent-skills.ps1 `
  -RuntimeDir <runtime> `
  -AgentSkillsDir <agent-skills-dir> `
  -Skill project-bootstrap,project-context-gate
```

Windows PowerShell 5.1 is also supported:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\link-agent-skills.ps1 `
  -RuntimeDir <runtime> `
  -AgentSkillsDir <agent-skills-dir> `
  -Skill project-bootstrap
```

Use `-Json` when a caller needs a structured result. Without `-Json`, the helper
prints one `[created]` or `[unchanged]` line per requested skill.

## Agent Client Targets

Choose the target directory from the client version and configuration you have
actually verified. The bridge does not auto-detect client installations or
claim full runtime compatibility.

| Client or adapter | Explicit target example |
| --- | --- |
| Codex | `-AgentSkillsDir <codex-skills-dir>` |
| Claude Code | `-AgentSkillsDir <claude-code-skills-dir>` |
| Qwen | `-AgentSkillsDir <qwen-skills-dir>` |
| Gemini | `-AgentSkillsDir <gemini-skills-dir>` |
| Future agent client | `-AgentSkillsDir <future-agent-skills-dir>` |

These placeholders are intentional. Do not replace them in repository examples
with a maintainer's real home directory. For evaluation and validation, use an
isolated temporary runtime and target directory.

## Safety And Metadata

The helper completes preflight for the entire requested skill set before it
creates any link:

- a missing target is eligible for creation;
- a link already targeting the expected installed runtime skill is an
  idempotent no-op;
- an existing non-link path is a conflict;
- a link to any other target is a conflict.

Any preflight conflict exits non-zero without creating links or bridge
metadata. If link creation or manifest writing fails after preflight, links
created by that run are rolled back.

`AgentSkillsDir` must be a non-root directory outside the installed runtime and
outside every selected skill source. The final per-skill target must also be
outside its source, preventing recursive links or writes into managed runtime
content. Before any directory, link, or manifest write, the helper resolves the
nearest existing ancestor and every symbolic-link or junction hop in its
ancestor chain, then appends the still-missing path segments to that canonical
physical location and repeats the containment checks there. Relative symbolic
link targets are supported. Broken links, unresolvable reparse points, link
cycles, and excessive alias chains fail fast without writing. These checks use
path-segment boundaries, so a sibling such as `<root>/runtime-client-skills` is
not treated as a child of `<root>/runtime`.

Successful runs write `<runtime>/agent-skill-bridge-manifest.json`. This file is
independent of the installer schema-2 manifest and records the actual skill,
source, target, result, and link mode. It is local runtime metadata with
`commit_policy: do-not-commit`; never add it or an installed runtime directory
to a source repository.

The helper only establishes filesystem discovery links. It does not verify
that a client supports every skill field, tool, hook, instruction, or runtime
behavior.
