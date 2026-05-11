# Work Spec

- **Title**: Minimal Project Adoption Walkthrough
- **Slug**: minimal-project-adoption-walkthrough
- **Status**: Active
- **Owner**: Maintainer + agent
- **Updated**: 2026-05-11

## 1. Summary

- Add a continuous public walkthrough that starts from an empty project and
  shows how to adopt the Workflow Kernel without copying private workflow
  details.
- The walkthrough should connect install, project bootstrap, context gate,
  spec-lite, memory governance, knowledge hub routing, validation, and cleanup.

## 2. Current Context

- GitHub issue #22 is accepted and requests an end-to-end minimal project
  adoption walkthrough.
- Existing adoption surfaces:
  - `README.md`
  - `README.zh-CN.md`
  - `docs/how-to-adapt.md`
  - `examples/minimal-project/README.md`
- Existing example project files illustrate layout, but do not provide a
  continuous user journey from an empty project.
- Public repository governance is active:
  - GitHub App identity: `agent-ecosystem-bot`
  - Ruleset: `protect-main`
  - Required validation: release validation checks before merge

## 3. Goals

- Create a public walkthrough under `docs/walkthroughs/`.
- Start from an empty project and use placeholders instead of local paths.
- Cover install, bootstrap, context gate, spec-lite, memory governance,
  knowledge hub routing, validation, and cleanup.
- Link the walkthrough from public entrypoints where a new adopter would look.
- Refresh public `.agents` memory to show #22 as the active maintenance item.

## 4. Non-Goals

- Do not add Bash/Zsh wrappers.
- Do not add new runtime features or change installer behavior.
- Do not publish private workflow, private overlay mappings, or local machine
  paths.
- Do not expand the GitHub App permission model.
- Do not resolve #27 validation-tier policy as part of this walkthrough.

## 5. Constraints

- Public docs are English-first.
- The project is PowerShell-first across Windows, Linux, and macOS; non-Windows
  users should use PowerShell 7+ via `pwsh -NoProfile -File`.
- Documentation must not imply Agent Ecosystem is an agent runtime, scheduler,
  or universal workflow.
- Public `.agents` files must avoid private mappings, local paths, and sensitive
  audit details.
- Scope control: avoid unrelated cleanup beyond the links and memory updates
  needed for #22.

## 6. Assumptions

- The existing `recommended` profile is the right default for the walkthrough.
- The walkthrough can reference the public example project as a companion, not
  as the primary path.
- Full local release validation is appropriate because the change adds a new
  public adoption surface and updates tracked agent memory.

## 7. Risks

- The walkthrough could duplicate `docs/how-to-adapt.md` instead of providing a
  more concrete path.
- Commands could become too machine-specific if placeholders are not used
  carefully.
- The doc could overstate automation maturity if it makes the GitHub App or
  governance model part of normal adopter setup.

## 8. Proposed Approach

- Add `docs/walkthroughs/minimal-project-adoption.md`.
- Add `docs/walkthroughs/README.md` if needed to provide a stable section
  entrypoint.
- Link the walkthrough from `README.md`, `README.zh-CN.md`,
  `docs/how-to-adapt.md`, and `examples/README.md` where useful.
- Update public `.agents/process.txt`, `.agents/plan.md`, and `.agents/notes.md`
  for #22 / PR #26 state.
- Validate with `git diff --check` and full release validation.

## 9. Acceptance / Evidence

- `docs/walkthroughs/minimal-project-adoption.md` exists.
- The walkthrough covers:
  - install a temporary or recommended runtime;
  - bootstrap an empty project;
  - inspect `.agents` and `docs/specs`;
  - run context gate;
  - create a minimal spec-lite work package;
  - run memory-governance checks;
  - consult or route knowledge hub entries;
  - validate and clean up generated runtime/project artifacts.
- Public entrypoints link to the walkthrough.
- `git diff --check` passes.
- `scripts/validate-release.ps1` passes locally.
- Hosted release validation passes on the PR before merge.

## 10. Loop Contract

- Not required for this documentation-only walkthrough task.

## 11. Execution Contract

- **Autonomy level**: bounded-autonomous
- **Phase list**:
  - P01: Draft spec/tasks and point public memory at #22.
  - P02: Implement walkthrough and entrypoint links.
  - P03: Validate locally, commit, push, and open PR.
  - P04: Wait for hosted checks and maintainer review.
- **Continue rule**: Continue while changes remain documentation/memory-only,
  validation is available, and no private or sensitive details are introduced.
- **Stop rule**: Stop for scope drift, unrelated refactor pressure, skipped
  acceptance checks, permission or ruleset blockers, or unresolved ambiguity
  about public/private boundaries.
- **State record**: `docs/specs/minimal-project-adoption-walkthrough/tasks.md`
  and `.agents/plan.md`.

## 12. Open Questions

- Whether #27 validation-tier policy should later reference this walkthrough as
  an example of high-confidence documentation validation.
