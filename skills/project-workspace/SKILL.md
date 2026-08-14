---
name: project-workspace
description: Discover and check public-safe project assets, manage canonical Work continuity, and explicitly manage derived Claude Code project Skill adapters.
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

## Canonical authoring

Use the same dispatcher for explicit canonical asset creation. These operations
write only the requested repository-relative asset and never write Catalog:

```powershell
pwsh -NoProfile -NonInteractive -File skills/project-workspace/scripts/project-workspace.ps1 -Operation create-context -ProjectRoot <project-root> -Id <context-id> -Title <title> -Summary <summary> -Keywords <keyword> -Evidence <evidence> -Json
pwsh -NoProfile -NonInteractive -File skills/project-workspace/scripts/project-workspace.ps1 -Operation create-procedure -ProjectRoot <project-root> -Id <procedure-id> -Title <title> -Kind command -Summary <summary> -Triggers <trigger> -SideEffects <side-effect> -Preconditions <precondition> -Steps <step> -Validation <validation> -StopBoundaries <stop-boundary> -Authorization <authorization> -Json
pwsh -NoProfile -NonInteractive -File skills/project-workspace/scripts/project-workspace.ps1 -Operation create-spec -ProjectRoot <project-root> -Id <spec-id> -Title <title> -Summary <summary> -Goals <goal> -NonGoals <non-goal> -Tradeoffs <tradeoff> -Acceptance <criterion> -RelatedWork <work-id> -Supersedes <spec-id> -Json
```

`create-context` records only stable, public-safe facts. `create-procedure`
accepts only `command` or `workflow`, keeps the Preconditions, Steps,
Validation, Stop Boundaries, and Authorization sections as documentation, and
never executes them. `create-spec` records a caller-confirmed stable design;
none of these operations classifies task complexity or creates short-lived
branch, check, log, or next-step state. Empty list parameters may be supplied
when the canonical schema permits an empty relation list.

## Procedure promotion

Promotion is an explicit two-step boundary:

```powershell
pwsh -NoProfile -NonInteractive -File skills/project-workspace/scripts/project-workspace.ps1 -Operation promote-skill -ProjectRoot <project-root> -Id <procedure-id> -Analyze -Json
pwsh -NoProfile -NonInteractive -File skills/project-workspace/scripts/project-workspace.ps1 -Operation promote-skill -ProjectRoot <project-root> -Id <procedure-id> -Apply -AnalyzeEvidence <evidence-hash> -ConfirmPromotion -Json
```

Analyze is read-only and returns a candidate `.agents/skills/<name>/SKILL.md`,
the original Procedure deletion plan, and the discovery/authorization/side-effect
boundary change, plus deterministic evidence bound to the current Procedure and
candidate hashes. Apply requires that evidence and explicit human confirmation;
missing or stale evidence fails closed without writes. Only Apply writes the
Skill and deletes the original Procedure. After Apply there is one published
Skill representation, not a Procedure plus Skill pair; the next `discover`
refreshes the disposable Catalog. Skill discovery never grants execution
authorization, and Apply performs only the minimal failure recovery needed to
avoid losing the original Procedure or leaving dual authority.

The four canonical project asset roots remain Work, Context, Procedure, and
Spec. A promoted `SKILL.md` follows the standard Agent Skills frontmatter
(`name` and `description`, with only standard optional fields when needed) and
is a Procedure publication form. It is read by an internal discover projection
reader, not by the canonical parser, and it is not a fifth canonical project
asset authority.

## Legacy project migration

Legacy migration uses the Runtime-level `scripts/migrate-project.ps1` entrypoint
and is never triggered by bootstrap, install, update, status, discover, or
uninstall:

```powershell
pwsh -NoProfile -NonInteractive -File scripts/migrate-project.ps1 -Mode Analyze -ProjectRoot <project-root> -Json
pwsh -NoProfile -NonInteractive -File scripts/migrate-project.ps1 -Mode Apply -ProjectRoot <project-root> -AnalyzeEvidence <analyze-json> -ConfirmMigration -Json
pwsh -NoProfile -NonInteractive -File scripts/migrate-project.ps1 -Mode Rollback -ProjectRoot <project-root> -BackupId <backup-id> -ConfirmRollback -Json
```

