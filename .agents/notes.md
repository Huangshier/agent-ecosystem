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
- The latest published public release is `v0.3.1`:
  https://github.com/Huangshier/agent-ecosystem/releases/tag/v0.3.1
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
- The configured repository automation identity is the `agent-ecosystem-bot`
  GitHub App. App auth material and local-only paths must not be stored in this
  public repository.
- The `protect-main` repository ruleset protects the default branch with
  required pull requests, required release validation checks, conversation
  resolution, deletion blocking, force-push blocking, and no bypass actors.
