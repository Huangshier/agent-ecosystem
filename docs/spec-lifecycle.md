# Spec Lifecycle and Review Status Hygiene

This document defines how `docs/specs/**` work packages are managed through
their lifecycle, and how agents should maintain review status metadata without
rewriting historical evidence.

## Spec Status Values

Every `docs/specs/<slug>/spec.md` must declare a status in its frontmatter
area (the `- **Status**:` line near the top):

| Status | Meaning |
| --- | --- |
| `Draft` | Work package defined but not yet approved or started. |
| `Active` | Work is in progress; an open PR or issue tracks it. |
| `Done` | Work is complete. A merged PR, closed issue, or published release provides evidence. |
| `Archived` | Work is complete and no longer relevant to current planning. Kept for historical evidence only. |
| `Superseded` | Replaced by a newer spec or approach. Kept for traceability. |
| `Deferred` | Accepted but intentionally postponed to a future version or milestone. |

Use `Done` (not `Completed`) for finished work. One historical spec uses
`Completed`; new work and updates should use `Done`.

## When to Keep a Completed Spec in Place

Completed specs stay in `docs/specs/<slug>/` by default. Do not move, rename,
or delete a completed spec unless:

- A maintainer explicitly requests archival or deletion.
- The spec is being replaced by a successor that links back to it.

Completed specs are evidence. They document what was decided, when, and why.
Moving them breaks links from PRs, issues, and release notes that reference
their path.

## Marking a Spec as Archived

When a completed spec is no longer relevant to current planning but should
remain as historical evidence:

1. Change `- **Status**: Done` to `- **Status**: Archived`.
2. Add a one-line `## Archive Note` section at the bottom explaining why it
   was archived and linking to any successor spec.
3. Do not rewrite the spec body, task checkboxes, or acceptance evidence.

## How Agents Update Active Status

Agents may update spec status when the change is clearly supported by evidence
(e.g., a PR merged, an issue closed). Rules:

- Only change the `- **Status**:` line. Do not rewrite summary, goals,
  acceptance criteria, or task history.
- When moving from `Active` to `Done`, add the merge commit hash or release
  tag as evidence in the spec if not already present.
- Never move a spec from `Done` to `Active` without explicit maintainer
  instruction.
- Never mark a spec `Archived` without a reason in the Archive Note section.

## Review Status Hygiene for Agent-Created Specs

Agent-created specs follow the same lifecycle but have additional hygiene
requirements:

1. **Link to issue**: Every agent-created spec should reference its tracking
   issue number in the Summary section.
2. **Scope boundary**: The spec must state what it does *not* do (Non-Goals
   section).
3. **Evidence on completion**: When marking `Done`, the spec must include the
   merged PR number, merge commit, or release version as proof.
4. **No orphaned active specs**: Agents should not leave specs in `Active`
   state when the corresponding issue is closed and no PR is open. If the
   work was abandoned, mark as `Deferred` with a note.

## Validation Expectations

Changes to spec lifecycle are docs-only and should pass:

```powershell
git diff --check
```

For changes that also touch release-facing files or scripts, additionally run:

```powershell
pwsh -NoProfile -File scripts/validate-release.ps1 -ScratchRoot <scratch>
```

Lifecycle-only changes (status line updates, archive notes) do not require
the full release validator unless they are part of a release preparation PR.

## Narrow Cleanup Guidance

When performing a lifecycle cleanup pass:

- Audit status values against issue/PR state. If the issue is closed and the
  PR is merged, the spec should be `Done`.
- Normalize inconsistent status values (e.g., `Completed` to `Done`).
- Do not rename directories or move files in the same PR as status updates
  unless explicitly scoped.
- Do not batch more than one logical concern per PR (e.g., do not combine
  lifecycle cleanup with new feature documentation).
