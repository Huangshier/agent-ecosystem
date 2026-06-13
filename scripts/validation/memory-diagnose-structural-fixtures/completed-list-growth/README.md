# Memory Diagnose Structural Fixtures: Completed List Growth

Status: implementation coverage for issue #155 after PR #160, PR #161, and
PR #162.

These fixtures support the `Completed list growth` diagnostic family from
`docs/roadmap/memory-diagnose-structural-diagnostics.md`. The current
`memory_diagnose.ps1` helper reports `process_completed_list_growth` for the
positive fixture and keeps the compact negative fixture clean.

## Fixtures

- `compact-active-phase`: negative fixture. It represents a concise active
  phase with one recent completed entry. The completed-list diagnostic should
  not report a finding for this shape.
- `process-history-backlog`: positive fixture. It represents a `process.txt`
  that keeps many completed entries in hot memory. The completed-list
  diagnostic reports an `info` finding for this shape.

## Validation Boundary

- The current diagnosis helper should report zero findings for
  `compact-active-phase`.
- The current diagnosis helper should report `process_completed_list_growth`
  for `process-history-backlog`.
- Default bootstrap projects should remain clean.

## Non-Goals

- No information-density heuristic is implemented here.
- No `LargeFileLineThreshold` value is changed here.
- No JSON output shape or human output shape is changed here.
