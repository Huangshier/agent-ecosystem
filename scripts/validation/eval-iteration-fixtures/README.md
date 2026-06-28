# Eval Iteration Fixtures

Status: first slice (fixture shape only). Issue #166.

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
```

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

## Validation Boundary

The release validator performs only static checks:

- File existence and JSON parse validity.
- Required field presence and type checking.
- Assertion type enum validation.
- Eval count, assertion count, and eval ID validation.
- README token presence.

No skill execution, LLM calls, or eval runner invocation occurs.

## Non-Goals

- No working eval runner or evaluation engine.
- No LLM-based grading or assertion evaluation.
- No network dependencies or external service calls.
- No private paths, credentials, or runtime state.
- No integration with Anthropic skill-creator, Promptfoo, or
  external eval frameworks.
