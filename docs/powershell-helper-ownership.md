# PowerShell Helper Ownership

This note defines the PowerShell helper ownership model for issue #97. It
documents where shared PowerShell path helpers may live today, where local
helper copies are intentional, and what future consolidation must preserve.

The current deliverable boundary is documentation plus validation guardrails.
It does not remove runtime helper copies and does not introduce a skill-local or
hub-local helper package.

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
- `skills/project-context-gate/scripts/context_gate.ps1`: retired
  compatibility-only context-gate helper retained for fixtures and historical
  contracts; it is not an active Runtime entrypoint.
- `skills/project-bootstrap/scripts/bootstrap_project.ps1`: standalone
  bootstrap runtime entrypoint.
- `skills/project-bootstrap/scripts/init_hub.ps1`: bootstraps the installed hub
  template and runtime script surface.
- `skills/project-bootstrap/scripts/audit_memory_language.ps1`: legacy
  compatibility-only project-memory language audit helper.
- `skills/project-bootstrap/scripts/check_hub_lock.ps1`: standalone hub lock
  drift helper.
- `skills/project-bootstrap/scripts/language_migration.ps1`: legacy
  compatibility-only project-memory language migration helper.
- `skills/project-bootstrap/scripts/set_project_language.ps1`: legacy
  compatibility-only first-session language scaffold helper.
- `skills/project-bootstrap/scripts/promote_experience.ps1`: compatibility copy
  for bootstrap-time hub setup.
- `skills/project-bootstrap/scripts/manage_candidates.ps1`: compatibility copy
  for standalone runtime candidate intake and triage.
- `skills/project-bootstrap/scripts/rebuild_experience_index.ps1`: compatibility
  copy for bootstrap-time hub setup.
- `knowledge-hub/scripts/promote_experience.ps1`: preferred installed hub
  experience promotion entrypoint.
- `knowledge-hub/scripts/manage_candidates.ps1`: preferred installed hub
  candidate intake and triage entrypoint.
- `knowledge-hub/scripts/rebuild_experience_index.ps1`: preferred installed hub
  index rebuild entrypoint.
- `knowledge-hub/scripts/search_experience.ps1`: preferred installed hub search
  entrypoint.

`scripts/validate-release.ps1` must continue to use
`scripts/lib/path-guard.ps1`; it must not reintroduce a local
`Join-PathParts` definition.

## Compatibility Copies

The `project-bootstrap` copies of `manage_candidates.ps1`,
`promote_experience.ps1`, and `rebuild_experience_index.ps1` are compatibility copies. They are kept so
`init_hub.ps1` can initialize or refresh the installed `knowledge-hub/scripts`
surface without depending on a maintainer source checkout.

The preferred long-term runtime entrypoints remain:

- `knowledge-hub/scripts/promote_experience.ps1`
- `knowledge-hub/scripts/manage_candidates.ps1`
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
`manage_candidates.ps1`, `promote_experience.ps1`, or
`rebuild_experience_index.ps1` without a documented
compatibility or deprecation plan.

Do not combine this helper ownership work with #96 release-validator or
language-migration modularization.

## Issue #97 Closeout

The second-stage #97 review found no safe direct deletion of local
`Join-PathParts` definitions inside installed runtime scripts. Each remaining
definition is either:

- the repository-maintenance authority in `scripts/lib/path-guard.ps1`;
- a standalone installed skill runtime entrypoint;
- a knowledge-hub installed runtime entrypoint; or
- a project-bootstrap compatibility copy used to seed the installed hub script
  surface.

Reducing the installed-runtime definitions further would require a new
packaged helper contract, such as a skill-local or hub-local helper module, plus
copy-mode and link-mode install validation. That is a separate packaging
refactor, not an in-scope #97 cleanup.

For the current v0.5.0 stabilization sequence, #97 is considered satisfied
when:

- repository-maintenance scripts use the authoritative
  `scripts/lib/path-guard.ps1` helper;
- installed skill and hub scripts do not depend on repository-only helper paths;
- compatibility copies remain documented and hash-guarded where they are meant
  to be identical; and
- release validation fails on unclassified new `Join-PathParts` definitions.

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
