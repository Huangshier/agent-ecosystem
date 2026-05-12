# Active Plan

Active Spec
- `docs/specs/pr-ready-memory-sync-gate/spec.md` (Active)
- Completed reference:
  `docs/specs/memory-safety-language-normalization/spec.md` (Done)
- Completed reference:
  `docs/specs/validation-tier-policy/spec.md` (Done)
- Completed reference:
  `docs/specs/minimal-project-adoption-walkthrough/spec.md` (Done)

Current Task
- Resolve issue #36: add a PR-ready / phase-close engineering-memory sync gate
  without hooks, ruleset changes, or #30/#32/#33 implementation.

Session Status
- `v0.3.1` has been published.
- Final `v0.3.1` main release validation run `25598098034` passed.
- PR #20 added minimal agent governance docs/templates and closed issue #19.
- PR #24 normalized `v0.3.1` release readiness evidence and closed issue #21.
- PR #26 documented `agent-ecosystem-bot` and closed issue #25.
- PR #28 added the minimal project adoption walkthrough and closed issue #22.
- PR #34 documented validation-tier policy and closed issue #27.
- PR #35 protected project memory upgrades and closed issues #29 and #31.
- Repository ruleset `protect-main` and GitHub App `agent-ecosystem-bot` are
  configured external governance controls.

Next Work
- [x] Sync public `main` to PR #35 merge commit.
- [x] Confirm #29/#31 are closed as completed.
- [x] Clean merged branch `issue-29-31-memory-safety` locally and remotely.
- [x] Accept #36 by updating triage labels.
- [x] Add PR-ready / phase-close memory sync gate guidance.
- [x] Close out #35 memory-safety work package as Done.
- [x] Validate, commit, push, and open draft PR #37 for #36.
- [ ] Wait for hosted checks and maintainer review / ready decision on PR #37.
- [ ] Keep #23 deferred until the next release direction is chosen.
- [ ] Keep #30, #32, and #33 deferred unless explicitly selected later.

Notes
- Do not store private mappings, local paths, or sensitive audit findings here.
