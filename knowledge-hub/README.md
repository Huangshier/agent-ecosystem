# Knowledge Hub

Public templates and reusable cross-project knowledge live here.

The first public release prioritizes project memory templates, lightweight
spec templates, and generic workflow experience over domain-specific knowledge
imports.

## Contents

- `knowledge-catalog.md`: catalog-first reading map for humans and agents.
- `templates/`: shared project scaffolds installed by `project-bootstrap`.
- `scripts/`: generic knowledge maintenance helpers.
- `knowledge/experience/`: public-safe cross-project workflow lessons.
- `knowledge/patterns/`: reusable engineering workflows.
- `knowledge/standards/`: cross-project rules and boundaries.
- `knowledge/domain-packs/`: optional public-safe domain knowledge bundles.

Domain-pack lifecycle, manifest, promotion, safety, validation, and profile
boundaries are governed by
[`docs/domain-pack-governance.md`](../docs/domain-pack-governance.md).

Private domain skills, private migration notes, and environment-specific
automation are intentionally excluded from this public hub.

## Retrieval

Start from `knowledge-catalog.md`, then open only the entries that match the
current task. Use `knowledge/experience/index.json` and
`scripts/search_experience.ps1` for scriptable experience lookup.

## Candidate Intake

Use `scripts/manage_candidates.ps1` to maintain an explicitly selected local
runtime inbox at `<runtime>/state/knowledge-candidates/`. Candidate intake is
read-only toward explicitly supplied project roots and never writes formal
experience entries. See
[`docs/global-candidate-workflow.md`](../docs/global-candidate-workflow.md) for
the schema, commands, triage lifecycle, and public/private boundary.
