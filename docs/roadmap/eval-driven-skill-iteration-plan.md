# Eval-Driven Skill Iteration Plan

Status: active (multiple slices merged). Issue #166.

This plan defines the eval-driven skill iteration mechanism for
agent-ecosystem. The first five slices established the public-safe design
boundary, eval schema draft, fixture shape, deterministic report generation,
and runner output contract. The sixth slice added a deterministic runner
output artifact generator and regeneration verification. The seventh slice
adds an iteration artifact / benchmark contract for recording eval iteration
pass rates, comparison metadata, and source references. It does not
implement a working eval runner, LLM grading, or external service
integration.

## Problem Statement

Current skill improvement depends on manual prompt optimization with
no data-driven evaluation loop. Changes are validated by subjective
"feels better" assessment rather than measured pass/fail assertions.

## Eval Schema Draft

Each skill's eval suite lives in `skills/<skill>/evals/evals.json`.
The schema defines a list of eval cases:

```json
{
  "skill": "<skill-name>",
  "version": 1,
  "evals": [
    {
      "id": "<eval-case-id>",
      "description": "human-readable case description",
      "input": {
        "prompt": "the user prompt or context that triggers the skill",
        "context": {}
      },
      "assertions": [
        {
          "type": "<assertion-type>",
          "expected": "<expected-value-or-pattern>",
          "description": "what this assertion checks"
        }
      ]
    }
  ]
}
```

### Assertion Types

| Type | Semantics | Example |
| --- | --- | --- |
| `skill_should_trigger` | Skill activates for the given input | `"expected": "true"` |
| `skill_should_not_trigger` | Skill must not activate for the input | `"expected": "true"` |
| `output_contains` | Skill output contains the expected substring | `"expected": "## Summary"` |
| `output_not_contains` | Skill output must not contain the substring | `"expected": "docs/specs/<slug>/plan.md"` |
| `output_exact_match` | Skill output equals expected string after trimming | `"expected": "PASS"` |
| `output_regex` | Skill output matches the expected regex pattern | `"expected": "Status: (draft\|verified)"` |
| `output_token_count_below` | Skill output token count is below threshold | `"expected": "500"` |
| `output_file_created` | A file at the expected path was created by the skill | `"expected": "docs/specs/foo/spec.md"` |
| `output_file_not_created` | No file at the expected path was created | `"expected": "docs/specs/"` |

Future assertion types (not in first slice):

- `llm_grade`: LLM-based quality grading with rubric.
- `human_review`: Flags case for manual review.

### Assertion Shape (JSON Schema)

```json
{
  "type": "object",
  "required": ["type", "expected"],
  "properties": {
    "type": {
      "type": "string",
      "enum": ["skill_should_trigger", "skill_should_not_trigger", "output_contains", "output_not_contains", "output_exact_match", "output_regex", "output_token_count_below", "output_file_created", "output_file_not_created"]
    },
    "expected": { "type": "string" },
    "description": { "type": "string" }
  }
}
```

## With-Skill vs Without-Skill Baseline

The eval iteration mechanism should support comparing skill-augmented
runs against baseline (no skill) runs. This quantifies the delta value
a skill provides.

### Direction (future)

1. Run eval suite with skill active → collect `pass_rate_with_skill`.
2. Run eval suite without skill → collect `pass_rate_without_skill`.
3. Compute `delta = pass_rate_with_skill - pass_rate_without_skill`.
4. If `delta <= 0` across two consecutive iterations, stop iterating.

### Non-Goals for First Slice

- No actual LLM invocation or grading.
- No integration with Anthropic skill-creator, Promptfoo, or any
  external eval service.
- No network dependencies.
- No automated iteration loop (the runner, scheduler, and convergence
  check are all future work).
- No A/B blind evaluation.
- No token efficiency measurement.

## Validation Boundary

The first slice validation is entirely static:

1. Fixture directory exists with expected structure.
2. `evals.json` fixture parses as valid JSON.
3. Fixture JSON contains the required top-level fields
   (`skill`, `version`, `evals`).
