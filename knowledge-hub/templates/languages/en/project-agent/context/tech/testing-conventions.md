# Testing Conventions

## Summary

Record the project's testing framework, commands, environment requirements,
fixture patterns, coverage expectations, and manual verification steps. This
file is project-specific; fill it with the conventions actually used by the
current project.

## Keywords

test framework, test command, coverage, fixtures, CI test, manual verification

## Framework

Record the test framework(s) the project uses. Examples: pytest, Jest, go test,
cargo test, JUnit, Google Test, Catch2, Unity (C).

| Field | Value |
|-------|-------|
| Primary framework | *(fill in)* |
| Language / runtime | *(fill in)* |
| Config file | *(fill in)* |

## Test Commands

| Action | Command |
|--------|---------|
| Run all tests | *(fill in)* |
| Run a single test file | *(fill in)* |
| Run a single test case | *(fill in)* |
| Run with coverage | *(fill in)* |

## Environment

Record any environment variables, services, databases, hardware fixtures, or
external dependencies required before running the test suite.

- *(fill in, or write "none" if tests run with no special setup)*

## Fixtures and Test Data

Describe the project's fixture patterns:

- Where test fixtures live (directory, naming convention).
- How test data is generated or maintained.
- Whether tests use mocks, stubs, fakes, or real services.

*(fill in)*

## Coverage

| Metric | Target | Measurement method |
|--------|--------|--------------------|
| Line coverage | *(fill in or "not tracked")* | *(tool name)* |
| Branch coverage | *(fill in or "not tracked")* | *(tool name)* |

## Manual Verification

List any verification steps that require manual execution (e.g., flashing
firmware, connecting hardware, checking a browser UI):

- *(fill in, or write "none — all verification is automated")*

## CI Integration

Record how tests run in CI:

| CI system | Workflow / job name | Trigger |
|-----------|--------------------|---------| 
| *(fill in)* | *(fill in)* | *(fill in)* |

## Notes

- This template does not mandate any specific test framework.
- Fill in only the sections relevant to the current project.
- Update this file when the project's testing approach changes.
- If the project has no automated tests yet, record manual verification and the
  smallest useful next testability improvement instead of blocking unrelated
  work.
