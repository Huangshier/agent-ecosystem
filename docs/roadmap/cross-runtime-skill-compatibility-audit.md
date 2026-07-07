# Cross-Runtime Skill Compatibility Audit

Status: first slice (audit + matrix). Issue #165.
Verification date: 2026-07-07.

This document audits the current agent-ecosystem kernel skills against
four target runtimes: the Agent Skills open standard (agentskills.io),
Claude Code, OpenAI Codex, and GitHub Copilot. It produces a
compatibility matrix with four alignment categories and identifies safe
next steps.

This audit does **not** change any skill format, metadata, trigger
mechanism, or runtime behavior.

## Scope and Non-Goals

**Scope**: compare file structure, metadata fields, trigger mechanisms,
validation entry points, and discovery paths across four runtimes.

**Non-Goals**:
- No bulk SKILL.md or frontmatter migration.
- No runtime behavior changes.
- No new trigger mechanisms.
- No external marketplace or registry integration.
- No claims of full compatibility without verified evidence.

## Current Kernel Skills Baseline

agent-ecosystem ships four kernel skills under `skills/`:

| Skill | Key Scripts | Output Surface |
| --- | --- | --- |
| `workflow-spec-lite` | `validate_spec.ps1` | `docs/specs/<slug>/spec.md`, `tasks.md` |
| `project-bootstrap` | `bootstrap_project.ps1` + 8 helpers | `.agents/` scaffold, `knowledge-hub/` |
| `project-context-gate` | `context_gate.ps1` | Inventory-only, no writes |
| `memory-governance` | `memory_diagnose.ps1` | `.agents/` memory files |

### File Structure

```
skills/<skill-name>/
  SKILL.md              # Metadata + instructions
  README.md             # Human-readable overview
  agents/openai.yaml    # Parallel agent interface config
  scripts/*.ps1         # PowerShell validation/automation
  references/*.md       # Bundled templates and guides (optional)
  assets/               # Bundled template snapshots (optional)
```

### Frontmatter Fields

| Field | Required | Current Values |
| --- | --- | --- |
| `name` | Yes | Kebab-case identifier matching directory name |
| `description` | Yes | Multi-sentence usage description |
| `category` | Yes | `kernel` (all four) |
| `stability` | Yes | `stable` (all four) |
| `scope` | Yes | `cross-project` (all four) |
| `metadata` | Yes | Mirrors `category`, `stability`, and `scope` as an additive compatibility map |
| `compatibility` | Yes | Documents PowerShell 7+ script requirements and alias support |

Additional metadata lives in `agents/openai.yaml` (display_name,
short_description, default_prompt). This is a parallel layer, not
frontmatter and not evidence of Codex Agent Skills compatibility by
itself.

### Trigger Mechanism

Skills are triggered by **natural language matching** against the
`description` field, supplemented by explicit negative triggers in
the SKILL.md body (e.g., "Do not use for tiny local fixes"). There
is no keyword index or regex; the agent model evaluates relevance.

### Validation Entry Points

Every kernel skill includes at least one PowerShell script that
produces structured JSON output. The release validator
(`scripts/validate-release.ps1`) exercises these scripts as part
of the release gate.

---

## Runtime Comparison Matrix

### A. Agent Skills Open Standard (agentskills.io)

**Source**: https://agentskills.io, https://github.com/agentskills/agentskills

The Agent Skills standard defines a skill as a directory containing
`SKILL.md` with YAML frontmatter. It is the cross-client interop
baseline.

| Dimension | Standard | agent-ecosystem | Alignment |
| --- | --- | --- | --- |
| Core file | `SKILL.md` | `SKILL.md` | **safe-to-align** |
| Directory-based | Yes | Yes | **safe-to-align** |
| `name` field | Required, kebab-case, 1-64 chars | Present, kebab-case | **safe-to-align** |
| `description` field | Required, 1-1024 chars, trigger mechanism | Present, multi-sentence | **safe-to-align** |
| `scripts/` directory | Optional, self-contained executables | Present, PowerShell | **safe-to-align** (structure) |
| `references/` directory | Optional, on-demand docs | Present | **safe-to-align** |
| `assets/` directory | Optional | Present in project-bootstrap | **safe-to-align** |
| `license` field | Optional | Not present | needs-follow-up |
| `compatibility` field | Optional, max 500 chars | Present, conservative PowerShell/runtime note | **safe-to-align** |
| `metadata` map | Optional, arbitrary key-values | Present, mirrors `category`, `stability`, `scope` | **safe-to-align** |
| `allowed-tools` field | Experimental | Not present | needs-follow-up |
| `category` field | Not in standard | `kernel` | **requires-adapter** (custom field) |
| `stability` field | Not in standard | `stable` | **requires-adapter** (custom field) |
| `scope` field | Not in standard | `cross-project` | **requires-adapter** (custom field) |
| Discovery path | `.agents/skills/` (canonical) | `skills/` (repo root) | **requires-adapter** |
| Eval format | `evals/evals.json` per skill | Fixture-based, repo-level | **requires-adapter** |
| Script runtime | Python/Bash/Deno/Bun/Ruby | PowerShell | **do-not-change** (platform) |
| `agents/openai.yaml` | Not in standard | Present | **requires-adapter** |

