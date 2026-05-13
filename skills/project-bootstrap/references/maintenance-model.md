# Maintenance Model

## Goals
- Keep cross-project defaults in a single global repository.
- Keep project behavior reproducible with pinned lock metadata.
- Allow project-local overrides without breaking shared updates.

## Repository Layout
- Global hub: `%USERPROFILE%\.agents\knowledge-hub`
- Shared templates: `templates/project-root/`, `templates/project-agent/`,
  and `templates/project-memory/<language>/`
- Project lock: `<project>/.agents/hub.lock.json`

## Update Rules
1. Treat `knowledge-hub/templates/project-memory/<language>/` as the
   authoritative source for project-memory language templates.
2. Keep `assets/knowledge-hub-template/templates/project-memory/<language>/`
   synchronized as the bundled runtime snapshot used by the bootstrap skill.
3. Treat the remaining `assets/knowledge-hub-template/` shared templates as the
   bundled source for ordinary hub bootstrap assets.
4. Sync those changes into the global hub with `scripts/init_hub.ps1 -Overwrite`.
5. Commit changes in the hub repository after reviewing the synced diff.
6. Re-run project bootstrap for target projects.
7. Use default non-overwrite mode for safe upgrades.
8. Use overwrite mode only when intentionally replacing local template files.
9. Treat `<hub>/knowledge/experience/index.json` as generated hub state, not the canonical template source. Rebuild it from the installed hub contents after syncs or manual repair.
10. Keep long-lived project artifacts such as `docs/specs/_templates/` under `templates/project-root/`; bootstrap must install the full project-root tree, not only `AGENTS.md`.

## Lock Validation Workflow
1. Run `scripts/check_hub_lock.ps1 -ProjectDir <project_path>` before assuming a project's pinned hub matches the installed hub.
2. New locks record both hub git metadata and `template_tree_hash_sha256`; dirty hub state is treated as non-reproducible until the hub changes are committed or discarded.
3. If drift is reported, decide whether to refresh the project with `bootstrap_project.ps1` or keep the older pin intentionally.
4. Treat `hub.lock.json` as an auditable pin, not just an installation receipt.

## Precedence
1. Project local edits
2. Installed template defaults
3. Future hub updates

## Docs vs Session Memory
- Put durable project work packages under project-root paths such as `docs/specs/`.
- Keep `.agents/` for session-local memory, routing, and status.
- Do not treat `.agents/plan.md` as a second copy of `docs/specs/<slug>/tasks.md`.

## Suggested Routine
- Weekly: review shared template improvements.
- Per project: refresh lock after template sync.
- Per incident: promote proven fixes into hub templates, not only local notes.
- Per toolchain/host incident: decide whether the lesson should become a global experience entry with a stable prevention rule.

## Experience Promotion Workflow
1. Capture incident/fix in `<project>/.agents/context/experience/*.md`.
2. Mark reviewed cross-project candidates with `Global candidate: Yes` or `Scope: Cross-project reusable`.
3. Promote using `<hub>/scripts/promote_experience.ps1`.
4. Review added files under `<hub>/knowledge/experience/`.
5. If entries were added manually or the registry was reset, repair the registry with `<hub>/scripts/rebuild_experience_index.ps1`.
6. Optionally commit with `-Commit`.
7. Periodically refactor high-frequency entries into reusable templates.

## Experience Retrieval Workflow
1. Keep project sessions focused on project-local memory by default.
2. When an issue looks related to toolchains, host environment, shell behavior, build systems, caches, ports, permissions, or path handling, search `<hub>/knowledge/experience/index.json`.
3. Open only matching entries instead of preloading the full global experience directory.
4. If the issue is repository-specific, keep the lesson local unless it later proves reusable across projects.

## Deduplication Policy
- Primary dedup key: file content SHA256.
- Registry file: `<hub>/knowledge/experience/index.json`.
- If file name collides but content differs, append hash suffix to file name.
- `init_hub.ps1` should leave the installed hub with a rebuilt registry even after `-Overwrite`; do not rely on the template copy of `index.json` as authoritative runtime data.
