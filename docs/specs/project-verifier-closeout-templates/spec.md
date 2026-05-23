# Work Spec

- **Title**: Project Verifier And Closeout Templates
- **Slug**: project-verifier-closeout-templates
- **Status**: Done
- **Owner**: Codex + maintainer
- **Updated**: 2026-05-23

## 1. Summary
- Strengthen project-agent templates so generated project memory ties completion to explicit verifier evidence.
- Clarify that recurring monitors or automations should call documented command cards instead of embedding project-specific rules in scheduler prompts.
- Keep the change public-safe and generic: no private overlay paths, sensitive access material, local automation cadence, repository settings, or domain-specific workflows.

## 2. Current Context
- The public kernel already has a PR-ready / phase-close memory sync gate in project-agent templates.
- `.agents/commands/` is already the documented place for high-frequency project workflows.
- The current templates mention validation, but they do not yet make the verifier-or-explicit-unavailable-evidence rule prominent enough for all generated projects.
- Private control-plane workflows can define concrete schedules and access setup outside this public repository; public templates should only define reusable project behavior.

## 3. Goals
- Add verifier-driven completion guidance to the English and Simplified Chinese project-agent templates.
- Clarify that `.agents/commands/` command cards are the right place for repeatable monitor / automation tasks and that scheduler prompts should stay thin.
- Ensure the PR-ready / phase-close gate records verifier evidence and does not create repeated memory-only churn.
- Keep `knowledge-hub/templates/...` and `skills/project-bootstrap/assets/...` template mirrors aligned.

## 4. Non-Goals
- Do not add a scheduler, heartbeat, GitHub Actions workflow, repository hook, branch-protection rule, or settings change.
- Do not add private overlay details, local paths, sensitive access material, GitHub App setup material, or automation cadence.
- Do not add domain-specific command cards to public templates.
- Do not modify release publication, tags, rulesets, access settings, runners, or public `main` settings.

## 5. Constraints
- Public docs and English templates remain English-first.
- The zh-CN template may use Simplified Chinese narrative while preserving commands, paths, APIs, filenames, raw errors, and code symbols in original form.
- Template changes must be mirrored between the live `knowledge-hub` template tree and the bootstrap asset template tree.
- Validation must be deterministic and recorded before the work is claimed complete.

## 6. Assumptions
- A documentation/template-level guardrail is sufficient for this phase.
- Existing validation scripts can catch common template drift.

## 7. Risks
- Overly specific template language could leak private-control-plane practices into the public kernel.
- Adding too much text could make project startup guidance heavy.
- Mirror drift between template trees would make bootstrap output inconsistent.

## 8. Proposed Approach
- Add a concise "Verification And Completion" section to both project-agent templates.
- Extend command-card guidance to mention recurring monitor / automation workflows while keeping project rules in files, not scheduler prompts.
- Tighten the PR-ready / phase-close checklist so verifier evidence is part of the boundary update.
- Mirror the same content into the bootstrap asset template tree.

## 9. Acceptance / Evidence
- English and zh-CN project-agent templates include verifier-driven completion guidance.
- Both template trees contain the same English template text and the same zh-CN template text.
- The guidance keeps recurring automation generic and points to `.agents/commands/`.
- `git diff --check` passed.
- `validate_spec.ps1` passed for this spec.
- Release validation passed with `PASS=52 FAIL=0 WARN=0 DEFERRED=0`.

## 10. Loop Contract
- Not applicable.

## 11. Execution Contract
- **Autonomy level**: bounded-autonomous
- **Phase list**:
  - P01: Create this public-safe work package.
  - P02: Update live template tree.
  - P03: Mirror bootstrap asset templates.
  - P04: Validate and close out public engineering memory.
- **Continue rule**: Completed; changes stayed limited to public-safe templates, specs, validation, and local public memory.
- **Stop rule**: Completed without private detail leakage, scheduler implementation, settings/ruleset changes, release/tag changes, mirror drift, validation failure, scope drift, unrelated refactor pressure, skipped acceptance checks, or unresolved ambiguity.
- **State record**: `docs/specs/project-verifier-closeout-templates/tasks.md`.

## 12. Open Questions
- None for this bounded template change.
