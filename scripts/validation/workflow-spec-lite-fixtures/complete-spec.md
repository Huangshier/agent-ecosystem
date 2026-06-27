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

## 3. Requirements Clarification
- Optional section included to verify the validator tolerates optional sections.
- **Questions asked**: None; acceptance criteria were clear from the fixture scope.
- **Default assumptions made**: Fixture uses standard English headings.
- **User confirmation status**: Confirmed.
- **Pending clarification**: None.

## 4. Goals
- Confirm complete specs pass.

## 5. Non-Goals
- Do not rewrite or normalize the target spec automatically.

## 6. Constraints
- Run only against temporary fixture files.

## 7. Assumptions
- Markdown headings follow the lightweight spec template.

## 8. Risks
- Missing acceptance or stop rules can let scope drift go unnoticed.

## 9. Proposed Approach
- Execute the validator and inspect structured findings.

## 10. Acceptance / Evidence
- Positive fixture passes and targeted negative fixtures fail.

## 11. Decision Validation
- Optional section included to verify the validator tolerates optional sections.
- **Key assumptions and their risk**: Fixture structure matches template; low risk.
- **Pre-mortem**: Section renumbering could break regex-based negative fixtures.
- **Reversibility**: Low cost to undo; fixture files are scratch-only.
- **ADR**:
  - Context: Adding optional sections to spec template.
  - Decision: Include optional sections in positive fixture with content.
  - Consequences: Negative fixture regexes need updating to match new numbering.

## 12. Loop Contract
- Not required for this fixture.

## 13. Execution Contract
- Use for multi-phase work where the agent should continue after each validated phase.
- **Autonomy level**: bounded-autonomous
- **Phase list**:
  - P01: Run validator fixture checks.
- **Continue rule**: Continue only when fixture results match expectations.
- **Stop rule**: Stop when required goals, non-goals, risks, acceptance, or stop rule fields are missing.
- **State record**: release validation evidence.

## 14. Open Questions
- None for this fixture.
