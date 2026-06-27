# Eval Iteration Fixtures

Status: first slice (fixture shape only). Issue #166.

These fixtures validate the static structure of eval case definitions.
They do not invoke an eval runner, generate skill output, or call any
LLM. The fixtures verify that evals.json files conform to the expected
schema shape and contain required fields.

## Fixture Structure

```
eval-iteration-fixtures/
  README.md           (this file)
  evals-schema-fixture/
    evals.json        (synthetic eval suite)
    expected.json     (validation expectations)
```

## Evals Schema Fixture

`evals-schema-fixture/evals.json` is a synthetic eval suite that
demonstrates the eval case structure. It uses a fictional "example-skill"
with two eval cases covering happy-path and edge-case scenarios.

`evals-schema-fixture/expected.json` defines the static validation
expectations:

- The JSON must parse without error.
- Top-level fields `skill`, `version`, and `evals` must exist.
- Each eval case must have `id`, `input`, and `assertions`.
- Each assertion must have `type` and `expected`.
- All assertion `type` values must be from the defined enum.

## Validation Boundary

The release validator performs only static checks:

- File existence and JSON parse validity.
- Required field presence and type checking.
- Assertion type enum validation.
- README token presence.

No skill execution, LLM calls, or eval runner invocation occurs.

## Non-Goals

- No working eval runner or evaluation engine.
- No LLM-based grading or assertion evaluation.
- No network dependencies or external service calls.
- No private paths, credentials, or runtime state.
