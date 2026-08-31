# Project Bootstrap

`project-bootstrap` initializes and conservatively refreshes a project-owned
C3.3 workspace. The executable workflow and compatibility boundaries are in
[`SKILL.md`](SKILL.md).

## Active C3.3 Default

Run the installed Skill against an existing target directory:

```powershell
pwsh -NoProfile -NonInteractive -File <runtime>\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -ProjectLanguage en
```

Use `-ProjectLanguage zh-CN` for the Simplified Chinese C3.3 templates. The
script does not infer chat language; omitted language defaults to `en` for a
fresh project.

Fresh bootstrap creates only the current C3.3 surface:

```text
<project>/
  AGENTS.md
  .agents/
    README.md
    .gitignore
    hub.lock.json
    work/
    context/
    procedures/
    skills/
  docs/
    specs/
```

`assets/c3-3-project-template/<language>/` is the fresh template source.
`ProjectLanguage` selects the localized root `AGENTS.md` and
`.agents/README.md`; the normalized value is persisted as
`.agents/hub.lock.json.project_language`. The lock also records
`workspace_model = "c3.3"`, `workspace_state = "active"`, and `hub_dir = ""`.
An empty `hub_dir` is the expected active state, not hub drift.

Bootstrap creates no placeholder Work, Context, Procedure, Spec, glossary, or
project-local Skill. It also does not create a nested project guide, hot-memory
files, a command index, `CLAUDE.md`, or legacy `.claude/**` content.

Verify the result with the other active Runtime Skill:

```powershell
pwsh -NoProfile -NonInteractive -File <runtime>\skills\project-workspace\scripts\check-project-workspace.ps1 -ProjectRoot <project> -Json
```

## Active Files

- `SKILL.md`: public workflow, safety boundary, and full command reference.
- `scripts/bootstrap_project.ps1`: fresh C3.3 initialization and conservative
  existing-project refresh wrapper.
- `scripts/project_language.ps1`: shared language normalization and legacy
  declaration reader used by the wrapper.
- `assets/c3-3-project-template/en/` and `zh-CN/`: fresh C3.3 templates.
- [`docs/project-bootstrap-command-boundaries.md`](../../docs/project-bootstrap-command-boundaries.md):
  helper ownership and orchestration boundary.

Default refresh preserves project-owned edits. `-RefreshUnmodifiedTemplates`
updates only files that still match prior installed template hashes.
`-OverwriteTemplates` remains a warning-emitting compatibility alias for that
same conservative behavior; it is not a force overwrite.

## Legacy / Compatibility-Only Surface

The following tools and assets remain for existing legacy projects or explicit
maintenance of a separately tracked knowledge hub. They are not fresh/default
C3.3 adoption entrypoints:

- `scripts/init_hub.ps1` and `scripts/check_hub_lock.ps1`: initialize or check
  a separately tracked hub and legacy non-empty hub pins.
- `scripts/set_project_language.ps1`: legacy first-session scaffold writer.
- `scripts/memory_upgrade.ps1`: legacy hot-memory layout analysis and upgrade.
- `scripts/language_migration.ps1` and
  `scripts/audit_memory_language.ps1`: legacy `en` / `zh-CN` migration and
  review-only body-language audit.
- `assets/knowledge-hub-template/templates/languages/<language>/project-root|project-agent/`:
  bundled legacy scaffold/migration templates.
- compatibility copies of knowledge-hub promotion and index helpers under
  `scripts/`; routine hub maintenance uses the installed
  `knowledge-hub/scripts/` entrypoints.

The legacy templates include nested project guides, hot memory, commands,
`CLAUDE.md`, `.claude/**`, context starters, and older Spec templates. Their
presence in compatibility assets does not make them current Runtime authority.
Do not run the language-migration or first-session scaffold helpers on a fresh
C3.3 project; they operate on the legacy surface.

For an existing legacy project, omitted `-ProjectLanguage` first reads
`.agents/hub.lock.json.project_language` and uses a nested guide declaration
only as a compatibility fallback when the lock has no language. Conflicting
declarations fail before writes. Legacy Simplified Chinese template gaps may
fall back to English and are reported as validation findings.

Legacy migration remains explicit, proposal-first, and backup-first. Use the
Runtime-level `scripts/migrate-project.ps1` Analyze -> explicit Apply -> guarded
Rollback flow for C3.3 workspace migration. The bootstrap memory/language
switches are compatibility wrappers, not a second migration authority.

## Intent And Safety

- **Refresh or template upgrade:** preserve project-specific content; add
  missing surfaces or refresh only verified unmodified templates.
- **Legacy language/memory migration:** use explicit Analyze, Plan, Apply, and
  Validate steps with reviewable proposals and backups.
- **Reset:** use `-ForceResetScaffold` only when the caller explicitly permits
  discarding scaffold customizations. It warns and backs up before replacement.

Commands, paths, APIs, filenames, raw errors, and code symbols remain protected
literals during language migration. Audit JSON includes the resolved project
path; remove local paths before copying evidence into public artifacts.

## Focused Validation

```powershell
pwsh -NoProfile -NonInteractive -File <repo>\scripts\validation\project-bootstrap-safety-fixture.ps1 -Json
```

Repository-wide Release validation is not part of the ordinary bootstrap or
documentation workflow; use the classifier-selected local validation plan.
