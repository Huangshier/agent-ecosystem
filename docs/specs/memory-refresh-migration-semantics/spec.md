# Work Spec

- **Title**: Memory Refresh, Migration, And Reset Semantics
- **Slug**: memory-refresh-migration-semantics
- **Status**: Done
- **Owner**: Codex
- **Updated**: 2026-05-22

## 1. Summary
- Refs #79 by clarifying guidance and trigger semantics for project-memory
  refresh/upgrade, language migration, and reset/reinitialize requests.
- Keep this PR limited to documentation, skill discovery, and project template
  guidance.

## 2. Current Context
- Latest public `main` at implementation start is `df20869`.
- #78, #80, #56, and #67 are already on `main`.
- `project-bootstrap` already has safe refresh, backup-first reset,
  conservative `en` / `zh-CN` migration, narrative proposal, and read-only
  body-language audit helpers.
- The remaining #79-A gap is user-intent clarity: agents should not confuse a
  refresh with reset, and should not treat language migration as ordinary bulk
  file edits.

## 3. Goals
- Distinguish refresh/upgrade, language migration, and reset/reinitialize in
  public guidance.
- Add English and Chinese trigger terms to relevant skill descriptions.
- Tell memory-governance and project-context-gate to route these requests
  through project-bootstrap's proposal-first and backup-first flows.
- Update project AGENTS templates and mirrored runtime snapshots.
- Add user-copyable prompt examples for safe refresh, language migration, and
  explicit reset.

## 4. Non-Goals
- Do not implement #79-B workflow or validation behavior changes.
- Do not close #79.
- Do not change migration scripts, release tags, releases, repository settings,
  rulesets, secrets, or branch protection.
- Do not introduce automatic unattended translation claims.
- Do not change `full` or `dev` profile install behavior.

## 5. Constraints
- Public repository project memory language is English.
- `README.md` remains the Simplified Chinese homepage; deeper public docs may
  remain English-first.
- Keep commands, paths, APIs, filenames, raw errors, and code symbols in their
  original form in migration guidance.
- Private report content is read-only evidence and must not be copied as local
  path or private-state detail into public artifacts.

## 6. Assumptions
- The existing script behavior already supports the distinction being
  documented here.
- Release validation should pass without new validator assertions because this
  PR changes guidance, not behavior.

## 7. Risks
- Overstating migration semantics could imply perfect automatic translation.
- Missing one template mirror could leave installed runtime guidance different
  from source hub guidance.
- Wording in Chinese trigger terms must stay clear that reset requires explicit
  discard permission.

## 8. Proposed Approach
- Patch `project-bootstrap`, `memory-governance`, and `project-context-gate`
  skill guidance.
- Patch source templates under `knowledge-hub/templates/languages/**` and the
  bundled snapshot under `skills/project-bootstrap/assets/**`.
- Patch `docs/existing-project-upgrade.md`, `docs/language-policy.md`, and
  README navigation links.
- Run diff and release validation, then publish a PR with `Refs #79`.

## 9. Acceptance / Evidence
- Skill descriptions include refresh, upgrade, language migration, and Chinese
  trigger terms.
- Guidance explicitly says refresh/upgrade preserves project-specific memory by
  default.
- Guidance explicitly says language migration means template replacement plus
  reviewed target-language narrative while preserving protected literals.
- Guidance explicitly says reset/reinitialize requires user permission to
  discard old memory.
- Source project templates and bundled snapshot templates are aligned.
- `git diff --check` passes.
- `scripts/validate-release.ps1` passes.
- PR body uses `Refs #79` and does not claim #79 is complete.

Current evidence:
- `git diff --cached --check` passed.
- A fresh scratch release validation run passed with
  `PASS=50 FAIL=0 WARN=0 DEFERRED=0`.

## 10. Loop Contract
- Not applicable.

## 11. Execution Contract
- **Autonomy level**: bounded-autonomous
- **Phase list**:
  - P01: Load context, create branch and work package.
  - P02: Update skill, template, and public docs guidance.
  - P03: Validate locally and prepare a PR handoff.
- **Continue rule**: Continue while changes stay guidance-only and validation
  failures are understood and fixable.
- **Stop rule**: Stop for script behavior changes, reset/destructive behavior
  changes, direct main pushes, protected repo setting changes, private data
  exposure, claims that #79 is complete, or skipped acceptance checks.
- **State record**: This spec and `tasks.md`; PR publication and hosted-check
  state belong in PR metadata rather than durable specs.

## 12. Open Questions
- None.
