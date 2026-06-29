# Eval Iteration Fixtures

Status: seventh slice (iteration artifact + benchmark contract). Issue #166.

These fixtures validate the static structure of eval case definitions
for a kernel skill eval pilot. They do not invoke an eval runner,
generate skill output, or call any LLM. The fixtures verify that
evals.json files conform to the expected schema shape and contain
required fields.

## Pilot Skill: workflow-spec-lite

The first eval pilot targets `workflow-spec-lite`, a kernel skill
for lightweight spec-first project workflow. The eval suite covers
three dimensions:

- **trigger-accuracy**: non-trivial multi-module work should activate
  the skill; trivial single-file fixes should not.
- **output-structure**: the generated spec must contain required
  sections (Summary, Goals, Non-Goals, Constraints, Risks, Acceptance)
  and metadata fields.
- **safety-boundary**: the skill must not create `docs/specs/` in the
  public agent-ecosystem repo, and must never create `plan.md` under
  `docs/specs/`.

## Fixture Structure

```
eval-iteration-fixtures/
  README.md               (this file)
  workflow-spec-lite/
    evals.json            (eval suite for workflow-spec-lite)
    expected.json         (static validation expectations)
    report.json           (static PASS/FAIL report artifact)
    baseline.json         (static baseline recording for comparison)
    runner-output-schema.json   (runner output JSON Schema contract)
    runner-output-example.json  (static example conforming to the schema)
    iterations/
      iteration-001/
        benchmark.json    (static benchmark artifact for iteration 001)
scripts/validation/
  release-eval-report-generator.ps1     (deterministic report artifact generator)
  release-eval-runner-generator.ps1     (deterministic runner output artifact generator)
  release-eval-benchmark-generator.ps1  (deterministic benchmark artifact generator)
```

## Runner Output Generator

`release-eval-runner-generator.ps1` provides a deterministic, offline runner
output artifact generation path. It reads `evals.json` and `expected.json`,
validates the fixture shape, expands assertions into per-assertion
`assertion_details`, and produces an artifact matching the committed
`runner-output-example.json` structure.

The release validator includes a "runner output regeneration" check that
invokes this generator and compares the output against the committed
`runner-output-example.json`. This proves the example is deterministically
reproducible from source fixtures, not hand-maintained.

The generator is standalone: it can be used outside the release validator
to regenerate the runner output artifact on demand.

```powershell
# Regenerate runner-output-example.json (writes to stdout)
pwsh -NoProfile -File scripts/validation/release-eval-runner-generator.ps1 `
  -EvalsJsonPath scripts/validation/eval-iteration-fixtures/workflow-spec-lite/evals.json `
  -ExpectedJsonPath scripts/validation/eval-iteration-fixtures/workflow-spec-lite/expected.json
```

No eval runner, LLM calls, or network access occurs during generation.

## Report Generation

`release-eval-report-generator.ps1` provides a deterministic, offline report
generation path. It reads `evals.json` and `expected.json`, validates the
fixture shape, computes the eval results, and produces a report artifact
matching the committed `report.json` structure.

The release validator includes a "eval report regeneration" check that
invokes this generator and compares the output against the committed
`report.json`. This proves the report artifact is deterministically
reproducible from source fixtures, not hand-maintained.

The generator is standalone: it can be used outside the release validator
to regenerate the report artifact on demand.

```powershell
# Regenerate report.json (writes to stdout)
pwsh -NoProfile -File scripts/validation/release-eval-report-generator.ps1 `
  -EvalsJsonPath scripts/validation/eval-iteration-fixtures/workflow-spec-lite/evals.json `
  -ExpectedJsonPath scripts/validation/eval-iteration-fixtures/workflow-spec-lite/expected.json
```

No eval runner, LLM calls, or network access occurs during generation.

## Report Artifact

`workflow-spec-lite/report.json` is a deterministic static report artifact
that represents the expected shape of an eval report. It does not invoke
an eval runner or LLM. The artifact records:

- Per-eval-case results: eval_id, status (PASS/FAIL), assertion counts.
- Failure reason shape: when an assertion fails, the finding includes
  eval_id, assertion_type, expected, and actual fields.
- Summary totals: eval_count, evals_passed, evals_failed,
  assertions_total, assertions_passed, assertions_failed, overall status.

