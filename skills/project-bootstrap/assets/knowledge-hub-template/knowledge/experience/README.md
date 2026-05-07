# Shared Experience Knowledge

Promoted cross-project experience files live here.

Index metadata is stored in `index.json`.

## Retrieval Rule
- Do not preload this directory into normal project sessions.
- Search `index.json` first and open only matching experience entries when the issue looks related to toolchains, host environment, shell behavior, build systems, caches, ports, permissions, path handling, or other cross-project workflow failures.

## Promotion Rule
- Promote a lesson here when the root cause is primarily toolchain/host/workflow driven, the fix does not depend on current repository business code, and the lesson can be stated as a stable prevention rule.
- If the issue is likely repository-specific, keep it in project-local `.agents/context/experience/` first and promote only after recurrence or cross-project confirmation.
- Project-local source files should explicitly say `Global candidate: Yes` or `Scope: Cross-project reusable` before the default promotion command will pick them up.

## Maintenance Rule
- `index.json` is the lightweight discovery registry for this directory, not the primary editing target.
- Maintain this registry through installed `knowledge-hub/scripts`: `promote_experience.ps1` for reviewed project-to-hub promotion and `rebuild_experience_index.ps1` for backfill or repair when hub files already exist.
- Experience files should include `Maturity`, `Scope`, `Source`, and
  `Last reviewed` metadata near the top so the catalog can distinguish draft,
  verified, proven, and deprecated entries.
