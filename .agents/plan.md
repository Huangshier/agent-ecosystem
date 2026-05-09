# Active Plan

Active Spec
- `docs/specs/bootstrap-auto-upgrade/spec.md`

Current Task
- Resolve GitHub issues #4 and #5 through a public maintenance branch.

Session Status
- Issues reviewed: #4 requests `bootstrap_project.ps1 -AutoUpgrade`; #5
  requests the workflow decision point around detected memory upgrade
  candidates.
- Branch: `issue-4-5-bootstrap-auto-upgrade`.

Next Work
- [x] Implement and targeted-smoke `-AutoUpgrade`.
- [x] Update project-bootstrap workflow docs.
- [x] Run full release validation (`PASS=31 FAIL=0 WARN=0 DEFERRED=0`).
- [ ] Push PR, merge, and confirm issues #4 and #5 close.

Notes
- Do not store private mappings, local paths, or sensitive audit findings here.
