# Confirmed Notes

- Record verified facts only.
- Include evidence source where possible.
- The public release validation gate is `scripts/validate-release.ps1`; it
  validates structure, metadata, installer profiles, copy/link modes, runtime
  smoke checks, installer behavior, hub.lock drift checks, experience search,
  experience promotion closure, audit checks, parser checks, JSON parsing, and
  duplicate helper hashes.
- The local `v0.1.0` release candidate passed release validation on 2026-05-07
  with 12 pass, 0 fail, 0 warn, and 1 deferred non-blocking behavior check.
- The hardened local release validator passed on 2026-05-08 with 15 pass,
  0 fail, 0 warn, and 1 deferred non-blocking behavior check.
- CI release validation workflow exists at
  `.github/workflows/release-validation.yml` for Windows, Ubuntu, and macOS.
- Hosted release validation passed on Windows, Ubuntu, and macOS on 2026-05-07:
  https://github.com/Huangshier/agent-ecosystem/actions/runs/25509636087
- `.gitattributes` pins validation-sensitive text files to LF endings so
  experience registry hashes remain stable across hosted Windows checkouts.
- `v0.1.0` publication was explicitly requested on 2026-05-07.
- `v0.1.0` GitHub Release:
  https://github.com/Huangshier/agent-ecosystem/releases/tag/v0.1.0
- For `v0.1.0`, `full` and `dev` are public profile placeholders that install
  the same content as `recommended`; future releases may add public domain
  packs or developer maintenance tooling.
- The initial public experience entry is a reindexed public-safe backfill.
  Its index metadata intentionally omits local source paths and private
  migration details.
- The latest published public release is `v0.4.3`:
  https://github.com/Huangshier/agent-ecosystem/releases/tag/v0.4.3
- Final `v0.3.1` main release validation run passed on 2026-05-09:
  https://github.com/Huangshier/agent-ecosystem/actions/runs/25598098034
- `knowledge-hub/` is part of the `agent-ecosystem` repository tree. It is not
  a Git submodule and should not contain a local nested `.git` directory.
- PR #6 added `project-bootstrap -AutoUpgrade` and the Step 2.5 memory upgrade
  decision workflow, closing GitHub issues #4 and #5.
- PR #20 added minimal agent governance docs/templates and closed issue #19.
- PR #24 normalized `v0.3.1` release readiness evidence and closed issue #21.
- PR #26 documented the installed `agent-ecosystem-bot` GitHub App identity and
  closed issue #25. Merge commit: `817c0841550de24a0bbf10a097829dd2e11b388e`.
- PR #28 added the end-to-end minimal project adoption walkthrough and closed
  issue #22. Merge commit:
  `38e39834398e034698b9c37541605a8a7630f04e`.
- PR #34 documented validation-tier policy and closed issue #27. Merge commit:
  `67dfdf161dad99c67f107099a58e2768cf65d190`.
- PR #35 `fix: protect project memory upgrades` was opened by
  `app/agent-ecosystem-bot` as a draft PR for #29 and #31:
  https://github.com/Huangshier/agent-ecosystem/pull/35
- PR #35 evidence-mapping update adds bootstrap evidence reports under
  `.agents/_backup/bootstrap-*/bootstrap-evidence.json` and `.md` in target
  projects. Local release validation after the update passed:
  `PASS=34 FAIL=0 WARN=0 DEFERRED=0`.
- PR #35 `fix: protect project memory upgrades` merged on 2026-05-12 at
  `89a7bd7e893378c19a6930288bff8c081d1732c1`; issues #29 and #31 are closed
  with `state_reason=completed`. The merged branch
  `issue-29-31-memory-safety` was cleaned locally and remotely after merge
  confirmation.
- Issue #36 was accepted on 2026-05-12 for a lightweight PR-ready /
  phase-close engineering-memory sync gate. It remains scoped to governance
  docs, skill guidance, specs, and tracked engineering memory; it does not
  include pre-commit hooks, GitHub ruleset changes, hosted-check loops, or
  implementation of #30/#32/#33.
- PR #37 `docs: add PR-ready memory sync gate` was opened by
  `app/agent-ecosystem-bot` for #36:
  https://github.com/Huangshier/agent-ecosystem/pull/37
- PR #37 merged on 2026-05-12 at
  `b5263c25512880e8f64c52d5a9dcab399de4a529`; issue #36 is closed with
  `state_reason=completed`. Hosted release validation run `25719200593` passed
  on Windows PowerShell 5.1, Windows pwsh, Ubuntu pwsh, and macOS pwsh.
