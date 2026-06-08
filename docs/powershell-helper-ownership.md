# PowerShell Helper Ownership

This note defines the first-stage ownership model for issue #97. It documents
where shared PowerShell path helpers may live today, where local helper copies
are intentional, and what future consolidation must preserve.

This is a governance and validation guard stage. It does not remove runtime
helper copies, does not introduce a skill-local or hub-local helper package,
and does not complete #97.

## Ownership Model

| Layer | Helper ownership | Allowed dependency shape |
| --- | --- | --- |
| Repository maintenance scripts | `scripts/lib/path-guard.ps1` is the authoritative helper for source-checkout maintenance scripts. | Scripts under `scripts/` may dot-source `scripts/lib/path-guard.ps1` when they are intended to run from the repository checkout. |
| Installed skill runtime scripts | Each installed skill script must remain usable from an installed runtime without a source checkout. | A skill runtime script must either keep the local helper it needs or depend only on a helper packaged in the same installed skill. |
| Knowledge hub installed runtime scripts | `knowledge-hub/scripts/` is the preferred runtime entrypoint for routine hub maintenance. | A hub runtime script must either keep the local helper it needs or depend only on a helper packaged in the installed hub. |

## Intentional Duplication

`Join-PathParts` duplication is currently intentional in installed runtime
surfaces because copy-mode installs do not include the repository-level
`scripts/lib/path-guard.ps1` helper.

The current allowed local definitions are:

- `scripts/lib/path-guard.ps1`: authoritative repository helper.
- `skills/project-context-gate/scripts/context_gate.ps1`: standalone context
  gate runtime entrypoint.
- `skills/project-bootstrap/scripts/bootstrap_project.ps1`: standalone
  bootstrap runtime entrypoint.
- `skills/project-bootstrap/scripts/init_hub.ps1`: bootstraps the installed hub
  template and runtime script surface.
- `skills/project-bootstrap/scripts/audit_memory_language.ps1`: standalone
  project-memory language audit helper.
- `skills/project-bootstrap/scripts/check_hub_lock.ps1`: standalone hub lock
  drift helper.
- `skills/project-bootstrap/scripts/language_migration.ps1`: standalone
  project-memory language migration helper.
- `skills/project-bootstrap/scripts/set_project_language.ps1`: standalone
  first-session language scaffold helper.
- `skills/project-bootstrap/scripts/promote_experience.ps1`: compatibility copy
  for bootstrap-time hub setup.
- `skills/project-bootstrap/scripts/rebuild_experience_index.ps1`: compatibility
  copy for bootstrap-time hub setup.
- `knowledge-hub/scripts/promote_experience.ps1`: preferred installed hub
  experience promotion entrypoint.
- `knowledge-hub/scripts/rebuild_experience_index.ps1`: preferred installed hub
  index rebuild entrypoint.
- `knowledge-hub/scripts/search_experience.ps1`: preferred installed hub search
  entrypoint.

`scripts/validate-release.ps1` must continue to use
`scripts/lib/path-guard.ps1`; it must not reintroduce a local
`Join-PathParts` definition.

## Compatibility Copies

The `project-bootstrap` copies of `promote_experience.ps1` and
`rebuild_experience_index.ps1` are compatibility copies. They are kept so
`init_hub.ps1` can initialize or refresh the installed `knowledge-hub/scripts`
surface without depending on a maintainer source checkout.

The preferred long-term runtime entrypoints remain:

- `knowledge-hub/scripts/promote_experience.ps1`
- `knowledge-hub/scripts/rebuild_experience_index.ps1`
- `knowledge-hub/scripts/search_experience.ps1`

Release validation should continue checking that the compatibility copies stay
identical to their preferred `knowledge-hub/scripts/` counterparts where an
identical copy is the chosen compatibility model.

## Future Consolidation Rules

Future code consolidation is allowed only after the packaging contract is clear.
Any follow-up PR that removes a local helper definition must show that the
replacement helper is available in both copy-mode and link-mode installs.

Do not make installed runtime scripts depend on repository-only paths such as
`scripts/lib/path-guard.ps1`.

Do not remove the project-bootstrap compatibility copies of
`promote_experience.ps1` or `rebuild_experience_index.ps1` without a documented
compatibility or deprecation plan.

Do not combine this helper ownership work with #96 release-validator or
language-migration modularization.

## Validation

The release validator owns a lightweight allowlist guard for current
`Join-PathParts` definitions. A new local definition should fail validation
until the maintainer intentionally classifies its runtime ownership.

Recommended checks for #97 helper-ownership PRs:

```powershell
rg -n "^function Join-PathParts" scripts skills knowledge-hub -g "*.ps1"
git diff --check
pwsh -NoProfile -File scripts/validate-release.ps1 -ScratchRoot <scratch-root>
```
