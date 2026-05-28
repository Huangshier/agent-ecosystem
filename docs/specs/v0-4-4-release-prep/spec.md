# Work Spec

- **Title**: v0.4.4 Release Prep And Finalization Guardrail
- **Slug**: v0-4-4-release-prep
- **Status**: Done
- **Owner**: Codex
- **Updated**: 2026-05-22

## 1. Summary

- Prepared a public-safe `v0.4.4` release candidate as a stabilization / docs /
  governance patch release.
- Produced bilingual release notes for the GitHub Release page.
- Correct the post-publication metadata after `v0.4.4` was tagged and
  published.
- Added a small publish-ready alignment guardrail so maintainer authorization to
  publish requires final metadata alignment before tag or GitHub Release
  creation.
- Keep #23 as a next-version release-planning umbrella. This work references
  #23 for release-planning context but does not implement or close it.

## 2. Current Context

- Latest published public release: `v0.4.4`.
- Post-`v0.4.3` public changes are primarily stabilization, documentation,
  release hygiene, workflow guardrails, project-memory language governance, and
  public/private boundary cleanup.
- `v0.4.4` was published at tag target
  `71fabb372a4cbc024f07c920a0c17b903a77afc2`, but the release-preparation
  metadata left README and release docs on pre-publication wording.
- Public root `.agents/` is checkout-local runtime memory and is not a public
  fact source.

## 3. Goals

- Added a `v0.4.4` release notes draft with clear `中文` and `English` sections.
- Updated `CHANGELOG.md`, release notes index, release readiness, and release
  process coverage for the release candidate.
- Added validator coverage for the `v0.4.4` release-prep notes.
- Updated `README.md`, `README.en.md`, `docs/releases/v0.4.4.md`,
  `docs/release-readiness.md`, and the release notes index to reflect the
  published `v0.4.4` state.
- Updated release process guidance so publication approval triggers
  release-finalization alignment rather than immediate tag or GitHub Release
  creation.
- Extended the validator so `-TargetVersion <version>` blocks mismatched README,
  release notes, release readiness, and release index metadata.
- Recorded release scope, validation evidence, known limitations, risk/rollback,
  and maintainer recommendation in public-safe release-facing artifacts.

## 4. Non-Goals

- Do not retag `v0.4.4`.
- Do not republish or edit the already published GitHub Release.
- Do not push directly to `main`.
- Do not modify repository settings, rulesets, branch protection, sensitive
  repository configuration, runners, or GitHub App configuration.
- Do not change install profile behavior or add public domain packs.
- Do not implement or close #23.
- Do not put private overlay paths, local-only runtime state, sensitive audit
  details, or machine-specific scratch paths into public artifacts.

## 5. Constraints

- Public release artifacts may include bilingual release copy when the release
  requires it.
- English remains the default for public specs and durable process docs.
- Release preparation must use PR review before any tag or published release.
- Release finalization must align public metadata and pass validation before any
  future tag or GitHub Release publication.
- Durable specs may record release scope, decisions, acceptance evidence, and
  completed results, but should not act as a transient operational status
  dashboard.

## 6. Assumptions

- The post-`v0.4.3` merged work is sufficient for a patch release rather than a
  minor release because it does not expand install profiles, add public domain
  packs, or introduce a new product surface.
- #23 can serve as the issue-first release-planning reference when the release
  prep work references it without a closing keyword.
- `docs/releases/README.md` is the release notes index named by the validator
  alignment requirement.

## 7. Risks

- Release notes could overstate publication status if release-prep wording is
  not clear.
- Validator expectations must stay aligned with release-facing docs so release
  hygiene does not drift.
- Including bilingual content in a public English-first repository can create
  duplicated summary text; the bilingual requirement is intentionally limited
  to release-facing copy.
- A future release-preparation PR may intentionally leave README on the latest
  published version; the finalization guardrail is run with the explicit target
  version when publication is authorized.

## 8. Proposed Approach

- Keep `README.md` and `README.en.md` on the latest published release until
  `v0.4.4` is tagged and published.
- Add `docs/releases/v0.4.4.md` as a release-prep draft with copyable bilingual
  GitHub Release body.
- Move the post-`v0.4.3` changelog batch into a `v0.4.4` release-prep candidate
  entry.
- Update release readiness and release process documentation with candidate
  positioning and validation coverage.
- Extend the release validator to require the `v0.4.4` release-prep notes and
  release index entry.
- Post-publication addendum: update the current release fields to `v0.4.4`,
  convert `docs/releases/v0.4.4.md` and release readiness to published-release
  metadata, remove the release notes index draft marker, document
  release-finalization alignment, and add target-version alignment checks to the
  validator.

## 9. Acceptance / Evidence

- `docs/releases/v0.4.4.md` includes `中文` and `English` sections with
  equivalent release scope, validation, upgrade impact, known limitations,
  risk/rollback, and maintainer recommendation.
- `CHANGELOG.md`, `docs/releases/README.md`, `docs/release-readiness.md`, and
  `docs/release-process.md` are consistent with the release candidate.
- `scripts/validate-release.ps1` checks `v0.4.4` release-prep coverage.
- `README.md`, `README.en.md`, `docs/releases/v0.4.4.md`,
  `docs/release-readiness.md`, and `docs/releases/README.md` are consistent
  with the published `v0.4.4` state.
- `scripts/validate-release.ps1 -TargetVersion v0.4.4` checks publish-ready
  metadata alignment and published `v0.4.4` release notes coverage.
- `git diff --check` passes.
- Full local release validation passes with
  `PASS=52 FAIL=0 WARN=0 DEFERRED=0`.
- Hosted validation for the release-finalization guardrail addendum passed as
  public evidence: PR base guard plus the Release validation matrix for Windows
  PowerShell 5.1, Windows pwsh, Ubuntu pwsh, and macOS pwsh.

## 10. Loop Contract

- Not applicable.

## 11. Execution Contract

- **Autonomy level**: bounded-autonomous
- **Phase list**:
  - P01: Assess public GitHub and `main` state after `v0.4.3`.
  - P02: Prepare release-facing docs and changelog records.
  - P03: Add validator coverage for the release-prep draft.
  - P04: Run local validation and record maintainer handoff evidence.
  - P05: Correct post-publication metadata and add target-version
    release-finalization alignment.
- **Continue rule**: Continue while changes stay within release-prep docs,
  release readiness, public specs, and validator coverage.
- **Stop rule**: Stop for tag creation, GitHub Release publication, direct
  `main` push, repository settings/ruleset/sensitive-configuration changes,
  profile behavior changes, domain-pack expansion, #23 implementation, private
  data exposure, skipped acceptance checks, or unresolved release-scope
  ambiguity.
- **State record**: This spec and `tasks.md`.

## 12. Open Questions

- None. No tag, GitHub Release, direct `main` push, settings change, or #23
  state change is part of this addendum.
