# Test Strategy

Maturity: draft
Scope: cross-project
Source: manual
Last reviewed: 2026-06-26

## Summary

Choose a testing approach that matches the project's risk profile, team
workflow, and toolchain constraints. A useful test strategy balances coverage
ambition against maintenance cost and signals value early: fast unit tests catch
regressions during development, integration tests protect module boundaries,
and end-to-end tests guard critical user-visible flows.

## Use When

- A project needs a documented testing approach before investing in test
  infrastructure.
- The team or agent must decide which test levels (unit, integration, end-to-end)
  to prioritize.
- A spec's acceptance criteria should reference test evidence but the project
  has no testing conventions yet.
- Test coverage goals need to align with release confidence or deployment risk.

## Do Not Use When

- The project already has a well-documented testing strategy that covers its
  needs.
- The task is adding a single test case to an existing test suite with
  established conventions.
- The work is a throwaway prototype with no quality requirements.

## Steps

1. **Identify project constraints**: what test framework(s) are already in use
   or mandated? What CI system runs tests? What is the deployment risk model?
2. **Classify risk surfaces**: list the modules, interfaces, or flows where a
   defect would have the highest impact. Prioritize test coverage for these
   surfaces.
3. **Choose test levels**: decide which of unit, integration, contract, and
   end-to-end tests are appropriate. Most projects benefit from a wide base of
   unit tests, a moderate number of integration tests, and a narrow band of
   end-to-end or smoke tests.
4. **Define coverage targets**: set realistic targets per level. Aim for high
   coverage on critical-path code and lower coverage on glue or boilerplate.
   State whether coverage is measured by line, branch, or function.
5. **Document in project memory**: record the strategy in the project's
   `.agents/context/tech/testing-conventions.md` or equivalent. Include
   framework, commands, fixture patterns, and coverage expectations.
6. **Link to acceptance criteria**: when writing a spec, reference the test
   strategy in the acceptance section so that every work package knows what
   test evidence is expected.

## Validation

- The test strategy document names the framework, test levels, and coverage
  targets.
- Spec acceptance criteria can reference the strategy to decide what test
  evidence is required.
- The strategy is proportionate: lightweight projects are not burdened with
  enterprise-scale test mandates.
- The strategy does not mandate a specific framework across all projects;
  it records what the current project uses.
