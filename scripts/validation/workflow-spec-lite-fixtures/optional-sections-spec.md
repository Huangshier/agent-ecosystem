# Work Spec

- **Title**: Optional sections fixture
- **Slug**: optional-sections-fixture
- **Status**: Active
- **Owner**: release validation
- **Updated**: 2026-06-27

## 1. Summary
- Verify that the validator tolerates optional Requirements Clarification and Decision Validation sections without requiring them.

## 2. Current Context
- The spec-lite template now includes two optional sections that should not break existing validation.

## 3. Requirements Clarification
- **Questions asked**: Are optional sections expected to pass validation when absent?
- **Default assumptions made**: Yes, optional sections must not become required by presence in the template.
- **User confirmation status**: Confirmed by fixture design.
- **Pending clarification**: None.

## 4. Goals
- Confirm that a spec with optional sections filled passes validation.

## 5. Non-Goals
- Do not make optional sections required in the validator.

## 6. Constraints
- Fixture must include all required sections with meaningful content.

## 7. Assumptions
- The validator distinguishes required from optional sections.

## 8. Risks
- If optional section detection is misconfigured, all specs would need these sections.

## 9. Proposed Approach
- Run the validator against this fixture and confirm pass.

## 10. Acceptance / Evidence
- Validator returns pass=true with no findings for this fixture.

## 11. Decision Validation
- **Key assumptions and their risk**: Optional sections are purely opt-in; low risk.
- **Pre-mortem**: A future change could accidentally add these to the required list.
- **Reversibility**: Fully reversible by removing the sections from the template.
- **ADR**:
  - Context: Enhancing workflow-spec-lite with requirements clarification and decision validation.
  - Decision: Add as optional sections to keep backward compatibility.
  - Consequences: Existing specs without these sections continue to pass.

## 12. Loop Contract
- Not required for this fixture.

## 14. Open Questions
- None for this fixture.
