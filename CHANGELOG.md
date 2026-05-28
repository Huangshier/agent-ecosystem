# Changelog

All notable public changes are summarized here.

## Unreleased

- No unreleased public changes after the `v0.4.5` maintenance preparation.

## v0.4.5 - (in preparation)

- Fixed issue triage label-sync to handle concurrent `issues` events
  idempotently. (Issue #102, PR #104)
- Aligned workflow-spec-lite validator with Simplified Chinese heading
  anchors. (Issue #94, PR #105)
- Fixed `validate_spec` UTF-8 no-BOM detection for zh-CN spec files.
  (Issue #106, PR #107)
- Added explicit minimal permissions to release-validation CI workflow.
  (Issue #95, PR #108)
- Added general bug report and feature request issue templates.
  (Issue #99, PR #109)

## v0.4.4 - 2026-05-22 (release-prep candidate)

- Prepared a stabilization / docs / governance patch release candidate. The
  copyable bilingual GitHub Release body is maintained in
  `docs/releases/v0.4.4.md`.
- Reconciled published `v0.4.3` release records after publication.
- Added cross-project closeout write-scope guardrails for public/private
  boundary control.
- Added cross-workspace root verification and `/goal` source/reference evidence
  guardrails.
- Added a generic high-risk evidence gate for workflow-spec guidance.
- Clarified project-bootstrap analyze, refresh, and project-memory language
  semantics.
- Expanded memory-scope discovery and language-governance guidance across
  context gate and memory governance skills.
- Closed out accepted stabilization engineering-memory state after PR #74.
- Added PR base/stack safety guardrails and release-validation concurrency.
- Localized root `.agents/` runtime state so checkout-local memory is ignored
  and no longer tracked as a public fact source.
- Made `README.md` the Simplified Chinese homepage and kept `README.en.md` as
  the English entrypoint.
- Added the domain-pack governance lifecycle without enabling new public domain
  packs or changing installer profile behavior.
- Added the read-only body-level project-memory language audit helper and
  validator fixtures.
- Improved memory refresh, reset, and language migration review semantics for
  `en` / `zh-CN` project memory.
- Reconciled completed public `docs/specs/**` work-package state and kept #23
  as a deferred next-version planning umbrella.

## v0.4.3 - 2026-05-14

- Published the post-`v0.4.2` stabilization release records.
- Normalized `v0.4.1` and `v0.4.2` release records and validator coverage.
- Added legacy template-path reference audit documentation and validation.
- Added existing-project upgrade guidance for the post-`v0.4.2`
  language-scoped template model.
- Recorded hosted release validation for tag target
  `26072b7f8e25e2a5b1092b6af45d47ae1c43cac8`.
- Kept `v0.5.0` expansion, new public domain packs, and `full` / `dev` profile
  behavior changes out of scope.

## v0.4.2 - 2026-05-13

- Converged project-memory templates to the language-scoped
  `templates/languages/<language>/project-root|project-agent` model under the
  public knowledge hub and the bundled `project-bootstrap` snapshot.
- Removed legacy top-level `templates/project-root`,
  `templates/project-agent`, and `templates/project-memory` entry trees.
- Updated bootstrap, language migration, hub initialization, hub-lock checks,
  docs, and release validation for the converged layout.
- Closed issue #51.

## v0.4.1 - 2026-05-13

- Consolidated project-memory template authority under
  `knowledge-hub/templates/project-memory/en|zh-CN/**`.
- Synchronized the bundled `project-bootstrap` knowledge-hub snapshot with the
  public template authority.
- Removed the standalone `skills/project-bootstrap/templates/project-memory/`
  tree and updated helper scripts plus release validation for the new authority
  model.
- Closed issue #49.

## v0.4.0 - 2026-05-13

- Added conservative `en` / `zh-CN` engineering-memory language migration with
  analyze, plan, proposal, backup, apply, and validate modes.
- Added Phase 2 narrative migration that reads retained manual-review artifacts
  and routes stable facts, active plan, process state, reusable lessons, and
  durable specs to the correct target-language engineering-memory surfaces.
- Added narrative proposal workflow with unapproved-by-default actions,
  hash-verified apply, and full validation coverage.
- Added release validation fixtures for both migration directions, mixed memory,
  project-specific preservation, hot-memory artifact routing, and narrative
  migration routing.
- Closed issue #30.

## v0.3.1 - 2026-05-09

- Clarified the public README and Chinese entrypoint around the Workflow Kernel
  positioning, extension model, and non-runtime boundaries.
- Added a lightweight Public Reader Review checklist to the release process and
  linked it from contributing guidance.
- Normalized v0.3.0 validation metadata and tightened release-note validation
  coverage to prevent summary drift.
- Updated the release validation workflow to Node 24-compatible action versions:
  `actions/checkout@v6` and `actions/upload-artifact@v7`.

## v0.3.0 - 2026-05-08

- Made knowledge hub Git initialization explicit so `init_hub.ps1` does not
  create nested repositories by default.
- Made experience index rebuilds preserve registry files when entries are
  unchanged, avoiding timestamp-only diffs.
- Added release validation coverage for hub initialization Git mode and no-op
  experience index rebuilds.
- Added manifest-based uninstall behavior that preserves unknown runtime files
  and provides manual cleanup guidance when no manifest exists.
- Added shared PowerShell helper extraction for path guards and release
  validation utilities.
- Added release validation coverage for large context-gate inputs, localized
  context discovery headings, bilingual public/private routing guidance, and
  cross-platform shell strategy.
- Documented PowerShell as the canonical public script surface for this release
  line while deferring Bash or Zsh wrappers.

## v0.2.0 - 2026-05-08

- Added release validation hardening for installer profiles, runtime smoke,
  hub.lock checks, knowledge hub metadata, sensitive scans, and language policy
  templates.
- Added public knowledge hub catalog, experience, pattern, standard, and
  domain-pack scaffold surfaces.
- Added adoption guidance and a minimal project example.

## v0.1.0

- Published the initial Workflow Kernel release with four kernel skills.
- Added the public installer and profile scaffold.
- Added public-safe knowledge hub templates.
