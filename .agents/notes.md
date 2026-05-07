# Confirmed Notes

- Record verified facts only.
- Include evidence source where possible.
- The public release validation gate is `scripts/validate-release.ps1`; it
  validates structure, metadata, installer profiles, copy/link modes, runtime
  smoke checks, experience search, audit checks, parser checks, JSON parsing,
  and duplicate helper hashes.
- The local `v0.1.0` release candidate passed release validation on 2026-05-07
  with 12 pass, 0 fail, 0 warn, and 1 deferred non-blocking behavior check.
- `v0.1.0` publication was explicitly requested on 2026-05-07.
- `v0.1.0` GitHub Release:
  https://github.com/Huangshier/agent-ecosystem/releases/tag/v0.1.0
- For `v0.1.0`, `full` and `dev` are public profile placeholders that install
  the same content as `recommended`; future releases may add public domain
  packs or developer maintenance tooling.
- The initial public experience entry is a reindexed public-safe backfill.
  Its index metadata intentionally omits local source paths and private
  migration details.
