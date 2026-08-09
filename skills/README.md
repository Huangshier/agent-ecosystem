# Skills

Public reusable skills live here.

First release scope is the Workflow Kernel:

- `project-bootstrap`
- `project-context-gate`
- `workflow-spec-lite`
- `memory-governance`

Domain skills are intentionally deferred.

## C3.3 lifecycle boundary

The dormant `c3-3-candidate` profile has exactly two Runtime Skill authorities:
`project-bootstrap` and `project-workspace`. The superseded
`project-context-gate`, `memory-governance`, and `workflow-spec-lite` Skills are
not installed or bridged by that profile and have no aliases, forwarders, or
dual-write path into C3.3.

The source directories remain temporarily because the uncut-over
`recommended`, `full`, and `dev` profiles still install them as a legacy-only
compatibility payload. Their presence for those profiles does not make them
C3.3 authority. The frozen replacement mapping is:

- `project-context-gate` discovery -> `project-workspace discover`
- `memory-governance` Work, Context, checkpoint, and migration -> `project-workspace`
- `workflow-spec-lite` Spec authority -> `project-workspace create-spec`

This compatibility boundary does not switch the default profile and never
removes user-owned project-local promoted Skills.

Kernel `SKILL.md` frontmatter should include:

- `category: kernel`
- `stability: stable`
- `scope: cross-project`
