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

The active C3.3 Runtime packages `project-workspace`, so that Skill and
`project-bootstrap` may be exposed through this existing bridge. The retired
`project-context-gate`, `memory-governance`, and `workflow-spec-lite` Skills are
not installed by the active runtime and cannot be newly bridged. Project-local
or promoted Skills are separate project authority and must not be represented
as packaged runtime ownership by this bridge.

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
  -Skill project-bootstrap,project-workspace
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
behavior, and it does not grant implicit high-risk execution authorization or
invoke a Skill. It does not build Skill chains, schedulers, or orchestrators.

## Read-Only Status

`scripts/status.ps1 -RuntimeDir <runtime>` reports live health only for links
explicitly recorded in that runtime's bridge manifest. It never searches for
Codex, Claude Code, or another client, and it does not scan a target parent or
client skill directory. `not-configured` means only that
`agent-skill-bridge-manifest.json` is absent from the selected runtime; manually
created links may still exist elsewhere.

The bridge status combines the bridge manifest contract, case-exact ownership
from the already parsed install manifest, the canonical runtime skill source,
and the live target link:

- `current`: every recorded link safely resolves to its owned runtime copy;
- `stale`: recorded metadata or configuration no longer matches this runtime;
- `broken`: a recorded link or its expected runtime source is unavailable;
- `conflict`: the target is occupied by non-link or unexpected linked content;
- `unknown`: the manifest, record, path, or link cannot be trusted or resolved;
- `not-configured`: the bridge manifest is absent.

For mixed records, the deterministic priority is `conflict`, `broken`, `stale`,
`unknown`, then `current`. JSON and text output include canonical skill names,
statuses, and link modes, but never include runtime, manifest, source, target,
home-directory, or raw exception data. Status is fail-soft and read-only: it
does not create, repair, rebuild, or delete links or client content.

Live bridge health proves the recorded filesystem discovery chain only. It is
not evidence that an agent client supports every skill field, tool, hook,
instruction, or runtime behavior.