4. Each eval case has `id`, `input`, and `assertions`.
5. Each assertion has `type` and `expected` fields.
6. Assertion `type` values are from the defined enum.
7. `report.json` records per-eval PASS/FAIL status with consistent
   summary totals and locked status semantics.
8. `baseline.json` records baseline identity, source references, eval
   coverage, and status summary for future comparison.
9. README fixture documents the required tokens.
10. `report.json` is deterministically reproducible from `evals.json`
    and `expected.json` via the standalone report generator.
11. `runner-output-schema.json` defines the runner output JSON Schema
    contract with required properties, `$defs` sub-schemas, and
    structural constraints.
12. `runner-output-example.json` is a static fixture conforming to the
    schema, with eval IDs matching `evals.json`, per-assertion
    `assertion_details` structurally consistent, comparison_metadata
    present, and summary totals coherent.
13. `release-eval-runner-generator.ps1` provides a deterministic, offline
    runner output artifact generation path that reads `evals.json` and
    `expected.json`, expands assertions into per-assertion
    `assertion_details`, and produces an artifact matching
    `runner-output-example.json`.
14. The release validator includes a "runner output regeneration" check
    that invokes the generator and verifies the committed example is
    deterministically reproducible from source fixtures.
15. In static deterministic mode, every `actual` field equals the
    corresponding `expected` field and every `passed` field is `true`.

No eval runner is invoked. No skill output is generated. No LLM calls
are made.

## Pilot Skill

The first eval pilot targets `workflow-spec-lite`, a kernel skill for
lightweight spec-first project workflow. The eval suite covers:

- **Trigger accuracy**: non-trivial multi-module work should activate
  the skill; trivial single-file fixes should not.
- **Output structure**: the generated spec must contain required
  sections (Summary, Goals, Non-Goals, Constraints, Risks, Acceptance).
- **Safety boundary**: the skill must not create `docs/specs/` in the
  public agent-ecosystem repo, and must never create `plan.md`.

## Fixture Location

```
scripts/validation/eval-iteration-fixtures/
  README.md
  workflow-spec-lite/
    evals.json
    expected.json
    report.json
    baseline.json
    runner-output-schema.json
    runner-output-example.json
    iterations/
      iteration-001/
        benchmark.json
scripts/validation/release-eval-report-generator.ps1
scripts/validation/release-eval-runner-generator.ps1
scripts/validation/release-eval-benchmark-generator.ps1
```

## Runner Output Contract

The runner output contract defines the output artifact shape for a future
eval runner. It is specified as a JSON Schema (draft 2020-12) in
`runner-output-schema.json` with a static example in
`runner-output-example.json`.

### Contract Design Decisions

- **schema_version vs contract_version**: `schema_version` (integer)
  tracks the JSON Schema structure; `contract_version` (semver string)
  tracks the semantic contract independently of the eval suite version.
  This allows the schema to evolve without changing the contract version
  if the change is purely structural.
- **mode field**: `runner_metadata.mode` distinguishes `static` (fixture-
  based, deterministic) from `live` (actual skill execution, possibly
  with LLM grading). The current example uses `static` mode only.
- **assertion_details**: Per-assertion results are required (not optional)
  in the runner output, even though `report.json` only has per-eval
  counts. This is because the runner must produce per-assertion evidence
  for debugging and comparison, while report.json is a summary artifact.
- **comparison_metadata**: Reserved for future with-skill vs without-skill
  comparison. The example uses `comparison_mode: "none"` to indicate no
  comparison is active.
- **ERROR status**: The eval_result status enum includes `ERROR` in
  addition to `PASS` and `FAIL`, to represent runner execution failures
  (e.g., skill crash, timeout). The current static example does not use
  `ERROR`.

### Future Work

- Implement a live eval runner that produces artifacts conforming to
  `runner-output-schema.json`.
- Add `llm_grade` assertion type and corresponding runner support.
- Implement with-skill vs without-skill comparison using
  `comparison_metadata`.
- Add convergence detection based on delta trends across iterations.
- Expand the iterations/ tree with additional synthetic or live
  iteration-N/ benchmark.json artifacts.

