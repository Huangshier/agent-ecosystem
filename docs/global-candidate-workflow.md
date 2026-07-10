# Global Candidate Intake And Triage

This workflow keeps project-local experience, runtime review candidates, and
formal global experience as three separate lifecycle layers.

```text
project-local experience
  -> explicit read-only discovery
  -> <runtime>/state/knowledge-candidates/
  -> human triage
  -> explicit promotion decision
  -> public issue / pull request and formal experience
```

Candidate intake never calls `promote_experience.ps1` and never writes
`knowledge-hub/knowledge/experience/**`.

## Candidate Contract

Each candidate is a Markdown file with JSON front matter and the canonical
English `## Summary` and `## Keywords` anchors. The independent candidate
contract starts at `schema_version: 1`.

File names use:

```text
YYYY-MM-DD-<normalized-title-slug>-<12-character-dedupe-hash>.md
```

The observed date defaults to the current UTC date. Supply `-ObservedOn
YYYY-MM-DD` for a reproducible historical import; candidate identity and the
dedupe hash do not depend on that date, and later reruns keep the original
`first_seen_on` file name.

The dedupe key is exactly:

```text
language + normalized_title + normalized_summary_hash
```

The allowed states are:

- `pending_review`
- `accepted`
- `rejected`
- `superseded`

Repeated evidence with the same dedupe key updates the same candidate. A local
occurrence is identified by project root, source file, and source file bytes,
so an unchanged rerun is idempotent while an independent reproduction raises
`occurrence_count`.

Public-safe fields contain the candidate ID, dedupe metadata, language, title,
summary, keywords, status, occurrence count, dates, and reviewed relationships.
The `_local` object may contain explicit project roots, source files, source
hashes, reviewer identity, and private review notes. `_local` is never included
in public export.

The Markdown front matter is a JSON object with this shape:

```json
{
  "schema_version": 1,
  "candidate_id": "candidate-<dedupe-sha256>",
  "dedupe_key": "<language>|<normalized_title>|<normalized_summary_hash>",
  "language": "zh-CN",
  "title": "<source-language title>",
  "normalized_title": "<normalized title>",
  "summary": "<public-safe summary>",
  "normalized_summary_hash": "<sha256>",
  "keywords": ["<keyword>"],
  "status": "pending_review",
  "occurrence_count": 1,
  "first_seen_on": "YYYY-MM-DD",
  "last_seen_on": "YYYY-MM-DD",
  "reviewed_on": "",
  "superseded_by": "",
  "merged_from": [],
  "_local": {
    "sources": [],
    "reviews": []
  }
}
```

## Commands

The installed authority is `knowledge-hub/scripts/manage_candidates.ps1`.
`project-bootstrap` ships an identical compatibility copy for standalone
runtime initialization.

Default discovery reads an existing inbox:

```powershell
pwsh -NoProfile -File <runtime>/knowledge-hub/scripts/manage_candidates.ps1 `
  -Mode Discover `
  -InboxDir <runtime>/state/knowledge-candidates/
```

Explicit project-root scanning is a read-only legacy import or recovery path.
Language is supplied explicitly; the helper does not infer it:

```powershell
pwsh -NoProfile -File <runtime>/knowledge-hub/scripts/manage_candidates.ps1 `
  -Mode Discover `
  -ProjectRoot <project-a>,<project-b> `
  -Language en,zh-CN `
  -Json
```

Intake discovered candidates into an explicit runtime inbox:

```powershell
pwsh -NoProfile -File <runtime>/knowledge-hub/scripts/manage_candidates.ps1 `
  -Mode Intake `
  -InboxDir <runtime>/state/knowledge-candidates/ `
  -ProjectRoot <project-a>,<project-b> `
  -Language en,zh-CN
```

List or inspect candidate state:

```powershell
pwsh -NoProfile -File <runtime>/knowledge-hub/scripts/manage_candidates.ps1 `
  -Mode List `
  -InboxDir <runtime>/state/knowledge-candidates/ `
  -Json
```

Generate a public-safe summary on stdout:

```powershell
pwsh -NoProfile -File <runtime>/knowledge-hub/scripts/manage_candidates.ps1 `
  -Mode Export `
  -InboxDir <runtime>/state/knowledge-candidates/ `
  -Json
```

Record a human triage decision:

```powershell
pwsh -NoProfile -File <runtime>/knowledge-hub/scripts/manage_candidates.ps1 `
  -Mode Triage `
  -InboxDir <runtime>/state/knowledge-candidates/ `
  -CandidateId <candidate-id> `
  -Status accepted `
  -ReviewedBy <reviewer>
```

Use `-SupersededBy <candidate-id>` with `-Status superseded`. Use
`-MergeCandidateId <candidate-id>` to mark one or more other candidates as
merged into the selected target. Intake and triage fully preflight the inbox,
stage the complete result, validate it, and then replace the inbox as one
transaction.

A merge relation is bidirectional: if target `A` lists source `B` in
`merged_from`, `B` must be `superseded` and its `superseded_by` value must be
exactly `A`. One source cannot belong to multiple merge targets. Retriaging a
merged source or moving it to another merge target fails until a future
explicit unmerge operation removes the old relation; this workflow does not
silently rewrite merge ownership.

## Public And Private Boundary

Discovery reads only explicitly supplied project roots. The helper does not
scan a home directory, private overlay, unlisted repository, or live agent
runtime. Its only durable write target is the explicitly supplied candidate
inbox; staging and rollback directories are temporary siblings of that inbox.

Project roots, the inbox, its parent, and transaction paths are compared by
their canonical physical locations. Junction and symbolic-link ancestors are
resolved segment by segment, including relative Unix-like link targets and
multi-link chains. Broken links, cycles, unreadable targets, excessive link
hops, or physical overlap between a project root and the writable inbox fail
before staging. A safe alias outside every project root remains supported, and
the transaction writes only through the validated physical target.

Public export is a summary list, not candidate Markdown. Human and JSON export
omit:

- `_local` and local reviewer notes;
- absolute paths and private repository mappings;
- raw logs, transcripts, and complete candidate bodies;
- access material.

`title`, `summary`, and every `keywords` value are checked when discovery
creates a candidate, whenever an existing inbox entry is read, and again before
human or JSON export. The fail-closed rules cover common absolute paths,
credential and authorization forms, major provider token/key shapes, private
key markers, raw evidence forms, and private repository/access mappings.
Failures identify only the field and rule category, never the rejected value.

Malformed existing candidates, unsupported schema or status values, duplicate
candidate IDs, duplicate entries for one dedupe key, conflicting normalized
metadata, missing relationships, and superseded cycles fail before writes.
`merged_from` self-references, duplicates, missing IDs, conflicting owners, and
one-sided merge metadata fail at the same preflight boundary.

## Review Decision Checklist

Keep the lesson project-local when its fix depends on repository business
logic, private environment details, or a single unconfirmed observation.

Use the candidate inbox when a marked lesson may be cross-project reusable but
needs comparison, deduplication, recurrence evidence, redaction, or lifecycle
review. Private review may inspect `_local`; public review must use only
`-Mode Export` output.

Create a public issue or Draft PR only after a human confirms that the summary
is public-safe, the lesson is cross-project reusable, source evidence can be
described without private mappings, and the proposed promotion scope is
explicit. Formal promotion remains a separate command and review decision.

## Non-Goals

This workflow does not add automatic promotion, telemetry, background sync,
language detection, schema v3, localized metadata aliases, search migration, a
remote service, a database, or an uninstaller.
