# Work Spec

- **Title**: Loop contract fixture
- **Slug**: loop-contract-fixture
- **Status**: Active
- **Owner**: release validation
- **Updated**: 2026-05-08

## 1. Summary
- Validate that loop-oriented specs can pass the lightweight validator.

## 2. Current Context
- Release validation needs a positive fixture with a Loop Contract.

## 4. Goals
- Confirm loop specs pass when required sections are present.

## 5. Non-Goals
- Do not execute the loop action.

## 6. Constraints
- Run only against temporary fixture files.

## 7. Assumptions
- The loop contract is agent-facing state, not executable code.

## 8. Risks
- A vague loop can lead to unbounded repeated work.

## 9. Proposed Approach
- Validate a bounded Loop Contract fixture.

## 10. Acceptance / Evidence
- The Loop Contract fixture passes validation.

## 12. Loop Contract
- **Variable**: retry count
- **Source of truth**: temporary fixture text
- **Check command**: inspect fixture
- **Pass predicate**: retry count is below the limit
- **Iteration action**: no-op validation fixture
- **State record**: release validation evidence
- **Limits**: one validation attempt
- **Abort conditions**: missing required spec sections

## 13. Execution Contract

## 14. Open Questions
- None for this fixture.