The release validator verifies that report.json exists, is valid JSON,
contains eval IDs matching evals.json, and that summary totals are
consistent with the per-eval results.

## Baseline Artifact

`workflow-spec-lite/baseline.json` is a deterministic static baseline
recording that captures the baseline identity, source references, eval
coverage, and status summary for future with-skill / without-skill
comparison. It does not invoke an eval runner or LLM. The artifact
records:

- Baseline identity: name, version, scope.
- Baseline source: paths to evals.json, report.json, expected.json.
- Eval IDs: matching evals.json eval case IDs.
- Assertion totals: eval_count, assertions_total, per-eval assertion counts.
- Status summary: evals_passed/failed, assertions_passed/failed, overall status.
- Comparison fields: baseline_pass_rate, with_skill_pass_rate, delta,
  iteration_count (reserved for future use).

The release validator verifies that baseline.json exists, is valid JSON,
contains eval IDs matching evals.json, assertion totals matching
evals.json, status summary matching report.json summary (field-by-field
consistency), baseline-source paths pinned to expected values, and
comparison field numeric types and ranges (pass rates in 0..1,
iteration_count as integer).

## Runner Output Contract

`runner-output-schema.json` is a JSON Schema (draft 2020-12) that
defines the output artifact contract for a future eval runner. It
specifies:

- **runner_metadata**: name, version, mode (static/live), skill, skill_version.
- **execution_metadata**: started_at, finished_at, duration_ms.
- **eval_results[]**: per-eval-case results with eval_id, status
  (PASS/FAIL/ERROR), assertion counts, and assertion_details[].
- **assertion_details[]**: per-assertion results with type, expected,
  actual, and passed boolean.
- **comparison_metadata**: fields for future with-skill vs without-skill
  comparison (comparison_mode, paired_run_id, pass rates, delta).
- **summary**: overall counts and status, consistent with report.json
  summary shape.

The schema uses `$defs` for reusable sub-schemas (eval_result,
assertion_detail, report_summary) and defines both the structural
contract and the failure reason shape.

`runner-output-example.json` is a static fixture that conforms to the
schema. It demonstrates what a future eval runner would produce for the
workflow-spec-lite eval suite in static mode (all assertions pass, no
LLM invoked). The example includes:

- Synthetic runner_metadata (name: "eval-runner-static-fixture",
  mode: "static").
- Placeholder execution_metadata (duration_ms: 0).
- Per-assertion details for all 12 assertions across 3 eval cases.
- comparison_metadata with comparison_mode "none".
- Summary totals matching report.json and evals.json.

The release validator verifies that:
- Both schema and example files exist and are valid JSON.
- The schema defines the required top-level properties.
- The example conforms to all required fields (runner_metadata,
  execution_metadata, eval_results with assertion_details, summary).
- The example's eval IDs match evals.json.
- The example's assertion_details count matches evals.json assertion count
  per eval case.
- The example's summary totals are consistent with per-eval results.

## Iteration Artifact / Benchmark Contract

`iterations/iteration-001/benchmark.json` is a deterministic static
benchmark artifact that records pass rate, comparison metadata, delta
placeholder, iteration index, and source references for a synthetic
iteration. It does not invoke an eval runner or LLM.

The benchmark artifact:

- **benchmark_identity**: unique name, iteration number, and description.
- **source_refs**: pinned paths to evals.json, report.json, baseline.json,
  runner-output-example.json, and runner-output-schema.json.
- **pass_rate**: overall pass rate, eval counts, assertion counts, and
  status back-linked to the report artifact.
- **comparison_metadata**: comparison_mode, baseline_pass_rate,
  comparison_pass_rate, delta, delta_placeholder, iteration_count, and
  paired_benchmark_id — all placeholder values for pre-live-eval state.
- **eval_ids**: eval case IDs matching evals.json.

The release validator verifies that:
- benchmark.json parses as valid JSON.
- Required top-level fields exist (skill, version, fixture, iteration_type,
  iteration_index, benchmark_identity, source_refs, pass_rate,
  comparison_metadata, eval_ids).
- Benchmark identity contains name, iteration, and description.
- Source refs contain all five expected paths.
- Pass rate contains rate, eval_count, evals_passed/failed,
  assertions_total/passed/failed, and status.
