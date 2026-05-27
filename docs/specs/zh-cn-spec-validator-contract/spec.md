# Work Spec

- **Title**: zh-CN Spec Validator Contract
- **Slug**: zh-cn-spec-validator-contract
- **Status**: Done
- **Owner**: Codex + maintainer
- **Updated**: 2026-05-27

## 1. Summary
- Align the workflow-spec-lite spec validator with the actual zh-CN spec-lite template contract tracked in the repository.

## 2. Current Context
- Issue #94 reports that the zh-CN spec-lite template uses bilingual anchors such as `Title（标题）`, `Summary（摘要）`, and `Autonomy level（自主级别）`.
- `skills/workflow-spec-lite/scripts/validate_spec.ps1` currently recognizes exact English field labels such as `Title` and `Autonomy level`.
- Release validation has positive and negative fixtures for the validator, but its Chinese positive fixture does not mirror the actual bilingual zh-CN template anchors.

## 3. Goals
- Accept filled specs generated from the actual zh-CN `spec-lite.md` template.
- Keep required metadata fields, required sections, execution contract fields, and phase list validation strict.
- Extend release validation so bilingual zh-CN anchors are covered by a positive fixture.
- Keep negative fixtures rejecting missing required fields, sections, and execution contract fields.
- Confirm the knowledge-hub template and bundled project-bootstrap snapshot stay synchronized.

## 4. Non-Goals
- Do not modularize `scripts/validate-release.ps1`; that broader release validator refactor belongs to #96.
- Do not change unrelated project memory templates.
- Do not remove or weaken required fields, required sections, execution contract validation, phase list validation, or negative fixture checks.
- Do not publish a release, create a tag, merge the PR, or delete remote branches.

## 5. Constraints
- Public-facing implementation and durable spec text remain English-first.
- Scope is limited to validator, fixture, and template synchronization needed for #94.
- The validator should support localized display text appended to known structural anchors without treating arbitrary labels as valid required fields.
- Validation evidence must include `git diff --check`, focused zh-CN and English validator checks, focused negative checks, and full release validation.

## 6. Assumptions
- Parenthesized localized labels after canonical English anchors are the intended bilingual template shape.
- The zh-CN knowledge-hub template and project-bootstrap bundled snapshot should remain byte-for-byte equivalent for this spec-lite template.
- Existing English specs and fixtures should continue to pass without migration.

## 7. Risks
- A broad regex could accidentally accept malformed or unrelated labels.
- Fixture-only changes could miss drift in the actual zh-CN template.
- Full release validation may surface unrelated environmental failures; those must be recorded instead of silently skipped.

## 8. Proposed Approach
- Update validator field and section matching so canonical English aliases can be followed by localized parenthetical text.
- Keep section alias matching limited to the existing required section aliases and bilingual forms derived from them.
- Update release validation's zh-CN positive fixture to use the actual bilingual anchor style.
- Add negative fixture coverage for missing metadata and missing execution contract fields in addition to the existing required-section checks.
- Verify the two zh-CN template copies remain synchronized.

## 9. Acceptance / Evidence
- `git diff --check` passed.
- `powershell -NoProfile -ExecutionPolicy Bypass -File skills/workflow-spec-lite/scripts/validate_spec.ps1 -SpecPath docs/specs/zh-cn-spec-validator-contract/spec.md -RequireExecutionContract -FailOnError` passed.
- Focused `validate_spec.ps1 -RequireExecutionContract` checks passed for:
  - a filled English spec fixture.
  - a filled zh-CN bilingual spec fixture matching the actual template anchor style.
- Focused negative validator checks failed as expected for missing `Title`, missing goals, and missing `Autonomy level`.
- `scripts/validate-release.ps1` passed with `PASS=52 FAIL=0 WARN=0 DEFERRED=0`.
- The zh-CN spec-lite template in `knowledge-hub/templates/...` matches the project-bootstrap bundled snapshot (`SHA256 32BC05E05E1324C4C02E331DC766231208C873E7CD3425A5F9E193CFB5525A19`).
- A scoped PR was opened for #94: <https://github.com/Huangshier/agent-ecosystem/pull/105>.
- Validation evidence is recorded in this section and in the PR description.

## 10. Loop Contract
- Not applicable.

## 11. Execution Contract
- **Autonomy level**: bounded-autonomous
- **Phase list**:
  - P01: Confirm issue scope, repository baseline, and validator/template evidence. Completed.
  - P02: Implement scoped validator and release fixture updates. Completed.
  - P03: Run focused and full validation, then update this work package with evidence. Completed.
  - P04: Publish a scoped PR for #94 with validation evidence. Completed.
- **Continue rule**: Continue while changes remain inside #94 scope, validation failures are explainable and fixable, and no high-impact external action is required.
- **Stop rule**: Stop on scope drift into #96 modularization, unrelated template rewrites, weakened negative checks, unexplainable validation failures, merge/tag/release/branch-deletion needs, or permission blockers.
- **State record**: `docs/specs/zh-cn-spec-validator-contract/spec.md`, `docs/specs/zh-cn-spec-validator-contract/tasks.md`, and the scoped PR description.

## 12. Open Questions
- None currently blocking implementation.
