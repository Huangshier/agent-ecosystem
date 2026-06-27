# Memory Diagnose Structural Fixtures: Hot Memory Soft-Length

Status: implementation coverage for issue #167 first slice.

These fixtures support the `Hot memory soft-length` diagnostic family in
`skills/memory-governance/scripts/memory_diagnose.ps1`. The helper reports
`hot_memory_process_long` when `process.txt` exceeds the soft line limit
(default 30) and `hot_memory_plan_long` when `plan.md` exceeds its soft
line limit (default 20).

The soft-length checks are separate from the existing
`LargeFileLineThreshold` (default 160) warning. They produce `info`-level
findings that recommend compressing hot session memory and migrating
long-lived content to `docs/specs` or `.agents/context`.

## Fixtures

- `concise-current-state`: negative fixture. Both `process.txt` and
  `plan.md` are within their soft limits. The helper should produce zero
  soft-length findings.
- `overloaded-hot-memory`: positive fixture. `process.txt` exceeds the
  30-line soft limit and `plan.md` exceeds the 20-line soft limit. The
  helper should produce both `hot_memory_process_long` and
  `hot_memory_plan_long` findings at `info` severity.

## Validation Boundary

- The current diagnosis helper should report zero findings for
  `concise-current-state`.
- The current diagnosis helper should report both
  `hot_memory_process_long` and `hot_memory_plan_long` for
  `overloaded-hot-memory`.
- Default bootstrap projects should remain clean.

## Non-Goals

- No knowledge maturity scoring, last_accessed tracking, or automatic
  decay is implemented here.
- No change to the existing `LargeFileLineThreshold` semantics.
- No error-driven sedimentation logic.
