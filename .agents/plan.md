# Active Plan

Active Spec
- `docs/specs/validation-scratch-retention/spec.md` (Active)
- Completed reference:
  `docs/specs/pr-ready-memory-sync-gate/spec.md` (Done via PR #37)
- Completed reference:
  `docs/specs/memory-safety-language-normalization/spec.md` (Done)
- Completed reference:
  `docs/specs/validation-tier-policy/spec.md` (Done)
- Completed reference:
  `docs/specs/minimal-project-adoption-walkthrough/spec.md` (Done)

Current Task
- Resolve issue #38: add guarded validation scratch retention pruning without
  deleting existing local scratch contents, expanding PR #37, changing rulesets,
  adding hooks, or implementing #30/#32/#33.

Session Status
- `v0.3.1` has been published.
- Final `v0.3.1` main release validation run `25598098034` passed.
- PR #20 added minimal agent governance docs/templates and closed issue #19.
- PR #24 normalized `v0.3.1` release readiness evidence and closed issue #21.
- PR #26 documented `agent-ecosystem-bot` and closed issue #25.
- PR #28 added the minimal project adoption walkthrough and closed issue #22.
- PR #34 documented validation-tier policy and closed issue #27.
- PR #35 protected project memory upgrades and closed issues #29 and #31.
- PR #37 added the PR-ready / phase-close memory sync gate and closed issue
  #36.
- Repository ruleset `protect-main` and GitHub App `agent-ecosystem-bot` are
  configured external governance controls.

Next Work
- [x] Sync public `main` to PR #37 merge commit.
- [x] Confirm #36 is closed as completed and PR #37 is merged.
- [x] Create issue #38 with `agent-ecosystem-bot[bot]`.
- [x] Create branch `issue-38-validation-scratch-retention`.
- [x] Add guarded pruning helper, release validator coverage, docs, and spec.
- [x] Run local validation.
- [ ] Commit, push, and open draft PR for #38.
- [ ] Keep #23 deferred until the next release direction is chosen.
- [ ] Keep #30, #32, and #33 deferred unless explicitly selected later.

Notes
- Do not store private mappings, local paths, or sensitive audit findings here.