### B. Claude Code

**Source**: https://docs.anthropic.com/en/docs/claude-code/skills,
https://docs.anthropic.com/en/docs/claude-code/memory

Claude Code follows the Agent Skills standard with additional
frontmatter fields and its own discovery paths.

| Dimension | Claude Code | agent-ecosystem | Alignment |
| --- | --- | --- | --- |
| Core file | `SKILL.md` | `SKILL.md` | **safe-to-align** |
| Discovery path | `.claude/skills/` | `skills/` | **requires-adapter** |
| `description` field | Recommended, 1536 char limit | Present | **safe-to-align** |
| `when_to_use` field | Optional, appended to description | Not present | needs-follow-up |
| `disable-model-invocation` | Optional bool | Not present | needs-follow-up |
| `user-invocable` | Optional bool | Not present | needs-follow-up |
| `allowed-tools` | Optional | Not present | needs-follow-up |
| `model` / `effort` override | Optional | Not present | needs-follow-up |
| `context: fork` | Optional, subagent isolation | Not present | needs-follow-up |
| `paths` (glob scoping) | Optional | Not present | needs-follow-up |
| `arguments` / `argument-hint` | Optional | Not present | needs-follow-up |
| Slash command trigger | `/skill-name` | Not available | **requires-adapter** |
| Auto-detection trigger | Description-based LLM matching | Description-based LLM matching | **safe-to-align** |
| Dynamic injection (`!`command) | Supported | Not used | needs-follow-up |
| CLAUDE.md integration | Native | Not native (uses AGENTS.md) | **requires-adapter** |
| `agents/openai.yaml` | Not recognized | Present | **do-not-change** (parallel layer) |

### C. OpenAI Codex

**Source**: https://developers.openai.com/codex/skills and
https://developers.openai.com/codex/skills.md, with source-code checks
remaining useful for AGENTS.md, config.toml, and hook behavior.

**Verification tier**: Tier 1 official documentation for Codex Agent
Skills format, discovery locations, progressive disclosure, and explicit
or implicit skill invocation. Tier 1 source code remains evidence for
AGENTS.md loading, config.toml structure, and hook system.

| Dimension | Codex (verified) | agent-ecosystem | Alignment |
| --- | --- | --- | --- |
| Agent instructions | `AGENTS.md` for project guidance | Project memory templates generate `AGENTS.md` | **safe-to-align** (project guidance) |
| Skill file | Skill directory with `SKILL.md` frontmatter and optional resources | `skills/<skill>/SKILL.md` plus optional scripts/references/assets | **safe-to-align** (format) |
| Skill discovery path | Repository `.agents/skills` from CWD to repo root; user `$HOME/.agents/skills`; admin `/etc/codex/skills`; system bundled skills | Public source uses repo-root `skills/`; generated projects do not create `.agents/skills` wrappers | **requires-adapter** |
| Progressive disclosure | Starts with skill name, description, and file path; loads full `SKILL.md` when selected | `name` and `description` are present; body follows progressive disclosure guidance | **safe-to-align** |
| Explicit invocation | CLI/IDE can use `/skills` or `$` skill mention | No generated `/skills` command card before this slice; no runtime adapter | **requires-adapter** |
| Implicit invocation | Matches task to `description` | Natural-language matching against `description` | **safe-to-align** |
| Optional Codex metadata | `agents/openai.yaml` for Codex app UI metadata, invocation policy, and tool dependencies | Skill-level `agents/openai.yaml` exists | **requires-adapter** (do not treat as proof of compatibility) |
| Config format | TOML (`config.toml`) | YAML frontmatter + YAML agents config | **do-not-change** |
| Project root detection | Configurable markers (default `.git`) | N/A (repo-level skill) | **do-not-change** |
| Hook system | 10 event types, TOML-based | Not present | needs-follow-up |

**Boundary**: Codex now has official Agent Skills documentation. This
does not mean the public repository's root `skills/` directory is
automatically discoverable by Codex in every installation. A future
adapter or installation-surface PR would need to prove the generated
paths and invocation behavior locally.

