# Skills Discovery

Project memory language: English.

## Purpose

Inventory skills that are available to the current project or runtime without
changing runtime configuration, installing tools, enabling skills, or validating
client compatibility.

## When To Use

- The user asks what skills are available or how to discover skills.
- A project command, handoff, or review needs a public-safe list of installed
  skill names and descriptions.
- You need to distinguish Workflow Kernel skills from project-local, personal,
  admin, system, or plugin-provided skills before deciding what to use.

## Discovery Locations

Inspect only locations that exist in the current environment. Common locations
include:

| Scope | Typical locations |
| --- | --- |
| Project-local | `.agents/skills`, `.github/skills`, `.claude/skills` |
| Runtime or repository | `<runtime>/skills`, `<repo>/skills` |
| User-local | `%USERPROFILE%\.agents\skills`, `$HOME/.agents/skills`, `$HOME/.copilot/skills` |
| System/admin | `/etc/codex/skills` or runtime-managed system skill directories |

For each candidate skill directory, read only `SKILL.md` first. Use progressive
disclosure: do not preload `scripts/`, `references/`, or `assets/` unless the
selected task requires that specific skill.

## What To Report

For each discovered skill, report:

- Skill name, from `SKILL.md` frontmatter when present; otherwise the directory
  name.
- Short description or trigger summary from `description`.
- Location scope, such as project-local, runtime, user-local, system, or plugin.
- Kernel classification when the frontmatter or metadata says
  `category: kernel`.
- Any conservative compatibility note already present in frontmatter.

## Boundaries

- This command card is read-only. Do not install, remove, enable, disable,
  symlink, copy, or validate skills unless another explicit task authorizes it.
- Do not claim a skill is compatible with Codex, Copilot, Claude Code, or other
  clients only because its metadata resembles an external standard.
- Do not treat `agents/openai.yaml` as evidence that a skill is compatible with
  Codex Agent Skills. It is a parallel metadata layer.
- Do not add `allowed-tools`, `invocation`, adapter wrappers, marketplace
  entries, registry publishing, or release-blocking external validator checks
  from this discovery command.

## Expected Evidence

- List of inspected locations and whether each existed.
- List of discovered `SKILL.md` files.
- Summarized frontmatter fields: `name`, `description`, `metadata`,
  `compatibility`, and any project-specific fields.
- Explicit note for locations that were not present in the current environment.

