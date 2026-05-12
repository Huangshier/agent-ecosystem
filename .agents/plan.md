# Active Plan

Active Spec
- `docs/specs/memory-safety-language-normalization/spec.md` (Active)
- Completed reference:
  `docs/specs/validation-tier-policy/spec.md` (Done)
- Completed reference:
  `docs/specs/minimal-project-adoption-walkthrough/spec.md` (Done)

Current Task
- Resolve issues #29 and #31: protect project-specialized memory during
  bootstrap refresh and make memory upgrade normalization language-aware.

Session Status
- `v0.3.1` has been published.
- Final `v0.3.1` main release validation run `25598098034` passed.
- PR #20 added minimal agent governance docs/templates and closed issue #19.
- PR #24 normalized `v0.3.1` release readiness evidence and closed issue #21.
- PR #26 documented `agent-ecosystem-bot` and closed issue #25.
- PR #28 added the minimal project adoption walkthrough and closed issue #22.
- PR #34 documented validation-tier policy and closed issue #27.
- Repository ruleset `protect-main` and GitHub App `agent-ecosystem-bot` are
  configured external governance controls.

Next Work
- [x] Implement #29 bootstrap overwrite safety.
- [x] Implement #31 language-aware memory upgrade normalization.
- [x] Add release validation fixtures for #29/#31.
- [x] Commit, push, and open draft PR #35 for #29/#31.
- [ ] Wait for hosted release validation on the PR.
- [ ] Keep #23 deferred until the next release direction is chosen.
- [ ] Keep #30-#33 deferred unless needed for the active safety fix.

Notes
- Do not store private mappings, local paths, or sensitive audit findings here.