- Issue #38 `Fix: add validation scratch retention pruning` was created by
  `agent-ecosystem-bot[bot]` for guarded scratch retention cleanup:
  https://github.com/Huangshier/agent-ecosystem/issues/38
- PR #39 `fix: add validation scratch pruning` was opened by
  `agent-ecosystem-bot[bot]` as a draft PR for #38:
  https://github.com/Huangshier/agent-ecosystem/pull/39
- PR #39 hosted release validation run `25724432079` passed on Windows
  PowerShell 5.1, Windows pwsh, Ubuntu pwsh, and macOS pwsh before the
  memory-closeout commit. Do not create repeated memory-only commits solely to
  refresh hosted-check timestamps.
- The configured repository automation identity is the `agent-ecosystem-bot`
  GitHub App. App auth material and local-only paths must not be stored in this
  public repository.
- The `protect-main` repository ruleset protects the default branch with
  required pull requests, required release validation checks, conversation
  resolution, deletion blocking, force-push blocking, and no bypass actors.
- PR #43 `ci: add issue triage label sync` was opened as a draft PR for issue
  #42. It adds a scoped issue-label synchronization workflow for explicit
  human triage checklist decisions; #30 migration implementation remains out
  of scope.
- PR #45 `[codex] Improve AGENTS startup templates` merged on 2026-05-13 and
  closed issue #44. It added Project Commands, large-issue planning / PR split,
  PR-ready memory sync, and no post-PR memory-only commit guidance to base
  templates.
- Issue #30 conservative language migration implementation passed local
  validation on 2026-05-13 with `git diff --check` and
  `scripts/validate-release.ps1` reporting `PASS=40 FAIL=0 WARN=0 DEFERRED=0`.
- PR #46 blocking-concern fixes for issue #30 passed local validation on
  2026-05-13 with `git diff --check` and `scripts/validate-release.ps1`
  reporting `PASS=40 FAIL=0 WARN=0 DEFERRED=0`.
- PR #47 `[codex] Add narrative language migration` merged on 2026-05-13 at
  `2beb8285803abe17daaea1d2eac590cb91d2aef0`, closing issue #30. Hosted release
  validation run `25795197326` passed on Windows PowerShell 5.1, Windows pwsh,
  Ubuntu pwsh, and macOS pwsh.
- Issue #30 `Feature: support conservative en/zh-CN engineering-memory language
  migration` closed on 2026-05-13 with `state_reason=completed`.
- `v0.4.0`, `v0.4.1`, `v0.4.2`, and `v0.4.3` have been published as GitHub
  Releases.
- PR #63 `[codex] Rebuild v0.4.3 release-prep from main` merged on 2026-05-14
  at `26072b7f8e25e2a5b1092b6af45d47ae1c43cac8`, completing issue #57.
- Hosted Release validation run `25841179794` passed for the `v0.4.3` tag
  target on Windows PowerShell 5.1, Windows pwsh, Ubuntu pwsh, and macOS pwsh.
- The tracked `.agents/plan.md`, `.agents/process.txt`, and `.agents/notes.md`
  files are project-specific engineering memory, not canonical release records.
  Do not create repeated memory-only commits solely to refresh per-push hosted
  CI timestamps.
- Accepted stabilization guardrails closed on 2026-05-20:
  #70, #75, #72, #73, and #74 are merged to `main` at
  `c35c35917c2dce55260f400312a4a5e15cd00932`. Issues #65, #66, #68, and #69
  are closed as completed; #67, #56, and #23 remain deferred/open.
- PR #71 was accidentally merged into the stacked base branch instead of
  `main`. Replacement PR #75 landed the same #65 Phase B/C scope on `main`.
- GitHub issue bodies and PR bodies using `Refs #...` do not auto-close issues.
  Use `Closes #...` or `Fixes #...` when automatic closeout is intended, or
  close manually after explicit authorization.
- PR #76 `docs: close out accepted stabilization state` merged on 2026-05-20
  at `8049a3e0058b42a1ee58f74c643be1cd0ac101b9`. Hosted Release validation run
  `26182173732` passed on `main`.
- The post-`v0.4.3` flow audit decision is to add PR base/stack guardrails and
  release-validation concurrency first, without splitting CI. A future CI split
  must preserve an always-run required check and update repository required
  checks and release-process documentation together.
