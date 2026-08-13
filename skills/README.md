# Skills

Public reusable skills live here.

The active C3.3 Runtime Skill authority is exactly two skills:

- `project-bootstrap`
- `project-workspace`

The superseded `project-context-gate`, `memory-governance`, and
`workflow-spec-lite` Skills are retired from C3.3 authority: after the one-time
default cutover they are no longer installed or newly bridged by any public
profile, and have no alias, forwarder, or dual-write path into C3.3. Their
source directories remain only for historical reading and are never re-installed
or newly bridged.

The frozen replacement mapping is:

- `project-context-gate` discovery -> `project-workspace discover`
- `memory-governance` Work, Context, checkpoint, and migration -> `project-workspace`
- `workflow-spec-lite` Spec authority -> `project-workspace create-spec`

This retirement boundary never removes user-owned project-local promoted Skills.

Kernel `SKILL.md` frontmatter should include:

- `category: kernel`
- `stability: stable`
- `scope: cross-project`
