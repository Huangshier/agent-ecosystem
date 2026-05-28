# Staged Refactor Execution

Maturity: draft
Scope: cross-project
Source: manual
Last reviewed: 2026-05-29

## Summary

Break a large refactor into independent, reviewable stages that each leave the
system in a working state. Each stage has its own commit, validation boundary,
and rollback point so that a failed stage does not require reverting the entire
refactor.

## Use When

- The refactor touches many files, modules, or interfaces.
- The change cannot be validated in a single pass.
- Reviewers need to inspect incremental diffs rather than one large diff.
- The refactor must preserve backward compatibility across stages.
- A partial merge is acceptable and useful.

## Do Not Use When

- The change is a single-file rename or trivial cleanup.
- The refactor is atomic by nature (all parts must land together or none).
- The project already has a narrower refactor workflow.

## Steps

1. **Inventory surfaces**: list every file, module, interface, or config that the
   refactor will touch. Group by dependency order.
2. **Define stage boundaries**: each stage should be independently compilable,
   testable, and reviewable. Prefer dependency-first ordering (foundational
   changes before consumers).
3. **Write a stage spec**: for each stage, state the goal, affected files,
   validation command, and rollback strategy. Use the project spec template.
4. **Implement one stage at a time**: commit after each validated stage. Do not
   combine stages into a single commit.
5. **Validate per stage**: run the project's deterministic checks after each
   stage. Record pass/fail in the spec or task list.
6. **Handoff at stage boundaries**: if a stage requires human review or external
   CI, pause and record state before continuing.

## Validation

- Each stage commit passes the project's build and test checks independently.
- The spec records which stages are complete, which are pending, and what
  evidence exists for each.
- No stage introduces a regression that the next stage must fix.
- Rollback is possible at any stage boundary without cascading reverts.
