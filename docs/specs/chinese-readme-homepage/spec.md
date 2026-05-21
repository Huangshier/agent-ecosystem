# Work Spec

- **Title**: Chinese README Homepage
- **Slug**: chinese-readme-homepage
- **Status**: Done
- **Owner**: Codex
- **Updated**: 2026-05-21

## 1. Summary
- Implement issue #80 by making the root `README.md` the Simplified Chinese
  repository homepage while preserving an English entrypoint and legacy
  Chinese link compatibility.

## 2. Current Context
- Latest public main includes issue #78 at commit
  `16974dcf93dce12efcca95840a35b742b753aa8c`.
- Root `README.md` is currently English and links to `README.zh-CN.md`.
- `README.zh-CN.md` is currently the longer Simplified Chinese entrypoint.
- Release notes are individual files under `docs/releases/` without an index.
- `scripts/validate-release.ps1` asserts README and release-note structure.

## 3. Goals
- Make root `README.md` the Simplified Chinese homepage.
- Add `README.en.md` as the English entrypoint with matching structure.
- Keep `README.zh-CN.md` as a compatibility redirect to `README.md`.
- Add `docs/releases/README.md` as the release notes index.
- Update language policy and roadmap language guidance for the new homepage
  model.
- Update release validation assertions for the README files and release index.

## 4. Non-Goals
- Do not translate all deeper public documentation.
- Do not change installer profile behavior.
- Do not publish a new release, move tags, edit GitHub Releases, change
  repository settings, rulesets, secrets, or branch protection.
- Do not implement #56, #67, #79, or additional #78 follow-up work.

## 5. Constraints
- This is a single scoped PR for issue #80.
- Public docs below the top-level README may remain English-first unless a file
  explicitly targets another language.
- Commands, paths, APIs, filenames, code identifiers, and raw error text may
  stay in their original language.
- Do not add private overlay details, local machine paths, private auth
  material, generated runtime manifests, or local-only migration records.

## 6. Assumptions
- `v0.4.3` remains the current release for README positioning.
- The issue #80 scope authorizes the exception to the older English-first root
  README convention.
- The release notes index should link every existing release note from
  `v0.1.0` through `v0.4.3`.

## 7. Risks
- Existing validator checks may still expect English homepage content strings.
- The language-policy update can conflict with older docs that describe the
  former English-first homepage model.
- Over-expanding the README can make the homepage less useful as a quick entry.

## 8. Proposed Approach
- Replace root `README.md` with a concise Simplified Chinese homepage that
  explains positioning, fit, non-fit, workflow, first-success path, layers,
  profiles, examples, and navigation.
- Add `README.en.md` as the English mirror.
- Reduce `README.zh-CN.md` to a compatibility page.
- Add a release notes index and point README navigation to it instead of
  listing every release on the homepage.
- Update language policy, roadmap, and release validator expectations.

## 9. Acceptance / Evidence
- `README.md`, `README.en.md`, and `README.zh-CN.md` link to each other as
  intended.
- `docs/releases/README.md` links all release notes from `v0.1.0` through
  `v0.4.3`.
- `scripts/validate-release.ps1` requires and validates the new files.
- Local validation completed on 2026-05-21:
  - `git diff --check` passed.
  - `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\validate-release.ps1 -ScratchRoot "$env:TEMP\agent-ecosystem-issue-80-validation-final"` passed with `PASS=49 FAIL=0 WARN=0 DEFERRED=0`.

## 10. Loop Contract
- Not applicable.

## 11. Execution Contract
- **Autonomy level**: bounded-autonomous
- **Phase list**:
  - P01: Update README and language-policy documentation.
  - P02: Update release index and validator assertions.
  - P03: Run local validation and prepare the scoped PR handoff.
- **Continue rule**: Continue while changes stay inside #80 scope and
  validation has no unresolved failure.
- **Stop rule**: Stop for scope drift, requested merge/main/tag/release/settings
  changes, secrets or private data exposure, skipped acceptance checks, or
  unresolved ambiguity.
- **State record**: This spec and local untracked `.agents/` memory when
  present.

## 12. Open Questions
- None.
