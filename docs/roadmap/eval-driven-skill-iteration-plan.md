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
7. README fixture documents the required tokens.

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
| No runtime behavior change | Existing release checks pass alongside the new static fixture check |
| No private data in public artifacts | Fixture and docs are public-safe synthetic content |
