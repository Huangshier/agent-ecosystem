# Template Path Reference Audit

This audit keeps the post-`v0.4.2` template model clear for maintainers and
agents. Current public guidance should point to the language-scoped template
layout:

```text
knowledge-hub/templates/languages/<language>/project-root/
knowledge-hub/templates/languages/<language>/project-agent/
skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/<language>/project-root/
skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/<language>/project-agent/
```

## Legacy Paths

The following paths are legacy or deprecated template entrypoints. They should
not appear as active setup, install, bootstrap, migration, or upgrade guidance:

```text
knowledge-hub/templates/project-root/
knowledge-hub/templates/project-agent/
knowledge-hub/templates/project-memory/
skills/project-bootstrap/assets/knowledge-hub-template/templates/project-root/
skills/project-bootstrap/assets/knowledge-hub-template/templates/project-agent/
skills/project-bootstrap/assets/knowledge-hub-template/templates/project-memory/
skills/project-bootstrap/templates/project-memory/
```

## Allowed Active References

Active script references are allowed only when they prevent or remediate legacy
paths:

- `scripts/validate-release.ps1` names the legacy paths as forbidden
  directories and fails release validation if active legacy directories return.
- `skills/project-bootstrap/scripts/init_hub.ps1` names the old hub template
  directories only to remove them from generated or refreshed hub snapshots.

These references are not public setup guidance and should not be copied into
new docs as supported template entrypoints.

## Allowed Historical Mentions

Historical release records and closed work packages may mention legacy paths
when the surrounding text makes the historical status clear. Examples include:

- `CHANGELOG.md` entries for `v0.4.1` and `v0.4.2`.
- `docs/releases/v0.4.1.md` and `docs/releases/v0.4.2.md`.
- Closed specs under `docs/specs/**` that describe the old implementation
  state or the migration away from it.
- `docs/release-readiness.md` when it describes published historical release
  state.

Historical mentions should be labeled as legacy, deprecated, removed,
superseded, or historical state. They must not instruct readers to create or
depend on the old paths.

## Validation

The release validator enforces three boundaries:

- Required language-scoped template directories must exist.
- Legacy template directories must not exist.
- Legacy path text matches must be limited to validator/remediation references
  or marked historical records.
