# Memory Diagnose Structural Fixtures: Completed List Growth

Status: fixture-only coverage for issue #155 after PR #160 and PR #161.

These fixtures support the `Completed list growth` diagnostic family from
`docs/roadmap/memory-diagnose-structural-diagnostics.md`. They intentionally do
not change `memory_diagnose.ps1` behavior.
This fixture-only set does not change `memory_diagnose.ps1` behavior.

## Fixtures

- `compact-active-phase`: negative fixture. It represents a concise active
  phase with one recent completed entry. Future structural diagnostics should
  not report a completed-list finding for this shape.
- `process-history-backlog`: positive fixture. It represents a `process.txt`
  that keeps many completed entries in hot memory. Future structural
  diagnostics may report a completed-list finding for this shape.

## Validation Boundary

- The current diagnosis helper should report zero findings for both fixtures.
- The `expected.json` files document the future structural outcome separately
  from current helper behavior.
- A later implementation PR may use the positive fixture to prove a new
  `info` finding, but that PR should keep default bootstrap projects clean.

## Non-Goals

- No Completed entry count detection is implemented here.
- No information-density heuristic is implemented here.
- No `LargeFileLineThreshold` value is changed here.
- No diagnosis severity, finding code, JSON output, or human output behavior is
  changed here.
