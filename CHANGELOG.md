# Changelog

All notable public changes are summarized here.

## Unreleased

No unreleased public changes.

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