- Comparison metadata contains comparison_mode, baseline_pass_rate,
  comparison_pass_rate, delta, delta_placeholder, iteration_count, and
  paired_benchmark_id.
- Pass rate counts and summary are consistent with evals.json and
  report.json.
- Eval IDs match evals.json.
- Iteration index is 1 and comparison mode is "baseline" (expected
  baseline values from expected.json).

### Benchmark Generation

`release-eval-benchmark-generator.ps1` provides a deterministic, offline
benchmark artifact generation path. It reads `evals.json` and
`expected.json`, validates the fixture shape, computes pass rate and
comparison metadata, and produces an artifact matching the committed
`benchmark.json` structure.

The release validator includes a "benchmark regeneration" check that
invokes this generator and compares the output against the committed
`benchmark.json`. This proves the benchmark artifact is deterministically
reproducible from source fixtures, not hand-maintained.

```powershell
# Regenerate benchmark.json (writes to stdout)
pwsh -NoProfile -File scripts/validation/release-eval-benchmark-generator.ps1 `
  -EvalsJsonPath scripts/validation/eval-iteration-fixtures/workflow-spec-lite/evals.json `
  -ExpectedJsonPath scripts/validation/eval-iteration-fixtures/workflow-spec-lite/expected.json
```

No eval runner, LLM calls, or network access occurs during generation.

## Runner Output Regeneration

`release-eval-runner-generator.ps1` is a standalone, offline, deterministic
script that reads `evals.json` and `expected.json`, validates fixture shape,
expands each assertion into per-assertion `assertion_details`, and produces
a runner output artifact conforming to `runner-output-schema.json`. It does
not invoke an eval runner, LLM, or external service.

The generator is the canonical source for the committed
`runner-output-example.json`. The release validator includes a "runner output
regeneration" check that invokes this generator and compares the output against
the committed example. This proves the example is deterministically reproducible
from source fixtures, not hand-maintained:

```powershell
# 重新生成 runner-output-example.json（输出到 stdout）
pwsh -NoProfile -File scripts/validation/release-eval-runner-generator.ps1 `
  -EvalsJsonPath scripts/validation/eval-iteration-fixtures/workflow-spec-lite/evals.json `
  -ExpectedJsonPath scripts/validation/eval-iteration-fixtures/workflow-spec-lite/expected.json
```

The comparison is structured (field-by-field), not JSON-string-based, to be
deterministic across PowerShell versions. Execution timestamps are excluded
from comparison. In static deterministic mode, every `actual` field equals
the corresponding `expected` field and every `passed` field is `true`.

## Schema Validation Expectations

`workflow-spec-lite/expected.json` defines the static validation
expectations:

- The JSON must parse without error.
- Top-level fields `skill`, `version`, and `evals` must exist.
- Each eval case must have `id`, `input`, and `assertions`.
- Each assertion must have `type` and `expected`.
- All assertion `type` values must be from the allowed enum:
  `skill_should_trigger`, `skill_should_not_trigger`,
  `output_contains`, `output_not_contains`, `output_exact_match`,
  `output_regex`, `output_token_count_below`, `output_file_created`,
  `output_file_not_created`.
- Expected eval count, assertion count, and eval IDs must match.
- README must contain required tokens documenting the pilot scope.
- Benchmark artifact structure, required fields, summary consistency,
  path references, and deterministic regeneration.

## Validation Boundary

The release validator performs only static checks:

- File existence and JSON parse validity.
- Required field presence and type checking.
- Assertion type enum validation.
- Eval count, assertion count, and eval ID validation.
- Report artifact PASS/FAIL status semantics and summary consistency.
- Baseline artifact source paths, assertion totals, and comparison field shape.
- Runner output schema and example structural conformance.
- Per-assertion detail count consistency between example and evals.json.
- Benchmark artifact structural conformance, pass rate consistency, and
  source ref validation.
- README token presence.

No skill execution, LLM calls, or eval runner invocation occurs.

## Non-Goals

- No working eval runner or evaluation engine.
- No LLM-based grading or assertion evaluation.
- No network dependencies or external service calls.
- No private paths, credentials, or runtime state.
- No integration with Anthropic skill-creator, Promptfoo, or
  external eval frameworks.
