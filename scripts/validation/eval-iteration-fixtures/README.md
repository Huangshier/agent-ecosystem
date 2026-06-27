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
```

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
