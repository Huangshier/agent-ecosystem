# Work Spec

- **Title**: Agents Template Startup Guidance
- **Slug**: `agents-template-startup-guidance`
- **Status**: Active
- **Owner**: Agent
- **Updated**: 2026-05-13

## 1. Summary
- Implement issue #44 by tightening the base project-bootstrap AGENTS templates and related mirrored guidance so generated projects encourage lean startup context, documented project commands, PR-ready memory sync, and reviewable planning for large issues.

## 2. Current Context
- Accepted issue: https://github.com/Huangshier/agent-ecosystem/issues/44
- Relevant paths:
  - `skills/project-bootstrap/templates/project-memory/en/project-root/AGENTS.md`
  - `skills/project-bootstrap/templates/project-memory/en/project-agent/AGENTS.md`
  - `skills/project-bootstrap/templates/project-memory/en/project-agent/commands/README.md`
  - `skills/project-bootstrap/templates/project-memory/zh-CN/project-root/AGENTS.md`
  - `skills/project-bootstrap/templates/project-memory/zh-CN/project-agent/AGENTS.md`
  - `skills/project-bootstrap/templates/project-memory/zh-CN/project-agent/commands/README.md`
  - `knowledge-hub/templates/project-root/AGENTS.md`
  - `knowledge-hub/templates/project-agent/AGENTS.md`
  - `knowledge-hub/templates/project-agent/commands/README.md`
  - `skills/project-bootstrap/assets/knowledge-hub-template/templates/project-root/AGENTS.md`
  - `skills/project-bootstrap/assets/knowledge-hub-template/templates/project-agent/AGENTS.md`
  - `skills/project-bootstrap/assets/knowledge-hub-template/templates/project-agent/commands/README.md`
  - `.agents/commands/README.md`
  - release validation scripts under `scripts/`
- Public `.agents/AGENTS.md` already contains the PR-ready / phase-close memory sync gate, but the base project-bootstrap templates do not yet carry equivalent guidance.

## 3. Goals
- Keep root `AGENTS.md` templates lightweight and cross-agent compatible.
- Change root startup read order so agents read hot memory first and discover context through `.agents/context/README.md` plus matching entries, not the whole `.agents/context/` tree.
- Add concise Project Commands guidance that links `.agents/AGENTS.md` to `.agents/commands/README.md`.
- Add PR-ready memory sync guidance to project-bootstrap base templates, including no post-PR memory-only commits solely for state or hosted-check timestamp churn unless explicitly approved.
- Add large issue guidance: create an implementation plan and, when helpful, split into reviewable PR phases before editing.
- Keep en, zh-CN, and necessary mirrored template copies aligned.
- Add or update release validation coverage for the new template requirements.

## 4. Non-Goals
- Do not implement issue #30 language migration.
- Do not add tool-specific instruction files such as `CLAUDE.md`, `GEMINI.md`, or `.clinerules`.
- Do not rewrite the entire `.agents/AGENTS.md`; make targeted additions only.
- Do not change release versioning.
- Do not change repository rulesets, branch protection, hooks, runners, GitHub App auth, main protection, or repository settings.

## 5. Constraints
- Public engineering memory is English-first.
- Project memory changes must avoid private overlay details, local paths, sensitive audit findings, and automation auth material.
- Keep this as workflow guidance and validation coverage, not enforcement through hooks or repository settings.
- Scope control: do not include unrelated refactors, cleanup, or behavior changes.

## 6. Assumptions
- Mirrored knowledge-hub template copies should remain aligned with project-bootstrap base templates where the same generated project memory surface exists.
- Release validation should check for durable guidance markers rather than exact prose duplication.

## 7. Risks
- Overly broad validation could make future wording changes brittle.
- Missing a mirrored copy could leave generated scaffolds inconsistent.
- Adding too much text to always-loaded AGENTS templates could weaken the lean startup goal.

## 8. Proposed Approach
- Inspect template mirrors and existing validation scripts.
- Patch only targeted sections in root AGENTS, project-agent AGENTS, and commands README templates.
- Add validation assertions that require progressive context wording, project commands guidance, PR-ready memory sync guidance, and large-issue planning guidance in the relevant templates.
- Run diff and release validation.
- Before PR creation, run the PR-ready / phase-close memory sync gate and update this spec, `.agents/plan.md`, and `.agents/process.txt` as needed.

## 9. Acceptance / Evidence
- Template changes exist for both `en` and `zh-CN` project-bootstrap project-memory templates.
- Necessary mirrored knowledge-hub template copies are aligned.
- `.agents/commands/README.md` and `.agents/AGENTS.md` are connected through Project Commands guidance.
- Validation covers the new template guidance requirements.
- `git diff --check` passed on 2026-05-13.
- `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-release.ps1` passed on 2026-05-13 with `PASS=39 FAIL=0 WARN=0 DEFERRED=0`.
- Implementation is PR-ready pending commit, push, and PR creation.

## 10. Loop Contract
- Not applicable.

## 11. Execution Contract
- **Autonomy level**: autonomous-until-blocked
- **Phase list**:
  - P01: Create work package and inventory template/validation surfaces.
  - P02: Implement targeted template and mirrored documentation changes.
  - P03: Add or update validation coverage and run local validation.
  - P04: Complete PR-ready public engineering memory sync, commit, push, and open PR if validation passes.
- **Continue rule**: Continue to the next phase when scope remains within #44, the working tree changes are understood, and validation for the current phase is available or explicitly recorded.
- **Stop rule**: Stop for scope drift into #30, tool-specific instruction files, release versioning, repository settings, hooks/rulesets/runners/auth/main protection changes, skipped acceptance checks without explanation, destructive git operations, or unresolved ambiguity.
- **State record**: `docs/specs/agents-template-startup-guidance/tasks.md` and `.agents/plan.md`.

## 12. Open Questions
- None blocking.
