# Changelog

All notable public changes are summarized here.

## Unreleased

- No unreleased public changes after the `v0.6.0` release.

## v0.6.0 - 2026-07-11

- Changed ordinary runtime installation to copy-first with schema-2 per-file
  ownership and content hashes, incremental refresh, explicit conflict reports,
  protected unknown/local content, and reviewed schema-1 migration through
  `-ReplaceManaged`. (Issue #219; PR #230)
- Added an explicit opt-in agent-specific skill bridge from installed runtime
  copies, with canonical ownership, containment checks, transactional rollback,
  and independent local metadata. (Issue #220; PR #231)
- Added a public-safe local candidate inbox with read-only discovery, explicit
  intake, and human triage;
  candidates remain separate from formal global experience and are never
  promoted automatically. (Issue #222; PR #232)
- Added a lightweight session-learning trigger to project-agent templates while
  preserving user confirmation and the no-automatic-promotion boundary.
  (Issue #225; PR #233)
- Added opt-in directory index health diagnostics, a reusable index governance
  reference, one public fixture pilot, and deterministic validation. (Issue
  #217; PRs #234, #235)
- Hardened public-safe experience metadata and multilingual anchor behavior,
  then fixed multiline keywords and cross-PowerShell score ordering with
  deterministic symptom coverage. (Issues #221, #223, #236, #238; PRs #228,
  #229, #237, #239)
- Grew full release validation from the `v0.5.2` 81-PASS baseline to
  `PASS=86 FAIL=0 WARN=0 DEFERRED=0` on both PowerShell 7 and Windows
  PowerShell 5.1.

## v0.5.2 - 2026-07-07

- Added Claude Code hooks guardrails and an executable template reliability
  runtime for project-bootstrap outputs, covering lifecycle hook registration,
  command-risk checks, public-safe fixtures, and release validation. (Issue
  #205; PRs #206, #207)
- Expanded testing and evaluation support with testing workflow templates, spec
  testing evidence guidance, a testing-core knowledge domain pack, and
  eval-driven skill iteration contracts, fixtures, report generation, runner
  output artifacts, and benchmark guidance. (Issues #166, #168, #210; PRs
  #191, #195-#201, #208, #209, #212)
- Improved skill discovery and metadata compatibility with a cross-runtime
  compatibility audit, additive frontmatter metadata, compatibility fields, and
  read-only skills discovery command cards. (Issue #165; PRs #192-#194, #213)
- Completed the public-safe #167 knowledge lifecycle split with hot memory
  soft-length diagnostics, human-reviewed experience lifecycle metadata,
  generated index lifecycle fields, context index guidance, and deterministic
  release validation. (Issue #167; PRs #190, #214, #215)
- Added smaller workflow-spec-lite, project-memory, and knowledge pattern
  improvements, including requirements clarification, decision validation, ADR
  usage guidance, terminology guidance, and an issue-decomposition fixture.
  (Issues #169, #183, #185, #188; PRs #182, #186, #187, #189)
- Grew release validation from the `v0.5.1` `PASS=62` baseline to the current
  `PASS=81 FAIL=0 WARN=0 DEFERRED=0` state.

## v0.5.1 - 2026-06-27

- Hardened memory governance with project memory template guidance, aligned
  commands index startup guidance, integrated memory diagnosis into the
  phase-close gate, defined structural memory diagnostics, added completed-list
  growth detection, and fixed stable notes preservation during memory upgrade.
  (Issues #151, #152, #153, #154, #155, #158; PRs #157, #159, #160, #161,
  #162, #163, #164)
- Clarified public-safe write authorization boundaries for cross-repository
  write scope. (Issue #170, PR #173)
- Added testing capability foundations as the first slice toward full testing
  coverage: TDD and test-strategy knowledge patterns, project-agent test
  workflow command cards, testing convention context entries, and workflow-spec-lite
  test guidance. (Issue #168, PR #174)
- Refactored `scripts/validate-release.ps1` from 2,496 lines to a 566-line
  main entrypoint with 10 extracted validation helper modules, completing the
  release validator thin-entrypoint closeout. (Issue #175, PRs #176-#180)

## v0.5.0 - 2026-06-09

- Added the stabilization-first v0.5.0 maintenance scope and completed the
  accepted pre-release governance sequence without expanding public domain
  packs, install profiles, or shell surfaces. (Issue #120, PR #129)
- Stopped tracking public root `docs/specs/**` maintenance work packages and
  kept public repository maintenance state in GitHub issues, pull request
  bodies, release docs, and governance docs. (Issue #127, PR #128)
- Clarified `project-bootstrap` command ownership, context gate brief output,
  runtime adoption bridge documentation, and PowerShell helper ownership.
  (Issues #116, #117, #119, #97; PRs #130, #131, #133, #134, #135)
- Refactored the release validator into stable helper and check-group
  boundaries, including workflow-spec-lite fixture extraction and language
  migration mode-handler separation. (Issue #96, PRs #136-#140)
- Documented the old-release upgrade path and recorded the `v0.4.6` to current
  `main` rehearsal evidence required before tagging v0.5.0. (Issue #118,
  PR #141)
- Added the bootstrap-provided `CLAUDE.md` shim for Claude Code adoption.
  (Issue #142, PR #144)
- Hardened agent issue triage decision handling for missing decision sections
  and stabilized maintainer comment command body updates. (Issues #121, #123,
  #125, #143; PRs #122, #124, #126, #147)
- Added a hosted PR identity guard for explicitly agent-authored pull requests,
  validating bot author and committer identity across every PR commit.
  (Issue #145, PR #148)

## v0.4.6 - 2026-05-29

- Added spec lifecycle and review status hygiene documentation, including
  completed-spec status guidance and README navigation. (Issue #98, PR #111)
- Added public-safe reusable knowledge patterns for staged refactor execution,
  issue decomposition, and error diagnosis framing. (Issue #100, PR #112)
- Separated public GitHub Release body copy from internal release records,
  added explicit release body markers, cleaned stale pre-publication wording from
  historical release notes, and hardened release validation against the
  regression. (Issue #113, PR #114)

## v0.4.5 - 2026-05-29

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

## v0.4.4 - 2026-05-22

- Published a stabilization / docs / governance patch release. The
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
