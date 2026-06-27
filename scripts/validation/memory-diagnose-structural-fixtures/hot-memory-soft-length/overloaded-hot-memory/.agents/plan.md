# Current Plan

## Current Work
- Implementing hot memory soft-length diagnostics for memory_diagnose.ps1.
- Adding public-safe fixtures for the new diagnostic family.
- Updating the release validator to cover new fixture cases.
- Writing documentation for the structural diagnostics roadmap.

## Current State
- The helper changes are drafted and under local validation.
- Fixture directory structure is created with positive and negative cases.
- The release validator fixture block needs final wiring.

## Non-Goals
- No automatic decay or knowledge maturity scoring.
- No changes to the existing LargeFileLineThreshold behavior.
- No error-driven sedimentation or last_accessed tracking.

## Next Steps
- Wire the new fixture block into validate-release.ps1.
- Run pwsh -NoProfile -File scripts/validate-release.ps1 -TargetVersion v0.5.1.
- Capture evidence and prepare the PR body with Refs #167.
