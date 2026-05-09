# Changelog

All notable public changes are summarized here.

## Unreleased

- Made knowledge hub Git initialization explicit so `init_hub.ps1` does not
  create nested repositories by default.
- Made experience index rebuilds preserve registry files when entries are
  unchanged, avoiding timestamp-only diffs.
- Added release validation coverage for hub initialization Git mode and no-op
  experience index rebuilds.

## v0.3.0 - 2026-05-08

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
