# Active Plan

Active Spec
- Private control work item:
  `release-validation-hardening` (tracked outside this public repository)

Current Task
- Release validation hardening for the public repository is complete.

Session Status
- Public validator has been expanded and passes locally:
  15 pass, 0 fail, 0 warn, 1 deferred.
- CI workflow has been added:
  `.github/workflows/release-validation.yml`.
- Hosted CI matrix passed on Windows, Ubuntu, and macOS:
  https://github.com/Huangshier/agent-ecosystem/actions/runs/25509636087
- Public release process/readiness docs have been updated.

Next Work
- Start a new maintenance/release work item for future public changes.

Notes
- Do not store private mappings, local paths, or sensitive audit findings here.