### Benchmark Contract

The benchmark contract defines an iteration-level artifact that records
pass rate, comparison metadata, delta placeholder, iteration index, and
source references for each eval iteration.

`iterations/iteration-001/benchmark.json` is a deterministic static
benchmark artifact:

- **benchmark_identity**: unique name, iteration number, and description
  for this iteration.
- **source_refs**: pinned paths to evals.json, report.json, baseline.json,
  runner-output-example.json, and runner-output-schema.json.
- **pass_rate**: overall pass rate, eval counts, assertion counts, and
  status back-linked to the report artifact.
- **comparison_metadata**: comparison_mode ("baseline" for static baseline
  recordings), pass rates, delta placeholder, iteration_count, and
  paired_benchmark_id — all reserved for future live eval comparison.
- **eval_ids**: eval case IDs matching evals.json.

`release-eval-benchmark-generator.ps1` provides a deterministic, offline
benchmark artifact generation path. It reads `evals.json` and
`expected.json`, validates the fixture shape, computes pass rate and
comparison metadata, and produces an artifact matching the committed
`benchmark.json` structure. The release validator includes a "benchmark
regeneration" check that verifies deterministic reproducibility.

### Benchmark Contract Design Decisions

- **iteration_index vs iteration in identity**: `iteration_index` (top-level
  integer) is the canonical iteration number for ordering and comparison;
  `benchmark_identity.iteration` mirrors it for self-contained identity.
- **source_refs covers all fixtures**: The benchmark references evals.json,
  report.json, baseline.json, runner-output-example.json, and
  runner-output-schema.json — the full set of static artifacts that define
  an iteration snapshot.
- **pass_rate mirrors report.json summary**: pass_rate fields (rate,
  eval_count, evals_passed/failed, assertions_total/passed/failed, status)
  are cross-validated against report.json and evals.json to prevent drift.
- **comparison_metadata comparison_mode "baseline"**: Pre-live-eval
  recordings use mode "baseline". Live iterations would use
  "with_skill" or "without_skill".
- **delta_placeholder**: A string field explaining that delta is populated
  during live comparison; keeps the schema self-documenting.
- **paired_benchmark_id**: Empty string in baseline mode. Links to the
  counterpart iteration's benchmark_id during with-skill vs without-skill
  comparison.

## Rollback

This change is docs and fixture only. Reverting the PR removes the
roadmap additions, benchmark fixture files, benchmark generator, and static
check additions. No runtime behavior, skill logic, or existing validation
coverage is affected.

## Non-Goals

- No working eval runner or evaluation engine.
- No LLM-based grading or assertion evaluation.
- No integration with Anthropic skill-creator plugin.
- No integration with Promptfoo or other external eval frameworks.
- No network dependencies or API calls.
- No automated iteration loop or convergence detection.
- No A/B blind evaluation workflow.
- No token efficiency or cost measurement.
- No private paths, credentials, overlays, or runtime state in public
  artifacts.

## Acceptance Criteria

| Criterion | Evidence |
| --- | --- |
| Eval schema draft is documented with assertion types | This document |
| Fixture directory with evals.json exists | `scripts/validation/eval-iteration-fixtures/` |
| Static validation checks pass | `validate-release.ps1` new check |
| Knowledge pattern documents the eval-driven iteration approach | `knowledge-hub/knowledge/patterns/eval-driven-skill-iteration.md` |
| Report artifact is deterministically reproducible | `validate-release.ps1` "eval report regeneration" check |
| Runner output contract schema is defined | `runner-output-schema.json` with JSON Schema draft 2020-12 |
| Runner output example conforms to schema | `runner-output-example.json` with static fixture data |
| Runner output contract is statically validated | `validate-release.ps1` "runner output contract" check |
| Runner output example is deterministically reproducible | `validate-release.ps1` "runner output regeneration" check |
| No runtime behavior change | Existing release checks pass alongside the new static fixture check |
| No private data in public artifacts | Fixture and docs are public-safe synthetic content |
