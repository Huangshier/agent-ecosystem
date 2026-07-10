# Agent Knowledge Hub

Global shared templates for project-level `.agents` scaffolds.

## Purpose
- Provide reusable defaults across projects.
- Keep project-level memory structures consistent.
- Support pinned installation via `.agents/hub.lock.json`.
- Provide a catalog-first reading map at `knowledge-catalog.md`.
- Keep promoted cross-project experience in `knowledge/experience/` with a generated `index.json` for lightweight lookup.
- Provide starter `knowledge/patterns/` and `knowledge/standards/` layers for
  reusable workflows and cross-project rules.

## Template Paths
- `templates/languages/<language>/project-root/` -> project root files
- `templates/languages/<language>/project-agent/` -> files under project
  `.agents/`

Typical project-root contents include:
- `AGENTS.md`
- `docs/specs/_templates/` for lightweight spec-first workflows

## Maintenance Notes
- Language-scoped template changes originate from
  `knowledge-hub/templates/languages/<language>/project-root|project-agent/`;
  this bundled asset tree carries the runtime snapshot used by
  `project-bootstrap`.
- Promote reviewed project experience with `scripts/promote_experience.ps1 -ProjectDir <project>`. By default, only files marked `Global candidate: Yes` or `Scope: Cross-project reusable` are promoted; use `-IncludeAll` only for an explicitly reviewed batch.
- Intake marked local experience into an explicit runtime review inbox with `scripts/manage_candidates.ps1 -Mode Intake -InboxDir <runtime>/state/knowledge-candidates/ -ProjectRoot <project> -Language <language>`. Intake is read-only toward project roots and never promotes formal experience.
- `knowledge/experience/index.json` in the installed hub is generated state. Promotion verifies registry file/hash consistency; rebuild it with `scripts/rebuild_experience_index.ps1` after manual hub edits or registry recovery.
- Search reusable experience with `scripts/search_experience.ps1 -Query <text>`; open only matching entries instead of preloading the whole experience directory.
- Update `knowledge-catalog.md` whenever adding, moving, or deprecating
  reusable knowledge entries.

## Source Of Truth
- Skill repositories own skill behavior and scripts.
- `knowledge-hub/templates/languages/<language>/project-root|project-agent/`
  owns project-memory language templates.
- `project-bootstrap/assets/knowledge-hub-template/` owns the bundled runtime
  snapshot.
- This installed `knowledge-hub` is the local aggregate/runtime layer for templates, scripts, and promoted experience.
- Routine global experience promotion belongs to this installed hub layer, not to project bootstrap sessions.
