---
name: project-workspace
description: Discover public-safe project Work, Context, Procedure, and Spec metadata through one deterministic read-oriented entrypoint.
compatibility: Requires PowerShell 7.6 or newer and a local project root.
---

# Project workspace

Use the scripts under `scripts/` as the single public entrypoint for Slice B:

```powershell
pwsh -NoProfile -NonInteractive -File skills/project-workspace/scripts/discover-project-assets.ps1 -ProjectRoot <project-root> -Query <query> -Json
pwsh -NoProfile -NonInteractive -File skills/project-workspace/scripts/check-project-workspace.ps1 -ProjectRoot <project-root> -Json
```

`discover` reads canonical Markdown metadata through the Slice A parser and may
maintain only the disposable `.agents/.cache/catalog.json` cache. `check` is
strictly read-only and never creates or refreshes that cache. Canonical Markdown
remains the content authority; `glossary.yaml` is used only when it is present,
evidence-backed, and valid.

## Deterministic discovery contract

- The default result limit is exactly `5`; callers may request `1..100`.
- Base scores are `direct_match=100`, `alias_match=90`,
  `symbol_match=80`, `relation_match=40`, and `default=1`. A matching Git
  branch adds `20`; a mismatching branch subtracts `10`, with a floor of zero.
- When one Glossary term matches in more than one way, precedence is
  `direct_match > alias_match > symbol_match > relation_match`. Public
  `reason_codes` always use this order:
  `direct_match`, `alias_match`, `symbol_match`, `relation_match`,
  `branch_match`, `branch_mismatch`, `default`.
- Results sort by `score` descending, status rank descending, `updated`
  descending, then `path`, `type`, and `id` ascending. Status ranks are
  `active=4`, `draft|accepted=3`, `paused|blocked=2`, `deferred=1`, and all
  others `0`. Every string comparison in the sort key is ordinal.
- Candidate assets are deduplicated by the ordinal `(type,id)` tuple.
  Repeated Glossary expansion is deduplicated by normalized canonical term and
  retains the highest-precedence reason.
- Without an explicit status filter, `archived`, `implemented`, and
  `superseded` assets are excluded.

The external surface remains one `project-workspace` Skill with the existing
`discover` and `check` commands. Internally, the implementation separates
Catalog/cache, Glossary/query, Git-anchor, and revision/reference-check
responsibilities; those internal scripts are not additional commands or Skills.

The Slice B surface is dormant. It does not create assets, update Work items,
integrate with bootstrap or runtime defaults, or expose Procedure files as
native Skills.
