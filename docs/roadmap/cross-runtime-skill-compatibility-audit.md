# Cross-Runtime Skill Compatibility Audit

Status: first slice (audit + matrix). Issue #165.
Verification date: 2026-06-28.

This document audits the current agent-ecosystem kernel skills against
three target runtimes: the Agent Skills open standard (agentskills.io),
Claude Code, and OpenAI Codex. It produces a compatibility matrix with
four alignment categories and identifies safe next steps.

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

Additional metadata lives in `agents/openai.yaml` (display_name,
short_description, default_prompt). This is a parallel layer, not
frontmatter.

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
| `compatibility` field | Optional, max 500 chars | Not present | needs-follow-up |
| `metadata` map | Optional, arbitrary key-values | Not present | **requires-adapter** |
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

**Source**: https://github.com/openai/codex (Apache-2.0, verified
from source code). Official documentation at developers.openai.com/codex
was inaccessible (404/auth) during this audit.

**Verification tier**: Tier 1 (source code) for AGENTS.md loading,
config.toml structure, and hook system. Tier 3 (secondary sources)
for skill subsystem details.

| Dimension | Codex (verified) | agent-ecosystem | Alignment |
| --- | --- | --- | --- |
| Instruction file | `AGENTS.md` (plain Markdown, no frontmatter) | `SKILL.md` (YAML frontmatter) | **requires-adapter** |
| Override file | `AGENTS.override.md` per directory | Not present | needs-follow-up |
| Config format | TOML (`config.toml`) | YAML frontmatter + YAML agents config | **do-not-change** |
| Project root detection | Configurable markers (default `.git`) | N/A (repo-level skill) | **do-not-change** |
| Hierarchical loading | Root-to-cwd directory walk | Not applicable (single skill file) | **requires-adapter** |
| Max instruction size | `project_doc_max_bytes` (configurable) | No explicit limit | needs-follow-up |
| Fallback filenames | Configurable via `project_doc_fallback_filenames` | Not applicable | needs-follow-up |
| Hook system | 10 event types, TOML-based | Not present | needs-follow-up |
| Skills subsystem | Name/path-based selectors (TOML) | Directory-based SKILL.md | needs-follow-up (low verification) |
| Slash commands | Not documented | Not applicable | needs-follow-up |
| `agents/openai.yaml` | Not recognized by Codex | Present | **do-not-change** (parallel layer) |

**Note on Codex skills subsystem**: The Codex source code includes a
`skills_config.rs` with name/path-based selectors, but the official
documentation was inaccessible. The exact mapping between Codex's
skill config and the Agent Skills standard's SKILL.md format is
**not verified**. Follow-up needed when official docs become available.

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
agent-ecosystem, the Agent Skills standard, and Claude Code with no
adapter. Codex uses a fundamentally different format (plain Markdown
`AGENTS.md` with no YAML frontmatter), so these fields are N/A for
Codex and would require a separate `AGENTS.md`-facing surface or
adapter to expose.

| agent-ecosystem | agentskills.io | Claude Code | Codex |
| --- | --- | --- | --- |
| `name` | `name` | `name` (optional, defaults to dir) | N/A → requires AGENTS.md adapter |
| `description` | `description` | `description` (recommended) | N/A → requires AGENTS.md adapter |
| `SKILL.md` filename | `SKILL.md` | `SKILL.md` | N/A (`AGENTS.md`) |
| `scripts/` dir | `scripts/` | `scripts/` | N/A (TOML config selectors) |
| `references/` dir | `references/` | N/A | N/A |
| Directory-based skill | Yes | Yes | Config-based selectors |

Codex compatibility for these fields is addressed in the
"Cross-Field Mapping: Requires Adapter" section below.

## Cross-Field Mapping: Requires Adapter

These current fields or conventions need a translation layer:

| Current | Target | Adapter Approach |
| --- | --- | --- |
| `category: kernel` | `metadata.category` (agentskills.io `metadata` map) | Move to `metadata` map: `metadata: { category: kernel }` |
| `stability: stable` | `metadata.stability` | Move to `metadata` map |
| `scope: cross-project` | `metadata.scope` | Move to `metadata` map |
| `skills/` path | `.agents/skills/` or `.claude/skills/` | Symlink or install script |
| `agents/openai.yaml` | N/A (no standard equivalent) | Keep as parallel layer; do not remove |
| PowerShell scripts | Cross-runtime script exec | Document `pwsh` requirement in `compatibility` field |
| SKILL.md frontmatter → Codex | `AGENTS.md` plain text (no frontmatter) | Generate `AGENTS.md` from `name` + `description` + body content |

## Do-Not-Change Items

These are intentional differences that should be preserved:

