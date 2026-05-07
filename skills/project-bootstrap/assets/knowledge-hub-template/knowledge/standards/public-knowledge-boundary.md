# Public Knowledge Boundary

Maturity: verified
Scope: cross-project
Source: manual
Last reviewed: 2026-05-08

## Rule

Reusable knowledge must be generic, portable, and safe to use without local
machine context. Personal overlays, project-only facts, local paths, and
private migration details belong outside the shared hub.

## Applies To

- Shared knowledge hub entries.
- Shared templates and project scaffolds.
- Docs that explain reusable workflows.
- Validation checks that protect reusable artifacts.

## Does Not Apply To

- Project-local `.agents/context/` notes.
- Private overlay content.
- Temporary validation scratch files.
- Local session notes that are not intended for shared use.

## Checklist

- The entry teaches a reusable workflow, pattern, or standard.
- The entry can be understood without a specific local machine layout.
- The entry avoids private repository mappings and project-only history.
- The entry belongs in `experience/`, `patterns/`, or `standards/` according to
  the catalog.
- The catalog is updated when the entry is added, moved, or deprecated.
