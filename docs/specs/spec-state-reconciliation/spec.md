# Work Spec

- **Title**: Specs State Reconciliation
- **Slug**: spec-state-reconciliation
- **Status**: Done
- **Owner**: Codex
- **Updated**: 2026-05-22

## 1. Summary

- Reconcile durable `docs/specs/**` state after several completed public PR
  batches left old work packages marked `Active`.
- This pass audits only spec/task state drift. It does not implement #23,
  publish a release, change install profile behavior, or modify repository
  settings, rulesets, tags, releases, sensitive repository configuration, or
  branch protection.

## 2. Audit Summary

- Active work packages audited: 13.
- Changed to `Done`: 13.
- Kept `Active`: 0.
- Changed to `Deferred`, `Superseded`, `Historical`, or
  `Needs maintainer decision`: 0.
- Human decision needed: none for the audited rows; each `Done` decision has
  merged PR, closed issue, or published release evidence.

## 3. Audit Table

| Slug / path | Current status before audit | Evidence | GitHub current state | Suggested status | Reason |
| --- | --- | --- | --- | --- | --- |
| `project-memory-template-authority` / `docs/specs/project-memory-template-authority/` | `Active` | PR #50 merged at `7978d53542de5ce8c35af4f16ffc32e647fe4db0`; issue #49 closed | Closed / merged | `Done` | The #49 template authority refactor landed; later v0.4.2 convergence is separate history. |
| `body-level-memory-language-audit` / `docs/specs/body-level-memory-language-audit/` | `Active` | PR #84 merged at `df208697889f4a3104f234c4b4c5aef4a79c1c22`; issue #67 closed | Closed / merged | `Done` | The read-only body-level audit helper and validator coverage landed. |
| `agents-template-startup-guidance` / `docs/specs/agents-template-startup-guidance/` | `Active` | PR #45 merged at `458e3834abf2648e907ce20a3c48e9d4fb5a6b9c`; issue #44 closed | Closed / merged | `Done` | Template startup guidance landed and the tracking issue is closed. |
| `conservative-language-migration` / `docs/specs/conservative-language-migration/` | `Active` | PR #46 merged at `ee327e75aa35bd38c7495a019eaa932f4f9395f2`; PR #47 merged at `2beb8285803abe17daaea1d2eac590cb91d2aef0`; issue #30 closed | Closed / merged | `Done` | Both deterministic and narrative migration phases landed; v0.4.0 records completion. |
| `issue-triage-label-sync` / `docs/specs/issue-triage-label-sync/` | `Active` | PR #43 merged at `c502f0cf894288ced1178ac182e57f50d62bc755`; issue #42 closed | Closed / merged | `Done` | The workflow, docs, and validation coverage landed. |
| `file-based-memory-templates` / `docs/specs/file-based-memory-templates/` | `Active` | PR #41 merged at `354b857087169a794ec1bca71258d3213f4e805f`; issue #32 closed | Closed / merged | `Done` | File-based `en` / `zh-CN` template work landed. |
| `memory-refresh-migration-semantics` / `docs/specs/memory-refresh-migration-semantics/` | `Active` | PR #85 merged at `d2a8a32adbf531ad36abb9894ae2508da4edc958`; issue #79 later closed by PR #86 | Merged; umbrella issue closed | `Done` | #79-A guidance semantics landed; remaining #79-B work is tracked by the separate review-flow spec. |
| `bootstrap-operating-modes` / `docs/specs/bootstrap-operating-modes/` | `Active` | PR #40 merged at `19656e5f92264a960c8e6ac6039debd97166c10f`; issue #33 closed | Closed / merged | `Done` | Safe refresh, compatibility warning, and force-reset semantics landed. |
| `minimal-project-adoption-walkthrough` / `docs/specs/minimal-project-adoption-walkthrough/` | `Active` | PR #28 merged at `38e39834398e034698b9c37541605a8a7630f04e`; issue #22 closed | Closed / merged | `Done` | The walkthrough and entrypoint links landed. |
| `memory-language-migration-review-flow` / `docs/specs/memory-language-migration-review-flow/` | `Active` | PR #86 merged at `8d1d07035a6be1bc642e82b73c50f29133f627ea`; issue #79 closed | Closed / merged | `Done` | #79-B workflow and validation behavior landed, closing the umbrella issue. |
| `v0-3-0-public-maintenance` / `docs/specs/v0-3-0-public-maintenance/` | `Active` | PR #3 merged at `433287141073e4ba216bc9f99da781a22c49cb0c`; issues #1 and #2 closed; release `v0.3.0` published | Closed / merged / published | `Done` | The maintenance PR merged and the release was published. |
| `template-language-directory-convergence` / `docs/specs/template-language-directory-convergence/` | `Active` | PR #52 merged at `e5367790469574a350bd9cbed28b56fd8b9f74bd`; issue #51 closed | Closed / merged | `Done` | The language-scoped template model landed and legacy paths are historical. |
| `validation-scratch-retention` / `docs/specs/validation-scratch-retention/` | `Active` | PR #39 merged at `f6d42726a882c961a59ebfca88db74d8bf0b9aa6`; issue #38 closed | Closed / merged | `Done` | The guarded scratch-retention helper and validation coverage landed. |

## 4. Decisions

- Durable completion evidence stays in the affected specs and tasks.
- Volatile branch, draft PR, hosted-check waiting, merge-wait, and PR-publish
  language was removed or rewritten where it contradicted current GitHub state.
- #23 remains open as a next-version planning umbrella. This reconciliation
  records that #56, #67, and #79 are complete, but it does not implement #23.
- `docs/release-readiness.md` now describes `full` and `dev` as reserved
  future public scopes that currently install the same content as
  `recommended`, avoiding the stale `v0.1.0` placeholder wording.

## 5. Acceptance / Evidence

- `rg` confirmed no active status marker remains under `docs/specs/**/spec.md` or
  `docs/specs/**/tasks.md`.
- `git diff --check` passes.
- `scripts/validate-release.ps1 -ScratchRoot <scratch>` passes.

## 6. Execution Contract

- **Autonomy level**: bounded-autonomous.
- **Phase list**:
  - P01: Scan active spec/task status.
  - P02: Verify public issue, PR, commit, and release evidence.
  - P03: Reconcile durable spec/task state and release-readiness wording.
  - P04: Validate and prepare scoped PR metadata that references #23 without
    closing it.
- **Continue rule**: Continue while changes stay limited to docs/spec state,
  release-readiness wording, and #23 triage context.
- **Stop rule**: Stop for #23 implementation, release publication, profile
  behavior changes, public domain-pack expansion, direct `main` pushes, tag or
  release edits, settings/ruleset/sensitive-configuration changes, or private
  data exposure.
- **State record**: This spec and `tasks.md`.
