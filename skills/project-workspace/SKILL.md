---
name: project-workspace
description: Discover and check public-safe project assets, manage canonical Work continuity with revision CAS, and classify interrupted Work from read-only Git evidence.
compatibility: Requires PowerShell 7.6 or newer and a local project root.
---

# Project workspace

Use the dispatcher under `scripts/` as the single public entrypoint:

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

## Work continuity operations

Slice C adds five operations to the same dispatcher. `create-work` is intended
only when the caller can name one of the frozen continuity risks:
`unfinished`, `external-wait`, `blocked`, `cross-boundary`, `user-paused`, or
`parallel-slices`.

```powershell
pwsh -NoProfile -NonInteractive -File skills/project-workspace/scripts/project-workspace.ps1 -Operation create-work -ProjectRoot <project-root> -Id <work-id> -Title <title> -Summary <summary> -Next <next-step> -ContinuityReason unfinished -Json
pwsh -NoProfile -NonInteractive -File skills/project-workspace/scripts/project-workspace.ps1 -Operation checkpoint -ProjectRoot <project-root> -Id <work-id> -BaseRevision <sha256:...> -Summary <snapshot> -Next <next-step> -Verified <fact> -Boundary <boundary> -Blocker <blocker> -Json
pwsh -NoProfile -NonInteractive -File skills/project-workspace/scripts/project-workspace.ps1 -Operation set-status -ProjectRoot <project-root> -Id <work-id> -BaseRevision <sha256:...> -Status paused -Json
pwsh -NoProfile -NonInteractive -File skills/project-workspace/scripts/project-workspace.ps1 -Operation complete -ProjectRoot <project-root> -Id <work-id> -BaseRevision <sha256:...> -ResultPersisted -Json
pwsh -NoProfile -NonInteractive -File skills/project-workspace/scripts/project-workspace.ps1 -Operation recover-work -ProjectRoot <project-root> -Id <work-id> -Json
```

`create-work` may also accept one status value, `GitBranch`, `GitWorktree`,
`GitLastVerifiedCommit`, and `Updated`. `checkpoint` updates only explicitly
provided metadata or the exact `## Verified`, `## Boundaries`, and
`## Blockers` sections; all other Markdown body content is preserved.
`set-status` accepts exactly one of `active`, `paused`, `blocked`, or
`deferred`, plus an optional deterministic `Updated`. If `Updated` is omitted,
write operations use the current UTC RFC3339 timestamp.

Every update or deletion requires the current `BaseRevision`. A stale request
returns top-level `status: revision-conflict`, the expected and current
revisions, repository-relative `current_path`, and deterministic
`changed_fields`; it never retries, merges, or overwrites. Before mutation the
implementation validates the current Work and revision again. The adjacent
final snapshot check is a one-shot optimistic fail-closed guard, not a lock,
lease, or claim of linearizable concurrent writes.

`complete` requires explicit persisted-result confirmation and a current
`BaseRevision`. It does not create `completed`, archive, history, or tombstone
state.

`recover-work` is strictly read-only. When Git evidence is sufficient,
`classification` is exactly one of `exact`, `advanced`, `dirty`, or
`diverged`. Branch or ancestry divergence wins over dirty state. Missing or
unverifiable anchors, unavailable Git, an uncheckable detached branch, missing
objects, or shallow-history uncertainty return `classification: null`,
`degraded: true`, and a stable `reason_code`; no fifth classification is
invented. Real branch, full HEAD, staged, unstaged, untracked, and ancestry
facts take precedence over Work summary text.

The external surface remains one `project-workspace` Skill. Internally, the
implementation separates Catalog/cache, Glossary/query, shared Git facts,
revision checks, and Work continuity responsibilities; those
internal scripts are not additional commands or Skills.

The Slice C surface remains dormant. It does not integrate with bootstrap,
installer, runtime defaults, orchestration, or Agent-native Procedure
discovery. Work mutations never synchronously write the disposable Catalog;
the next `discover` observes canonical create/update/delete state and refreshes
that cache when needed, while `check` remains strictly read-only.
