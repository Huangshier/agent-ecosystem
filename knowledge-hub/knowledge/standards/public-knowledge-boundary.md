# Public Knowledge Boundary

Maturity: verified
Scope: cross-project
Source: manual
Last reviewed: 2026-05-08

## Rule

Public knowledge must be generic, reusable, and safe to share without local
machine context. Personal overlays, project-only facts, local paths, and
private migration details belong outside the public hub.

## Applies To

- Public knowledge hub entries.
- Public templates and project scaffolds.
- Public docs that explain reusable workflows.
- Release validation checks that protect public artifacts.

## Does Not Apply To

- Project-local `.agents/context/` notes.
- Private overlay content.
- Temporary validation scratch files.
- Local session notes that are not intended for release.

## Checklist

- The entry teaches a reusable workflow, pattern, or standard.
- The entry can be understood without a specific local machine layout.
- The entry avoids private repository mappings and project-only history.
- The entry belongs in `experience/`, `patterns/`, or `standards/` according to
  the catalog.
- The catalog is updated when the entry is added, moved, or deprecated.