Analyze is deterministic and strictly read-only. Its caller-held JSON evidence
binds the declared Work / Context / Procedure / Spec plan to every
migration-relevant source, target, project-language, workspace-model, and
project-local state. Apply rejects missing, unconfirmed, ambiguous, unsupported,
or stale evidence before writing. It creates and verifies a complete
project-owned backup under `.agents/.migration-backups/` before changing any
migration target, then records the exact expected post-Apply state.

Rollback keeps the backup and restores only an unchanged migrated project. It
first verifies backup integrity, Apply identity, and the complete expected
post-Apply state; any later Work, Context, Procedure, Spec, project-local Skill,
language, workspace metadata, or other migration-relevant edit makes rollback
fail closed. Rollback never changes the Runtime installation, merges content,
or restores packaged Runtime files as project authority. Unsupported or
ambiguous legacy material remains a human-disposition finding and is not
promoted into a fifth asset type.

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
revision checks, Work continuity, and authoring responsibilities; those
internal scripts are not additional commands or Skills. `project-workspace` and
`project-bootstrap` are the active C3.3 Runtime Skill authority after the
one-time default cutover.

The workspace dispatcher does not trigger migration and does not provide
orchestration, releases, automatic Skill calls, Skill chains, or schedulers.
Migration remains an explicit Runtime-level Analyze / Apply / Rollback
entrypoint. Work and authoring mutations never synchronously write the disposable Catalog;
the next `discover` observes canonical create/update/delete state and refreshes
that cache when needed, while `check` remains strictly read-only.

## Claude Code project adapter

Codex discovers the canonical `.agents/skills` tree natively and does not need
an adapter. ZCode imports Skills through its client-managed UI and does not have
a Runtime-managed filesystem target. The only supported Runtime adapter target
is therefore `claude-code`, with the exact mapping
`.agents/skills/<name>` to `.claude/skills/<name>`.

Bootstrap does not create this adapter. Every lifecycle change is explicit and
uses the same dispatcher style:

```powershell
pwsh -NoProfile -NonInteractive -File skills/project-workspace/scripts/project-workspace.ps1 -Operation create-adapter -ProjectRoot <project-root> -Target claude-code -Json
pwsh -NoProfile -NonInteractive -File skills/project-workspace/scripts/project-workspace.ps1 -Operation rebuild-adapter -ProjectRoot <project-root> -Target claude-code -Json
pwsh -NoProfile -NonInteractive -File skills/project-workspace/scripts/project-workspace.ps1 -Operation status-adapter -ProjectRoot <project-root> -Target claude-code -Json
pwsh -NoProfile -NonInteractive -File skills/project-workspace/scripts/project-workspace.ps1 -Operation remove-adapter -ProjectRoot <project-root> -Target claude-code -Json
```

The representation is a `managed-copy`. Each derived Skill directory contains
`.agent-ecosystem-adapter.json` with `lifecycle=derived` and a deterministic
payload SHA-256. The digest covers normalized relative paths, entry types, raw
file bytes, and the normalized executable flag; it never uses timestamps or
absolute paths. Copies retain file bytes, newline/encoding, directory layout,
and the normalized executable flag on POSIX-like hosts.

`status-adapter` is read-only and reports `absent`, `current`, `stale`,
`modified/conflict`, or `unknown/invalid-ownership`. Mutations preflight the
complete target-wide candidate set before writing, build and validate staged
outputs, replace only unchanged marker-owned outputs, and roll back a failed
replacement. Unowned, modified, invalid, linked, junction-backed, or reparse
point content is never overwritten, merged, or deleted. Rebuild retains owned
source-deleted orphans as `stale`; only explicit `remove-adapter` removes an
unchanged owned orphan. Runtime uninstall never scans or cleans project
adapters, and adapter operations never modify `.gitignore` or
`.git/info/exclude`.
