# Work Spec

- **Title**: UTF-8 No-BOM Spec Validator Compatibility
- **Slug**: utf8-no-bom-spec-validator
- **Status**: Done
- **Owner**: Codex + maintainer
- **Updated**: 2026-05-28

## 1. Summary
- Make `skills/workflow-spec-lite/scripts/validate_spec.ps1` read spec files as explicit UTF-8 so valid zh-CN specs saved as UTF-8 without BOM validate consistently in Windows PowerShell 5.1 and PowerShell 7+.

## 2. Current Context
- Issue #106 reports that Windows PowerShell 5.1 can decode UTF-8 without BOM as the local ANSI code page when scripts use `Get-Content -Raw` without an explicit encoding.
- PR #105 fixed bilingual zh-CN anchor recognition for #94, but the validator still depends on shell-default file decoding.
- `scripts/validate-release.ps1` already exercises English, zh-CN bilingual positive fixtures, and negative fixtures for missing metadata, required sections, and execution-contract fields.

## 3. Goals
- Read spec text with explicit UTF-8 semantics in `validate_spec.ps1`.
- Add a focused release validator fixture that writes a zh-CN bilingual spec as UTF-8 without BOM and validates it through `validate_spec.ps1`.
- Preserve existing English and zh-CN bilingual positive fixture behavior.
- Preserve existing negative fixture behavior for missing metadata, required sections, and execution-contract fields.
- Open a scoped PR that fixes #106.

## 4. Non-Goals
- Do not reopen or expand #94.
- Do not modularize `scripts/validate-release.ps1`; that broader work belongs to #96.
- Do not change PowerShell helper ownership or helper layout for #97.
- Do not change release artifacts, tags, GitHub Actions, repository settings, secrets, or branch protection.
- Do not require specs to be saved with a UTF-8 BOM.

## 5. Constraints
- Keep the implementation small and limited to validator text reading plus focused fixture coverage.
- Use public-safe durable artifacts only; do not commit root `.agents/**`, private overlay state, local temp paths, sensitive access material, or private review evidence.
- The no-BOM fixture must be written with `.NET` `UTF8Encoding(false, true)` so the test data is actually UTF-8 without BOM.
- Validation evidence must distinguish Windows PowerShell 5.1 availability from PowerShell 7+ validation.

## 6. Assumptions
- Valid workflow specs in this repository are intended to be UTF-8 text files.
- Strict UTF-8 decoding is preferable to accepting locale-dependent ANSI decoding for validator input.
- The current release validator fixture block is the right place for focused regression coverage.

## 7. Risks
- A broad release validator rewrite could drift into #96 scope.
- Non-strict decoding could mask malformed input instead of proving the no-BOM compatibility fix.
- Encoding changes to PowerShell scripts themselves could break Windows PowerShell 5.1 script parsing if the BOM is lost.

## 8. Proposed Approach
- Add a small `Read-Utf8Text` helper in `validate_spec.ps1` that uses `System.Text.UTF8Encoding($false, $true)` and `System.IO.File.ReadAllText`.
- Replace the existing `Get-Content -Raw` validator read with the helper.
- In the spec-lite fixture section of `scripts/validate-release.ps1`, write a zh-CN bilingual fixture with `System.IO.File.WriteAllText` and strict UTF-8 no-BOM encoding, then validate it.
- Include the focused no-BOM fixture in spec-lite evidence without restructuring the release validator.

## 9. Acceptance / Evidence
- `git diff --check` passed.
- The active work spec passed `validate_spec.ps1 -RequireExecutionContract -FailOnError`.
- A focused UTF-8 without BOM zh-CN bilingual fixture was written with `System.Text.UTF8Encoding($false, $true)` and confirmed not to contain a BOM.
- The focused UTF-8 without BOM zh-CN fixture passed `validate_spec.ps1 -RequireExecutionContract -FailOnError` with Windows PowerShell 5.1 (`5.1.22621.2506`).
- The same focused fixture passed with PowerShell 7+ (`7.6.2`).
- `powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/validate-release.ps1 -ScratchRoot <scratch>` passed with `PASS=52 FAIL=0 WARN=0 DEFERRED=0`.
- Release validation's spec-lite fixture evidence covers complete English, zh-CN bilingual, and UTF-8 no-BOM zh-CN positive fixtures.
- Existing negative fixtures still reject missing metadata, required sections, and execution-contract fields.

## 10. Loop Contract
- Not applicable.

## 11. Execution Contract
- **Autonomy level**: bounded-autonomous
- **Phase list**:
  - P01: Confirm issue scope, repository baseline, and current validator fixture behavior. Completed.
  - P02: Implement the explicit UTF-8 read and no-BOM zh-CN fixture. Completed.
  - P03: Run focused Windows PowerShell 5.1, PowerShell 7+, diff, and release validation. Completed.
  - P04: Publish a scoped PR with validation evidence. Completed in the PR publication workflow.
- **Continue rule**: Continue while changes remain within #106 scope, validation failures are explainable and fixable, and no external release or repository administration action is required.
- **Stop rule**: Stop on scope drift into #94, #96, #97, release/tag/settings/access-control/branch-protection work, unrelated refactors, unexplainable validation failure, missing GitHub permission, or unavailable required validation that cannot be honestly reported.
- **State record**: This spec and the scoped PR description.

## 12. Open Questions
- None currently blocking implementation.