### D. GitHub Copilot

**Source**: https://docs.github.com/en/copilot/concepts/agents/about-agent-skills
and
https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-skills.

GitHub Copilot documents Agent Skills support for several Copilot
surfaces and supports both project and personal skill locations.

| Dimension | GitHub Copilot | agent-ecosystem | Alignment |
| --- | --- | --- | --- |
| Core file | `SKILL.md` with YAML frontmatter | `SKILL.md` | **safe-to-align** |
| Required fields | `name`, `description`; `license` optional | `name`, `description` present; `license` absent | needs-follow-up |
| Project discovery paths | `.github/skills`, `.claude/skills`, `.agents/skills` | Public source uses repo-root `skills/` | **requires-adapter** |
| Personal discovery paths | `~/.copilot/skills`, `~/.agents/skills` | Not managed by this repo | **do-not-change** |
| CLI skill commands | `/skills list`, `/skills info`, `/skills reload`, `/skills add`, `/skills remove`; `copilot skill` terminal subcommands | No generated skills command card before this slice | **requires-adapter** |
| Explicit skill prompt | Skill name can be referenced with a slash in prompts | No generated command guidance before this slice | **requires-adapter** |
| `allowed-tools` | Optional; shell preapproval carries explicit safety warnings | Not present | needs-follow-up / **do-not-change by default** |

---

## Alignment Category Definitions

| Category | Meaning | Action |
| --- | --- | --- |
| **safe-to-align** | Current practice matches or is compatible with the target standard. No adapter needed. | Document as-is; optionally formalize in spec. |
| **requires-adapter** | Current practice differs from target but can be bridged with a thin adapter layer. | Design adapter in a follow-up PR; do not change current format. |
| **do-not-change** | Current practice is intentionally different (platform choice, parallel layer, architectural decision). | Document the rationale; do not attempt alignment. |
| **needs-follow-up** | Cannot determine alignment without more evidence (missing docs, experimental feature, unverified runtime). | Track as open research item; do not speculate. |

---

## Cross-Field Mapping: Safe-to-Align

These fields and structural conventions are directly portable between
agent-ecosystem, the Agent Skills standard, Claude Code, OpenAI Codex,
and GitHub Copilot as a SKILL.md authoring format. Discovery locations
and runtime invocation remain separate adapter questions.

| agent-ecosystem | agentskills.io | Claude Code | Codex | GitHub Copilot |
| --- | --- | --- | --- | --- |
| `name` | `name` | `name` (optional, defaults to dir) | `name` | `name` |
| `description` | `description` | `description` (recommended) | `description` | `description` |
| `SKILL.md` filename | `SKILL.md` | `SKILL.md` | `SKILL.md` | `SKILL.md` |
| `scripts/` dir | `scripts/` | `scripts/` | `scripts/` | Skill directory resources |
| `references/` dir | `references/` | N/A | `references/` | Supplementary Markdown/resources |
| Directory-based skill | Yes | Yes | Yes | Yes |

## Cross-Field Mapping: Requires Adapter

These current fields or conventions need a translation layer:

| Current | Target | Adapter Approach |
| --- | --- | --- |
| `category: kernel` | `metadata.category` (agentskills.io `metadata` map) | Move to `metadata` map: `metadata: { category: kernel }` |
| `stability: stable` | `metadata.stability` | Move to `metadata` map |
| `scope: cross-project` | `metadata.scope` | Move to `metadata` map |
| `skills/` path | `.agents/skills/`, `.claude/skills/`, `.github/skills`, or runtime/user skill locations | Symlink, copy, install profile, or wrapper; requires tested adapter |
| `agents/openai.yaml` | Codex-specific optional metadata in Codex docs; not part of agentskills.io | Keep as parallel layer; do not remove; do not use alone as compatibility evidence |
| PowerShell scripts | Cross-runtime script exec | Document `pwsh` requirement in `compatibility` field |
| `/skills` discovery | Codex and Copilot have documented `/skills` surfaces | Provide project command-card guidance first; runtime behavior still belongs to each client |

## Do-Not-Change Items

These are intentional differences that should be preserved:

| Item | Rationale |
| --- | --- |
| PowerShell scripts | Platform-specific tooling choice; Windows-first project. Documented requirement, not a format issue. |
| `agents/openai.yaml` | Parallel metadata layer. Do not use it by itself as proof that this repository is loaded as a Codex Agent Skill. |
| Codex config format (TOML) | Codex's native config; agent-ecosystem does not need to adopt TOML. |

## Needs-Follow-Up Items

