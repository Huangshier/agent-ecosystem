# Eval-Driven Skill Iteration Plan

Status: first slice (docs + fixture only). Issue #166.

This plan defines the eval-driven skill iteration mechanism for
agent-ecosystem. The first slice establishes the public-safe design
boundary, eval schema draft, fixture shape, and non-goals. It does not
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
| `contains` | Output contains the expected substring | `"expected": "## Summary"` |
| `not_contains` | Output must not contain the substring | `"expected": "private key"` |
| `exact_match` | Output equals expected string after trimming | `"expected": "PASS"` |
| `regex` | Output matches the expected regex pattern | `"expected": "Status: (draft\|verified)"` |
| `token_count_below` | Output token count is below threshold | `"expected": "500"` |
| `file_created` | A file at the expected path was created | `"expected": "docs/specs/foo/spec.md"` |
| `file_not_created` | No file at the expected path was created | `"expected": ".agents/_scratch/"` |

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
      "enum": ["contains", "not_contains", "exact_match", "regex", "token_count_below", "file_created", "file_not_created"]
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
7. README fixture documents the required tokens.

No eval runner is invoked. No skill output is generated. No LLM calls
are made.

## Fixture Location

```
scripts/validation/eval-iteration-fixtures/
  README.md
  evals-schema-fixture/
    evals.json
    expected.json
```

## Rollback

This change is docs and fixture only. Reverting the PR removes the
roadmap document, knowledge pattern, fixture files, and static check
addition. No runtime behavior, skill logic, or existing validation
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
| No runtime behavior change | Existing 62 checks pass unchanged |
| No private data in public artifacts | Fixture and docs are public-safe synthetic content |
