# Work Spec

- **Title**: Local Root Agents Runtime State
- **Slug**: local-root-agents-runtime-state
- **Status**: Done
- **Owner**: Codex
- **Updated**: 2026-05-21

## 1. Summary
- Implement issue #78 by localizing root `.agents/` runtime memory and keeping
  public status records durable.
- Preserve project-bootstrap support for generated `.agents/` memory in
  temporary projects, examples, templates, and fixtures.

## 2. Implementation-Start Context
- Issue #78 is accepted for implementation.
- Root `.agents/` files were tracked in the public repository and contained
  stale checkout-local state.
- Root `AGENTS.md` pointed clean clones toward `.agents/AGENTS.md` as the
  primary guide.
- `docs/specs/post-v0-4-3-flow-guardrails/` recorded stale completion
  state after PR #77 landed.

## 3. Goals
- Stop tracking root `.agents/` without deleting local files.
- Add a root-anchored ignore rule for checkout-local `.agents/`.
- Update root fallback guidance for clean clones.
- Move reusable root `.agents/context/experience/` content into curated public
  knowledge.
- Close stale post-v0.4.3 flow records with durable evidence.
- Update release validation to prevent tracked root `.agents/` files and to
  check public spec status boundaries.

## 4. Non-Goals
- Do not remove the `.agents` runtime memory concept.
- Do not change project-bootstrap `.agents` generation behavior.
- Do not block `.agents` paths in examples, templates, fixtures, scratch
  projects, or documentation.
- Do not implement #56, #67, #79, or #80.
- Do not change installer profiles, tags, releases, repository settings,
  rulesets, protected configuration, or branch protection.

## 5. Constraints
- Public repository memory and durable work packages are English-first.
- Private audit notes and local machine paths stay outside the public repo.
- Public specs may retain historical completion evidence, stop rules, and
  retrospectives, but must not become a long-lived local checkout dashboard.
- Validation changes must keep project-bootstrap runtime smoke coverage.

## 6. Assumptions
- The accepted issue body is the public scope contract for #78.
- Existing historical spec references may need a narrow validator allowlist.
- Root `.agents` files should remain on the maintainer machine after index
  removal.

## 7. Risks
- Validator changes can accidentally reject legitimate examples, templates, or
  temporary project output.
- Overbroad ignore rules can hide fixture or template `.agents` paths.
- Migrating root memory content could leak checkout-local paths if copied
  without review.

## 8. Proposed Approach
- Update root guidance and `docs/specs` rules before removing tracked memory.
- Promote only the reusable stacked-PR recovery lesson to public knowledge.
- Remove root `.agents/` from the Git index using a root-scoped ignore rule.
- Replace validator assumptions about tracked root `.agents` with checks
  against templates and scratch project output.
- Add a lightweight spec-state boundary check with an explicit historical
  allowlist.

## 9. Acceptance / Evidence
- `git ls-files .agents` returns no files.
- `.gitignore` contains `/.agents/`.
- Root `AGENTS.md` works as the clean-clone fallback.
- `docs/specs/post-v0-4-3-flow-guardrails/` is marked done.
- Release validation passes and continues to verify generated `.agents` memory
  in temporary projects.
- No tags, releases, settings, rulesets, protected configuration, or protected
  branches are changed.

## 10. Loop Contract
- Not applicable.

## 11. Execution Contract
- **Autonomy level**: bounded-autonomous
- **Phase list**:
  - P01: Update documentation and migrate durable memory.
  - P02: Remove root `.agents/` from tracking.
  - P03: Update validator checks.
  - P04: Run local validation and prepare a scoped PR handoff.
- **Continue rule**: Completed while changes remained inside issue #78 scope
  and local validation passed.
- **Stop rule**: Completed without repository settings changes, tag or release
  changes, protected configuration exposure, destructive local deletion, direct
  default-branch push, unrelated issue implementation, or unresolved validation
  failure.
- **State record**: `docs/specs/local-root-agents-runtime-state/tasks.md`.

## 12. Open Questions
- None.
