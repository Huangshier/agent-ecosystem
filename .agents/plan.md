# Active Plan

Active Spec
- `docs/specs/hub-maintenance-hardening/spec.md`

Current Task
- Resolve GitHub issues #7 and #8 through an issue-first public maintenance PR.

Session Status
- Issues #7 and #8 were created and reviewed as project-relevant.
- Issue #7: `init_hub.ps1` should not create nested Git repos by default.
- Issue #8: experience index rebuilds should avoid timestamp-only diffs.

Next Work
- [x] Implement hub Git initialization hardening.
- [x] Implement idempotent experience index rebuild.
- [x] Run full release validation (`PASS=32 FAIL=0 WARN=0 DEFERRED=0`).
- [ ] Validate, open PR, merge, and confirm issues #7/#8 close.

Notes
- Do not store private mappings, local paths, or sensitive audit findings here.
