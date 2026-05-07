# Context Gate to Spec to Validation Loop

Maturity: verified
Scope: cross-project
Source: manual
Last reviewed: 2026-05-08

## Summary

Use a context gate, a lightweight work spec, and deterministic validation as one
continuous loop for non-trivial repository work.

## Use When

- The task spans multiple files, repositories, or validation steps.
- The work may pause and resume across sessions.
- The result should be reviewable from project artifacts, not only chat history.
- Public/private boundaries or release readiness matter.

## Do Not Use When

- The task is a tiny one-file edit with obvious acceptance.
- The user only asked for a read-only answer and no durable work package is
  needed.

## Steps

1. Run the project context gate and summarize the active constraints.
2. Search for an existing matching spec before creating a new one.
3. Write the smallest useful spec and task list for the work.
4. Implement in bounded phases that map back to the spec.
5. Run deterministic checks that match the touched surface.
6. Update the state record with what passed, what remains, and where evidence
   lives.

## Validation

- The active spec states goals, non-goals, constraints, risks, and acceptance.
- The task list has checkable steps and current status.
- Validation output is reproducible from a local command or durable artifact.
- Session memory points to the active spec instead of duplicating it.
