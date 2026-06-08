# Work Spec

- **Title**: Spec validator fixture
- **Slug**: spec-validator-fixture
- **Status**: Active
- **Owner**: release validation
- **Updated**: 2026-05-08

## 1. Summary
- Validate the workflow-spec-lite spec validator helper.

## 2. Current Context
- Release validation creates temporary positive and negative fixtures.

## 3. Goals
- Confirm complete specs pass.

## 4. Non-Goals
- Do not rewrite or normalize the target spec automatically.

## 5. Constraints
- Run only against temporary fixture files.

## 6. Assumptions
- Markdown headings follow the lightweight spec template.

## 7. Risks
- Missing acceptance or stop rules can let scope drift go unnoticed.

## 8. Proposed Approach
- Execute the validator and inspect structured findings.

## 9. Acceptance / Evidence
- Positive fixture passes and targeted negative fixtures fail.

## 10. Loop Contract
- Not required for this fixture.

## 11. Execution Contract
- Use for multi-phase work where the agent should continue after each validated phase.
- **Autonomy level**: bounded-autonomous
- **Phase list**:
  - P01: Run validator fixture checks.
- **Continue rule**: Continue only when fixture results match expectations.
- **Stop rule**: Stop when required goals, non-goals, risks, acceptance, or stop rule fields are missing.
- **State record**: release validation evidence.

## 12. Open Questions
- None for this fixture.
