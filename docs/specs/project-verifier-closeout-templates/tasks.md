# Task Plan

- **Spec**: `docs/specs/project-verifier-closeout-templates/spec.md`
- **Status**: Done
- **Updated**: 2026-05-23

## Tasks

- [x] T01: Create public-safe work package
  - Scope: `docs/specs/project-verifier-closeout-templates/`.
  - Validation: Spec and tasks describe goals, non-goals, acceptance, and execution stop rules.
  - Notes: This records public scope without private overlay details.

- [x] T02: Update live project-agent templates
  - Scope: `knowledge-hub/templates/languages/en/project-agent/AGENTS.md` and `knowledge-hub/templates/languages/zh-CN/project-agent/AGENTS.md`.
  - Validation: Templates include verifier-driven completion and recurring monitor command-card routing.
  - Notes: Added verifier-driven completion and recurring automation command-card routing.

- [x] T03: Mirror bootstrap asset templates
  - Scope: `skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/en/project-agent/AGENTS.md` and zh-CN equivalent.
  - Validation: Asset templates match the live templates for the changed sections.
  - Notes: Mirrored the same guidance in the bootstrap asset template tree.

- [x] T04: Validate
  - Scope: Public working tree.
  - Validation: `git diff --check` and release validation pass with `FAIL=0`.
  - Notes: `git diff --check` passed. Release validation passed with `PASS=52 FAIL=0 WARN=0 DEFERRED=0`.

- [x] T05: Close out public memory and commit
  - Scope: Public tracked spec/tasks and template files; root `.agents/` closeout notes are local untracked checkout memory only.
  - Validation: The public PR artifact excludes root `.agents/**`; final clean status is verified after the commit step.
  - Notes: Root `.agents/` may be refreshed locally for closeout, but it is not a public fact source and is not part of this PR.

## Task-to-Spec Notes
- T02 and T03 map to P02 and P03 in the execution contract.

## Conditional Loop Tasks
- Not applicable.

## Execution Contract Tasks

- [x] P01: Complete phase 1 and record validation
  - Goal: Create public-safe work package.
  - Inputs: Existing project-agent templates and private-control-plane boundary.
  - Outputs: Public spec/tasks.
  - Validation: Spec/tasks exist and keep private details out.
  - Continue / stop decision: Continue; public-safe work package exists and contains stop rules.

- [x] P02: Complete phase 2 and record validation
  - Goal: Update live template tree.
  - Inputs: Live en / zh-CN project-agent templates.
  - Outputs: Verifier and automation-routing guidance.
  - Validation: Changed sections are concise and generic.
  - Continue / stop decision: Continue; live template guidance is generic and public-safe.

- [x] P03: Complete phase 3 and record validation
  - Goal: Mirror bootstrap asset templates.
  - Inputs: Bootstrap asset en / zh-CN project-agent templates.
  - Outputs: Matching asset template text.
  - Validation: Live and asset templates match for changed sections.
  - Continue / stop decision: Continue; bootstrap asset templates were updated with matching guidance.

- [x] P04: Complete phase 4 and record validation
  - Goal: Validate and close out.
  - Inputs: Public diff.
  - Outputs: Validation evidence and ready-to-close public work package.
  - Validation: `git diff --check` passed; release validation passed with `PASS=52 FAIL=0 WARN=0 DEFERRED=0`.
  - Continue / stop decision: Continue to memory closeout and commit.
