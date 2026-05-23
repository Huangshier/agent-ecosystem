# Long Session Phase Split

Maturity: verified
Scope: cross-project
Source: promoted
Last reviewed: 2026-05-24

## Summary

Split large, restart-prone, or evidence-heavy agent work into three durable
phases: spec, implementation, and closeout. Each phase should have an explicit
state record and validation boundary so the work can resume without relying on
chat history alone.

## Use When

- A session is likely to span many files, tools, repositories, or validation
  cycles.
- Reverse engineering, firmware, CI, release, or migration work may produce
  large logs or long-running tool output.
- The work may pause for human review, external CI, device availability,
  network access, or a follow-up session.
- Public/private boundaries or sensitive evidence must be summarized safely.
- A prior session became too large to review or resume confidently.

## Do Not Use When

- The task is a small one-file fix with obvious validation.
- The user only asks for a read-only answer.
- A project already has a narrower domain workflow that defines equivalent
  phase records and validation evidence.

## Steps

1. **Spec phase**: run the project context gate, identify the write boundary,
   create or reuse a work spec, and define goals, non-goals, risks,
   acceptance, validation, and stop rules.
2. **Implementation phase**: make bounded changes that map back to the spec or
   task list. Record meaningful discoveries, validation attempts, and blockers
   in the state record instead of only in chat.
3. **Closeout phase**: rerun the relevant validation, update the spec/tasks
   with final evidence, sync only the necessary project memory, and prepare the
   issue or pull request handoff.
4. If work resumes after a pause, branch switch, commit, context compaction, or
   user correction, rerun the context gate before continuing.
5. If the session grows beyond the current phase's reviewability, stop at a
   phase boundary and hand off through the state record.

## State Record

Use project-local or public artifacts according to the repository boundary:

- `docs/specs/<slug>/spec.md` for durable goals, constraints, decisions, risks,
  and acceptance evidence.
- `docs/specs/<slug>/tasks.md` for multi-phase execution status.
- `.agents/plan.md` for the current local pointer only, when project memory is
  present.
- `.agents/process.txt` for local current state, blockers, branch/PR status, or
  next action.
- GitHub issues and pull requests for public review state.

## Validation

- The spec identifies the active phase and stop rule.
- The task list records completed phases, validation evidence, and next action.
- Private logs, local paths, secrets, and repository mappings are summarized or
  omitted from public artifacts.
- The final handoff states what changed, what passed, what was skipped, and
  what still requires human review.