| Item | Why | Resolution Path |
| --- | --- | --- |
| `allowed-tools` (agentskills.io) | Marked "experimental" in standard | Monitor adoption across clients |
| `when_to_use` (Claude Code) | Optional but potentially useful for trigger precision | Evaluate if description field is insufficient |
| `context: fork` (Claude Code) | Subagent isolation; agent-ecosystem has its own delegation model | Compare delegation patterns |
| `disable-model-invocation` | Controls auto-detection; agent-ecosystem relies on description matching | Evaluate for sensitive skills |
| Claude Code `paths` scoping | Glob-based auto-activation; not currently needed | Evaluate when monorepo use cases emerge |
| Dynamic injection (`!`command) | Claude Code feature for shell output injection | Evaluate for context-gate skill |
| `license` field | Standard optional field | Add to frontmatter when license is finalized |
| Runtime discovery adapters | Each client has specific load paths and commands | Keep separate from metadata alignment until tested |

---

## Suggested PR Sequence

The following PRs are ordered from lowest risk to highest. Each PR
should be independently reviewable and revertable.

### PR 1: Frontmatter metadata map migration (completed by #193)

Move `category`, `stability`, `scope` into a `metadata` map to
align with agentskills.io standard. Keep the three original fields
as read-compatibility aliases during a transition period.

Risk: low. Metadata only; no behavior change.
Validation: existing release checks + new frontmatter shape check.

### PR 2: Add `compatibility` and `license` fields (partially completed by #194)

Add `compatibility: Requires PowerShell 7+` to all kernel skills.
Add `license` field later if the project decides that skill-level
license metadata should be explicit.

Risk: low. Additive frontmatter only.
Validation: frontmatter field presence check.

### PR 3: Skills discovery command card

Add `.agents/commands/skills.md` to generated project memory templates.
This is read-only discovery guidance: list existing skill locations,
read `SKILL.md` frontmatter, and report available skills without
installing, enabling, validating, or claiming client compatibility.

Risk: low. Template/documentation only; no runtime behavior change.
Validation: template/snapshot existence and hash consistency checks.

### PR 4: Discovery path adapter

Create `.agents/skills/` symlink or thin wrapper that points to
the existing `skills/` directory. This enables cross-client
discovery without changing the canonical location.

Risk: medium. Affects discovery behavior; needs testing across
Claude Code and agentskills.io validator.
Validation: symlink existence + skill load test.

### PR 5: Claude Code integration surface

Document the `CLAUDE.md` → `AGENTS.md` import pattern. Optionally
add `.claude/skills/` wrappers or symlinks for native Claude Code
discovery.

Risk: medium. Affects Claude Code integration.
Validation: Claude Code skill loading test.

### PR 6: Eval format alignment

Migrate from repo-level fixture validation to per-skill
`evals/evals.json` format as defined by agentskills.io. This
builds on the #166 eval iteration work.

Risk: medium. Changes eval structure; needs fixture migration.
Validation: existing eval iteration checks adapted to new format.

### PR 7: Codex compatibility surface

Create Codex-compatible `.agents/skills` wrappers, install profile
behavior, or config entries only after a local Codex loading test proves
the selected public path and invocation behavior.

Risk: medium/high. Official docs exist, but this repository's generated
paths and installation behavior still need local validation.
Validation: Codex CLI skill loading test.

---

## Evidence Sources

| Source | Tier | URL |
| --- | --- | --- |
| Agent Skills standard | Verified | https://agentskills.io |
| Agent Skills GitHub | Verified | https://github.com/agentskills/agentskills |
| Claude Code skills docs | Verified | https://docs.anthropic.com/en/docs/claude-code/skills |
| Claude Code memory docs | Verified | https://docs.anthropic.com/en/docs/claude-code/memory |
| Codex Agent Skills docs | Verified | https://developers.openai.com/codex/skills and https://developers.openai.com/codex/skills.md |
| GitHub Copilot Agent Skills docs | Verified | https://docs.github.com/en/copilot/concepts/agents/about-agent-skills and https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-skills |
| Codex source code | Verified (Tier 1) | https://github.com/openai/codex (Apache-2.0). Key files: `codex-rs/core/src/agents_md.rs` (AGENTS.md loading), `codex-rs/core/src/config_toml.rs` (TOML config), `codex-rs/core/src/hook_config.rs` (hook system). |

**Tier definitions**:
- Tier 1: Official source code or primary documentation, directly read.
- Tier 2: Official site confirmed to exist but content inaccessible.
- Tier 3: Secondary sources (blogs, community posts, search results).
  Not used for confirmation claims.
