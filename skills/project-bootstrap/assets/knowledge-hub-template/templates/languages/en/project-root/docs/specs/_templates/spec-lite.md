# Work Spec

Project memory language: English.

- **Title**:
- **Slug**:
- **Status**: Draft / Active / Done / Archived
- **Owner**:
- **Updated**:

## 1. Summary
- What is being built, changed, or investigated?

## 2. Current Context
- Relevant code paths, binaries, documents, artifacts, or observed behavior
- Existing implementation facts already confirmed

## 3. Requirements Clarification
- Optional. Use when the goal, scope, constraints, acceptance criteria, or write authorization is not yet clear enough to proceed.
- **Questions asked**:
- **Default assumptions made**:
- **User confirmation status**:
- **Pending clarification**:

## 4. Goals
- Clear completion outcomes

## 5. Non-Goals
- Explicit boundaries for this work item

## 6. Constraints
- Environment, compatibility, tooling, time, safety, or interface constraints
- Scope control: do not include unrelated refactors, cleanup, or behavior changes unless they are explicit goals.

## 7. Assumptions
- Assumptions being made pending proof

## 8. Risks
- What may fail or require fallback

## 9. Proposed Approach
- Planned direction, implementation outline, or analysis method

## 10. Acceptance / Evidence
- How the result will be validated
- What proof or output should exist when done
- How skipped or unavailable acceptance checks will be recorded before claiming completion

## 11. Decision Validation
- Optional. Use for high-risk or hard-to-reverse decisions.
- **Key assumptions and their risk**:
- **Pre-mortem** (how this approach could fail):
- **Reversibility** (cost to undo, fallback options):
- **ADR** (Architecture Decision Record, for significant choices):
  - Context:
  - Decision:
  - Consequences:

## 12. Loop Contract
- Use only when execution must repeat until a variable or condition is satisfied.
- **Variable**:
- **Source of truth**:
- **Check command**:
- **Pass predicate**:
- **Iteration action**:
- **State record**:
- **Limits**:
- **Abort conditions**:

## 13. Execution Contract
- Use for multi-phase work where the agent should continue after each validated phase.
- **Autonomy level**: ask-before-each-phase / autonomous-until-blocked / bounded-autonomous
- **Phase list**:
  - P01:
  - P02:
  - P03:
- **Continue rule**:
- **Stop rule**: include scope drift, unrelated refactor pressure, skipped acceptance checks, safety/permission blockers, and unresolved ambiguity.
- **State record**:

## 14. Open Questions
- Unresolved issues that may block or reshape execution
