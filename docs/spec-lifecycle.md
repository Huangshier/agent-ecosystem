# Target-Project Spec Lifecycle

This document describes optional `docs/specs/**` lifecycle hygiene for target
projects that choose to use `project-workspace create-spec`.

It no longer governs this public repository's own maintenance records. Public
`agent-ecosystem` maintenance uses GitHub issues and pull request bodies as the
canonical record, with release docs, changelog entries, governance docs, and
curated knowledge entries for durable public-facing facts.

## When To Use Local Specs

Use project-local `docs/specs/<slug>/` work packages when a target-project task
needs durable scope, non-goals, risks, acceptance evidence, or multi-phase
handoff across sessions.

Skip local specs for small, obvious, one-step work where the issue, PR body, or
ordinary project documentation already captures enough context.

## Status Values

If a target project keeps spec status metadata, use these values:

| Status | Meaning |
| --- | --- |
| `Draft` | Work package defined but not approved or started. |
| `Active` | Work is in progress. |
| `Done` | Work is complete and has review, validation, merge, issue, or release evidence. |
| `Archived` | Work is complete and kept only for historical evidence. |
| `Superseded` | Replaced by a newer spec or approach. |
| `Deferred` | Accepted but intentionally postponed. |

Use `Done`, not `Completed`, for finished work.

## Completion Hygiene

When a target-project spec reaches completion:

- Record the evidence that proves the work is complete, such as a merged PR,
  closed issue, release version, test output, or reviewer confirmation.
- Keep the scope, non-goals, and acceptance evidence intact.
- Remove branch-local waiting state, pending hosted-check notes, and stale
  "next action" dashboards from long-lived specs.
- Do not rewrite historical evidence only to make old phrasing look current.

## Archival

Completed specs can stay in place by default. Archive only when the target
project's maintainer wants old work removed from current planning.

When archiving:

1. Change `- **Status**: Done` to `- **Status**: Archived`.
2. Add a short archive note explaining why the record is no longer active.
3. Link to any successor issue, PR, release, or spec.
4. Avoid rewriting the full body or task history.

## Public Repository Boundary

In this public source repository:

- do not create root `docs/specs/**` work packages for new maintenance;
- do not treat removed historical specs as deleted history, because Git
  history, issues, PRs, changelog entries, and release notes remain available;
- keep target-project examples and templates clearly marked as optional local
  artifacts.

## Validation

Docs-only lifecycle guidance should pass:

```powershell
git diff --check
```

Changes that also touch release-facing files, scripts, templates, or validation
logic should additionally pass:

```powershell
pwsh -NoProfile -File scripts/validate-release.ps1 -ScratchRoot <scratch>
```
