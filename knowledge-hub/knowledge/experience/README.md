# Shared Experience Knowledge

Promoted cross-project experience files live here.

Index metadata is stored in `index.json`.

The first public release may include reindexed backfill entries migrated from
the pre-release knowledge hub. Their index records intentionally omit local
source paths and private migration details; the Markdown experience file is the
public source of truth.

## Retrieval Rule
- Do not preload this directory into normal project sessions.
- Search `index.json` first and open only matching experience entries when the issue looks related to toolchains, host environment, shell behavior, build systems, caches, ports, permissions, path handling, or other cross-project workflow failures.

## Promotion Rule
- Promote a lesson here when the root cause is primarily toolchain/host/workflow driven, the fix does not depend on current repository business code, and the lesson can be stated as a stable prevention rule.
- If the issue is likely repository-specific, keep it in project-local `.agents/context/experience/` first and promote only after recurrence or cross-project confirmation.
- Project-local source files should explicitly say `Global candidate: Yes` or `Scope: Cross-project reusable` before the default promotion command will pick them up.
- Marked local experience can enter `<runtime>/state/knowledge-candidates/` for deduplication and human triage before promotion. An inbox candidate is not a promoted experience entry; only an explicit human promotion decision may invoke the separate promotion path.

## Language And Metadata Contract

The knowledge hub is English-first and localized-aware. English-first applies to
the stable Markdown anchors consumed by promotion, rebuild, validation, and
search; it does not require English titles, prose, summaries, keywords, or
metadata values. A project-local experience may therefore be written in
Simplified Chinese (or another supported project language) and still be
promoted when it preserves these English anchors:

- `## Summary`
- `## Keywords`
- `Global candidate: Yes` or `Scope: Cross-project reusable`
- Lifecycle fields: `Maturity`, `Scope`, `Source`, `Last reviewed`, and
  `Decay policy`

Do not replace these anchors with localized aliases in a promotion candidate.
The current helpers intentionally do not detect language or parse aliases such
as `摘要`, `关键词`, `全局候选`, or `范围`; an aliases-only candidate is skipped by
default. This contract does not introduce schema v3 or localized metadata
aliases. Keep lifecycle values public-safe even when the project-local prose is
localized.

## Maintenance Rule
- `index.json` is the lightweight discovery registry for this directory, not the primary editing target.
- Maintain this registry through installed `knowledge-hub/scripts`: `promote_experience.ps1` for reviewed project-to-hub promotion and `rebuild_experience_index.ps1` for backfill or repair when hub files already exist.
- Maintain the separate local candidate inbox through `manage_candidates.ps1`; it does not mutate this directory or `index.json`.
- Experience files should include public lifecycle metadata near the top so
  the catalog and generated index can distinguish draft, verified, proven, and
  deprecated entries without relying on local runtime usage telemetry.

## Lifecycle Metadata Contract
- `Maturity`: one of `draft`, `verified`, `proven`, or `deprecated`.
- `Scope`: public-safe reuse boundary, such as `cross-project`.
- `Source`: public-safe source evidence or migration record. Do not include
  private paths, raw local logs, private repository mappings, or private-only
  identifiers.
- `Last reviewed`: ISO date (`YYYY-MM-DD`) for the last public review.
- `Decay policy`: human-reviewed lifecycle guidance for when the entry should
  be rechecked, downgraded, deprecated, or left stable.

`rebuild_experience_index.ps1` derives index lifecycle fields from these
Markdown metadata lines:

- `maturity`
- `scope`
- `source`
- `reviewed_at`
- `decay_policy`

The generated index is public durable metadata. It must not record
`last_accessed`, search/read telemetry, local runtime usage, scratch paths, or
private overlay evidence. Reading experience entries with
`search_experience.ps1` is intentionally non-mutating.