| Item | Rationale |
| --- | --- |
| PowerShell scripts | Platform-specific tooling choice; Windows-first project. Documented requirement, not a format issue. |
| `agents/openai.yaml` | Parallel metadata layer for OpenAI Agent compatibility. Does not conflict with SKILL.md frontmatter. |
| Codex config format (TOML) | Codex's native config; agent-ecosystem does not need to adopt TOML. |

## Needs-Follow-Up Items

| Item | Why | Resolution Path |
| --- | --- | --- |
| Codex skills subsystem | Source code exists but official docs inaccessible | Wait for public docs; verify SKILL.md compatibility |
| `allowed-tools` (agentskills.io) | Marked "experimental" in standard | Monitor adoption across clients |
| `when_to_use` (Claude Code) | Optional but potentially useful for trigger precision | Evaluate if description field is insufficient |
| `context: fork` (Claude Code) | Subagent isolation; agent-ecosystem has its own delegation model | Compare delegation patterns |
| `disable-model-invocation` | Controls auto-detection; agent-ecosystem relies on description matching | Evaluate for sensitive skills |
| Claude Code `paths` scoping | Glob-based auto-activation; not currently needed | Evaluate when monorepo use cases emerge |
| Codex `AGENTS.override.md` | Per-directory override; unique to Codex | No equivalent needed unless Codex becomes primary target |
| Dynamic injection (`!`command) | Claude Code feature for shell output injection | Evaluate for context-gate skill |
| `license` field | Standard optional field | Add to frontmatter when license is finalized |
| `compatibility` field | Standard optional field; documents runtime requirements | Add: `Requires PowerShell 7+` |

---

## Suggested PR Sequence

The following PRs are ordered from lowest risk to highest. Each PR
should be independently reviewable and revertable.

### PR 1: Frontmatter metadata map migration

Move `category`, `stability`, `scope` into a `metadata` map to
align with agentskills.io standard. Keep the three original fields
as read-compatibility aliases during a transition period.

Risk: low. Metadata only; no behavior change.
Validation: existing release checks + new frontmatter shape check.

### PR 2: Add `compatibility` and `license` fields

Add `compatibility: Requires PowerShell 7+` to all kernel skills.
Add `license` field when the project license is finalized.

Risk: low. Additive frontmatter only.
Validation: frontmatter field presence check.

### PR 3: Discovery path adapter

Create `.agents/skills/` symlink or thin wrapper that points to
the existing `skills/` directory. This enables cross-client
discovery without changing the canonical location.

Risk: medium. Affects discovery behavior; needs testing across
Claude Code and agentskills.io validator.
Validation: symlink existence + skill load test.

### PR 4: Claude Code integration surface

Document the `CLAUDE.md` → `AGENTS.md` import pattern. Optionally
add `.claude/skills/` wrappers or symlinks for native Claude Code
discovery.

Risk: medium. Affects Claude Code integration.
Validation: Claude Code skill loading test.

### PR 5: Eval format alignment

Migrate from repo-level fixture validation to per-skill
`evals/evals.json` format as defined by agentskills.io. This
builds on the #166 eval iteration work.

Risk: medium. Changes eval structure; needs fixture migration.
Validation: existing eval iteration checks adapted to new format.

### PR 6: Codex compatibility surface (pending docs)

Create Codex-compatible `AGENTS.md` wrappers or config entries
once official Codex skill documentation is available and the
SKILL.md → Codex mapping is verified.

Risk: high (unverified). Blocked on Codex docs availability.
Validation: Codex CLI skill loading test.

---

## Evidence Sources

| Source | Tier | URL |
| --- | --- | --- |
| Agent Skills standard | Verified | https://agentskills.io |
| Agent Skills GitHub | Verified | https://github.com/agentskills/agentskills |
| Claude Code skills docs | Verified | https://docs.anthropic.com/en/docs/claude-code/skills |
| Claude Code memory docs | Verified | https://docs.anthropic.com/en/docs/claude-code/memory |
| Codex source code | Verified (Tier 1) | https://github.com/openai/codex (Apache-2.0). Key files: `codex-rs/core/src/agents_md.rs` (AGENTS.md loading), `codex-rs/core/src/config_toml.rs` (TOML config), `codex-rs/core/src/hook_config.rs` (hook system). |
| Codex official docs | Inaccessible (Tier 2) | https://developers.openai.com/codex (404/auth) |
| Codex blog summaries | Unverified (Tier 3) | Various community sources |

**Tier definitions**:
- Tier 1: Official source code or primary documentation, directly read.
- Tier 2: Official site confirmed to exist but content inaccessible.
- Tier 3: Secondary sources (blogs, community posts, search results).
  Not used for confirmation claims.
