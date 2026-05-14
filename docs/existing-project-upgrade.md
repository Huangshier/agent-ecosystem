# Existing Project Upgrade Path

This guide is for projects that already have `.agents` memory and want to move
toward the post-`v0.4.2` public template model without losing local project
context.

New empty projects should use the
[minimal project adoption walkthrough](walkthroughs/minimal-project-adoption.md)
instead. This guide assumes the project already has local memory, specs, and
possibly generated context entries.

## Current Template Model

`v0.4.2` uses language-scoped project-memory templates:

```text
knowledge-hub/templates/languages/<language>/project-root|project-agent/
skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/<language>/project-root|project-agent/
```

The supported public project-memory template languages are `en` and `zh-CN`.
English remains the public default and fallback language. The `full` and `dev`
profiles still install the same public content as `recommended`; they do not
install additional public domain packs yet.

Do not recreate legacy template directories as compatibility mirrors. Old path
references should be treated as historical records or cleanup findings, not as
supported current entrypoints.

## Preserve Local Memory

Existing project memory is project-owned. The public templates are structural
baselines for missing files, exact template replacement, and reviewable
migration proposals. They do not authorize overwriting project-specific memory.

Preserve local content such as:

- `.agents/process.txt`, `.agents/plan.md`, and `.agents/notes.md` when they
  contain active project state or stable facts.
- `.agents/context/experience/` entries created by runtime work.
- `.agents/context/patterns/` and `.agents/context/standards/` when a project
  has added those local routing folders.
- `docs/specs/**` work packages that define local goals, decisions, or
  acceptance evidence.
- Any project-specific commands, context indexes, or notes that do not exactly
  match the public scaffold.

## Upgrade Flow

Use a conservative analyze -> plan -> backup -> apply -> validate flow.

1. Analyze existing memory without editing files by calling the memory-upgrade
   helper directly.

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File <runtime>\skills\project-bootstrap\scripts\memory_upgrade.ps1 -ProjectDir <project> -Mode Analyze
   ```

   The bootstrap wrapper also exposes `-AnalyzeMemoryUpgrade`, but it runs the
   normal conservative bootstrap path before memory analysis. It may create
   missing scaffold files and `.agents/hub.lock.json` before reporting memory
   findings. Use the wrapper when a project also needs the current scaffold
   baseline refreshed; use the direct helper when the analysis must be
   memory-only and no-edit.

2. Plan a reviewable upgrade proposal.

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File <runtime>\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -PlanMemoryUpgrade
   ```

3. Review the generated plan. Confirm that project-specific memory is preserved
   and that old template path references are treated as historical notes or
   cleanup findings.

4. Back up before apply. The memory upgrade and language migration apply flows
   are backup-first; do not bypass that safety record.

5. Apply only the reviewed proposal.

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File <runtime>\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -ApplyMemoryUpgrade -UpgradePlan <proposal>
   ```

6. Validate the result with the relevant project checks.

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File <runtime>\skills\project-context-gate\scripts\context_gate.ps1 -ProjectRoot <project>
   powershell -NoProfile -ExecutionPolicy Bypass -File <runtime>\skills\memory-governance\scripts\memory_diagnose.ps1 -ProjectRoot <project>
   ```

For project-memory language changes, use the conservative language migration
Analyze, Plan, Apply, and Validate modes with explicit source and target
languages. Review any manual-review artifacts before applying the narrative
phase.

## Handling Old Path References

Classify old path references before editing:

- Active setup, install, bootstrap, migration, or upgrade guidance should move
  to the `templates/languages/<language>/project-root|project-agent/` model.
- Historical release notes, closed specs, and old experience entries can keep
  old paths only when they are clearly marked as legacy, deprecated, removed,
  superseded, or historical state.
- Generated or local project records should not be deleted only because they
  mention an old path. Preserve the record and add a short note when the path is
  historical.

Do not add compatibility mirrors for old template directories. If a local tool
still depends on an old path, update the tool or keep the compatibility layer
inside the local project, not in the public kernel.

## Validation For Public Changes

When changing this public repository, run:

```powershell
git diff --check
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-release.ps1 -ScratchRoot <scratch-root>
```

The release validator checks the language-scoped template structure, legacy
template-path audit, upgrade-flow coverage, and public/private boundary rules.
