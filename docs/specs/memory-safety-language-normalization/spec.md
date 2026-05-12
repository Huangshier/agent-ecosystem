# Work Spec

- **Title**: Engineering Memory Safety And Language Normalization
- **Slug**: memory-safety-language-normalization
- **Status**: Active
- **Owner**: Maintainer + agent
- **Updated**: 2026-05-12

## 1. Summary

- Fix two engineering-memory safety bugs:
  - #29: project bootstrap refreshes must not silently overwrite
    project-specialized memory.
  - #31: memory upgrade normalization must respect the configured project
    memory language.
- Keep the fix focused on deterministic safety behavior and release-test
  coverage.

## 2. Current Context

- `skills/project-bootstrap/scripts/bootstrap_project.ps1` can overwrite
  existing scaffold files when `-OverwriteTemplates` and `-ProjectLanguage`
  are combined.
- `skills/project-bootstrap/scripts/set_project_language.ps1` can rewrite hot
  memory scaffolds when called with `-OverwriteScaffold`.
- `skills/project-bootstrap/scripts/memory_upgrade.ps1` currently writes
  English headings during `-Mode Apply`, regardless of `.agents/hub.lock.json`
  `project_language`.
- Public release validation already covers the baseline memory-upgrade flow but
  does not cover language-aware output or overwrite safety.

## 3. Goals

- Prevent silent replacement of existing project memory during bootstrap
  reinitialization or language refresh.
- Preserve existing memory content when it differs from templates unless the
  behavior is an explicit reset path.
- Back up any file before a bootstrap template refresh replaces it.
- Make `memory_upgrade.ps1 -Mode Apply` resolve the project language from
  `.agents/hub.lock.json` and write normalized hot memory in that language.
- Keep English behavior unchanged for English projects and missing language
  metadata.
- Provide an explicit fallback signal for unsupported language metadata.
- Add release validation fixtures for #29 and #31.

## 4. Non-Goals

- Do not implement the full conservative bilingual migration requested by #30.
- Do not externalize scaffold templates into separate files for #32.
- Do not redesign the CLI beyond the safety warnings needed for this fix.
- Do not change GitHub repository rulesets, App permissions, or release
  publishing workflow.

## 5. Constraints

- Public repository code, docs, specs, and memory remain English-first.
- Generated zh-CN project memory must use Simplified Chinese for headings and
  defaults.
- Tracked public files must not contain private paths, local mappings,
  runtime-only access material, or sensitive audit details.
- Existing public release validator behavior should remain deterministic across
  Windows PowerShell 5.1, PowerShell 7, Ubuntu, and macOS.

## 6. Assumptions

- `project_language` in `.agents/hub.lock.json` is the canonical language
  signal for memory upgrade normalization.
- Missing or `en` language metadata should keep the current English output.
- Unsupported language metadata should fall back to English while reporting the
  fallback in machine-readable output.
- Existing modified memory files should be preserved and marked for manual
  review rather than replaced during a normal refresh.

## 7. Risks

- Preserving modified memory during `-OverwriteTemplates` changes current
  refresh behavior for project memory files.
- Warning output must not corrupt JSON output used by scripts.
- Language-aware output can make tests brittle if assertions check too much
  prose instead of stable headings and spec references.

## 8. Proposed Approach

- Add safe bootstrap copy behavior:
  - detect existing project memory before template refresh;
  - preserve modified protected memory files and report them for manual review;
  - lazily create a backup directory before any template replacement.
- Limit language scaffold overwrites to new project initialization or explicitly
  safe paths, so existing project-specialized memory is not silently rewritten.
- Add a language resolver and localized default text to `memory_upgrade.ps1`.
- Extend `scripts/validate-release.ps1` with fixtures for:
  - protected memory preservation during bootstrap language refresh;
  - zh-CN memory upgrade normalization;
  - unsupported language fallback.

## 9. Acceptance / Evidence

- A project with customized root and `.agents` memory keeps those sections
  after bootstrap reinitialization with `-OverwriteTemplates -ProjectLanguage
  zh-CN`.
- Bootstrap output reports preserved or manual-review memory files when a
  modified protected file would otherwise be replaced.
- Bootstrap refresh writes a reviewable evidence report with preserved,
  replaced, skipped, manual-review, and backup groups.
- Any bootstrap template replacement of an existing file creates a backup
  first.
- `memory_upgrade.ps1 -Mode Apply` writes zh-CN headings/defaults for a project
  whose lock file has `project_language` set to `zh-CN`.
- English projects keep the current English normalized headings.
- Unsupported language metadata falls back to English and reports the fallback.
- Spec references found in old memory are preserved after upgrade.
- `git diff --check` passes.
- Local release validation passes.
- Hosted release validation passes on the PR before merge.

## 10. Loop Contract

- Not required; this work is bounded to two related safety bugs.

## 11. Execution Contract

- **Autonomy level**: bounded-autonomous
- **Phase list**:
  - P01: Create work package and point public memory at #29/#31.
  - P02: Implement bootstrap overwrite safety.
  - P03: Implement language-aware memory upgrade normalization.
  - P04: Add release validation fixtures.
  - P05: Validate locally, commit, push, and open PR.
  - P06: Wait for hosted checks and maintainer review.
- **Continue rule**: Continue while changes remain in project-bootstrap
  scripts, release validation fixtures, specs, docs, and tracked public memory.
- **Stop rule**: Stop for requested destructive resets of user memory,
  unsupported safety-sensitive data handling, repository setting changes, or a
  need to define full #30 migration semantics.
- **State record**:
  `docs/specs/memory-safety-language-normalization/tasks.md` and
  `.agents/plan.md`.

## 12. Open Questions

- Whether a later explicit reset flag should be added for maintainers who want
  to discard existing project memory and regenerate all scaffolds.
