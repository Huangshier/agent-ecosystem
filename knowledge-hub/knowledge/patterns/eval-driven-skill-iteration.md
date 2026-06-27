# Eval-Driven Skill Iteration

Maturity: draft
Scope: cross-project
Source: manual
Last reviewed: 2026-06-28

## Summary

Improve skills through a structured eval loop: define eval cases with
assertions, measure pass rate, compare against baseline, and iterate
until improvement plateaus. The eval suite is the quality contract for
each skill version.

## Use When

- A skill's output quality has degraded or plateaued after changes.
- Multiple candidate prompt rewrites exist and need objective comparison.
- A skill's acceptance criteria should include measurable output
  quality, not just trigger accuracy.
- The project needs to track skill improvement across versions.

## Do Not Use When

- The skill is a simple configuration or template with no meaningful
  output variation.
- The project has no mechanism to run eval cases (even manually).
- The cost of building an eval suite exceeds the value of the skill's
  output quality (throwaway or one-off skills).
- The task is adding documentation, fixtures, or metadata to a skill
  without changing its behavior.

## Steps

1. **Define eval cases**: for each skill, create an `evals.json` with
   representative input prompts and expected output characteristics.
   Cover happy path, edge cases, and known regression scenarios.
2. **Write assertions**: for each eval case, define assertions using
   the standardized types (skill_should_trigger,
   skill_should_not_trigger, output_contains, output_not_contains,
   output_exact_match, output_regex, output_token_count_below,
   output_file_created, output_file_not_created). Start with
   structural assertions before adding semantic ones.
3. **Establish baseline**: run the eval suite with the current skill
   version. Record `pass_rate` as the baseline. If running without
   the skill is feasible, record `pass_rate_without_skill` to measure
   delta value.
4. **Iterate**: modify the skill (prompt, script, or workflow), re-run
   the eval suite, and compare to baseline. Accept changes that improve
   `pass_rate` without regressing passing cases.
5. **Stop on plateau**: if two consecutive iterations produce no
   meaningful improvement (delta pass_rate below threshold), stop
   iterating and document the current quality level.
6. **Record version evidence**: store eval results alongside the skill
   version for auditability.

## Validation

- Every eval case has at least one assertion.
- Eval assertions use only defined assertion types.
- Baseline pass rate is recorded before any iteration.
- Each iteration's delta is measured and recorded.
- Stopping condition (plateau) is documented with evidence.
- No eval case depends on network access, external services, or
  private credentials.

## Assertion Types

| Type | What it checks |
| --- | --- |
| `skill_should_trigger` | Skill activates for the given input |
| `skill_should_not_trigger` | Skill must not activate for the input |
| `output_contains` | Skill output includes the expected substring |
| `output_not_contains` | Skill output excludes the expected substring |
| `output_exact_match` | Skill output equals expected value (trimmed) |
| `output_regex` | Skill output matches a regex pattern |
| `output_token_count_below` | Skill output token count is under threshold |
| `output_file_created` | A file at the expected path was created by the skill |
| `output_file_not_created` | No file at the expected path was created |

Future types: `llm_grade` (LLM-based quality grading with rubric),
`human_review` (flags for manual review).
