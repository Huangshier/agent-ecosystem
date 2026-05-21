# Work Spec

- **Title**: Body-Level Memory Language Audit
- **Slug**: body-level-memory-language-audit
- **Status**: Active
- **Owner**: Codex
- **Updated**: 2026-05-21

## 1. Summary
- Implement issue #67 by adding a reusable, read-only project-memory language
  audit helper that checks narrative body language instead of accepting
  localized `Summary` / `Keywords` metadata as enough evidence.

## 2. Current Context
- Latest public `main` at implementation start is
  `dc53509bafb2a27a84906a57aef35df35833b9ed`.
- `project-bootstrap` owns conservative `en` / `zh-CN` memory language
  migration helpers.
- Existing migration validation checks proposal, backup, apply, validate, and
  narrative routing, but does not provide a standalone body-level audit helper.
- Issue #67 is accepted and requests a read-only heuristic helper with fixture
  coverage and concise findings.

## 3. Goals
- Add a reusable `project-bootstrap` helper for read-only body-level project
  memory language audits.
- Support `-ProjectDir`, `-ExpectedLanguage en|zh-CN`, and `-Json`.
- Support optional scan expansion for `docs/specs/**` and `.agents/commands/**`.
- Ignore discovery metadata, fenced code blocks, inline code, commands, paths,
  API names, filenames, raw error text, and code identifiers when judging body
  language.
- Report likely mismatches with paths, concise reasons, severity, and
  confidence.
- Add release validation fixture coverage for metadata/body mismatch,
  localized metadata in the opposite language, fenced code, protected literals,
  and mixed body text.
- Document the helper without implying automatic translation or memory rewrite.

## 4. Non-Goals
- Do not automatically translate or rewrite project memory.
- Do not claim perfect language identification.
- Do not require arbitrary project languages beyond the existing `en` and
  `zh-CN` project-memory policy.
- Do not change repository tags, releases, settings, rulesets, sensitive access
  configuration, or protected branch behavior.
- Do not implement issue #79 language migration workflow changes.

## 5. Constraints
- Public repository memory language is English for project memory.
- Root `.agents/` is local runtime memory and is not tracked.
- Private report content is read-only evidence; do not copy private local paths
  or sensitive state into public artifacts.
- The helper must be safe to run on an established project without mutating
  memory files.
- PowerShell scripts must remain Windows PowerShell 5.1-compatible.

## 6. Assumptions
- The helper belongs under `skills/project-bootstrap/scripts/` because it serves
  memory language migration and refresh workflows.
- Release validator scratch fixtures are sufficient fixture/smoke coverage for
  the initial implementation.
- A warning-level finding is the right default for heuristic mismatches.

## 7. Risks
- Heuristics may produce false positives on technical prose, so protected
  literal stripping and conservative thresholds are important.
- Too much integration into migration apply/validate could imply automatic
  rewrite semantics, which is outside #67.
- Adding large committed fixtures would increase maintenance weight; generated
  scratch fixtures keep the public tree lean.

## 8. Proposed Approach
- Add `skills/project-bootstrap/scripts/audit_memory_language.ps1`.
- Parse Markdown-like files by removing fenced code blocks and excluding
  `Summary` / `Keywords` sections before scoring narrative text.
- Strip inline code and common protected literal forms before counting CJK
  characters and Latin narrative words.
- Return human-readable warnings by default and structured JSON when requested.
- Add a release validator check that installs the runtime, creates a temporary
  fixture project, runs the helper with JSON, and asserts expected findings and
  non-findings.
- Update project-bootstrap and language policy documentation to reference the
  helper as read-only audit support.

## 9. Acceptance / Evidence
- Helper exists and is installed with the `project-bootstrap` skill.
- JSON and human-readable output include concise path-level findings.
- Scratch fixtures prove metadata-only localization is detected.
- Scratch fixtures prove body language, not metadata language, controls the
  result.
- Scratch fixtures prove fenced code blocks and protected literals do not
  trigger findings.
- Scratch fixtures prove mixed body language is reported without rewriting.
- Local validation:
  - `git diff --check` passed.
  - Helper-specific JSON and human-readable smoke commands passed.
  - `scripts/validate-release.ps1 -ScratchRoot "$env:TEMP\agent-ecosystem-issue-67-validation-skiplink-r2" -SkipLinkMode`
    passed with `PASS=50 FAIL=0 WARN=0 DEFERRED=0`.
  - `scripts/validate-release.ps1 -ScratchRoot "$env:TEMP\agent-ecosystem-issue-67-validation-full"`
    passed with `PASS=50 FAIL=0 WARN=0 DEFERRED=0`.
- Hosted PR release validation passes before merge recommendation.

## 10. Loop Contract
- Not applicable.

## 11. Execution Contract
- **Autonomy level**: bounded-autonomous
- **Phase list**:
  - P01: Create the spec/tasks and implement the helper.
  - P02: Add validator fixture coverage and docs references.
  - P03: Run local validation, commit, push, open PR, and wait for hosted
    checks.
- **Continue rule**: Continue while changes stay within #67 scope, no
  mutation semantics are added, and validation failures are understood and
  fixable.
- **Stop rule**: Stop for scope drift into #79, automatic translation or
  rewrite pressure, skipped acceptance checks, private data exposure, protected
  repository actions, merge requests, or unresolved safety ambiguity.
- **State record**: This spec and `tasks.md`; checkout-local `.agents` memory
  only when present.

## 12. Open Questions
- None.
