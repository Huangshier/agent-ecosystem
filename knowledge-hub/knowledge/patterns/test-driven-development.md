# Test-Driven Development

Maturity: draft
Scope: cross-project
Source: manual
Last reviewed: 2026-06-26

## Summary

Write a failing test before writing the implementation code. This practice
ensures every piece of behavior has a corresponding test, keeps implementation
focused on the intended outcome, and produces a regression guard at the same
time as the feature. TDD works best for logic with clear inputs and outputs;
it is less suited to exploratory UI work or configuration-only changes.

## Use When

- The desired behavior can be specified as observable inputs and outputs before
  implementation begins.
- The code under test has deterministic behavior (no hardware state, no
  nondeterministic timing, no external service uncertainty that cannot be
  mocked).
- Refactoring is planned: existing tests provide the safety net.
- The team or project conventions call for test-first or test-alongside
  development.

## Do Not Use When

- The task is a configuration change, documentation update, or template edit
  with no testable logic.
- The environment makes testing unreliable (flaky hardware, unstable external
  dependencies without mocks).
- The cost of writing tests first exceeds the value for throwaway prototypes
  or one-off scripts.
- The project has no test framework installed and setting one up is out of
  scope for the current work.

## Steps

1. **Write a failing test**: express the smallest meaningful behavior as a
   test case. Run it and confirm it fails for the expected reason.
2. **Write the minimum implementation**: make the test pass with the simplest
   correct code. Do not add extra behavior.
3. **Refactor if needed**: clean up duplication or naming while keeping the
   test green. Run the full test suite to confirm no regressions.
4. **Repeat**: for each additional behavior, return to step 1.
5. **Record test evidence**: note the test command, pass/fail status, and
   coverage delta in the project's test workflow command card or spec
   acceptance evidence.

## Validation

- Every implemented behavior has at least one test that was written before
  or alongside the implementation.
- Tests are deterministic: they pass consistently and fail for the expected
  reason when behavior is broken.
- The test suite runs in a reasonable time relative to the project size.
- Test evidence is recorded in spec acceptance criteria or project memory
  when the workflow calls for it.
