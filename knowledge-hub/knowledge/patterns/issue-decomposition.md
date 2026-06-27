# Issue Decomposition

Maturity: draft
Scope: cross-project
Source: manual
Last reviewed: 2026-06-27

## Summary

Decompose a complex issue or task into independently scoped, verifiable
sub-tasks that can be implemented, reviewed, and validated in isolation.
Each sub-task has clear acceptance criteria and does not depend on
unscoped future work.

## Use When

- An issue or task spans multiple modules, concerns, or validation steps.
- The scope is too large for a single PR or review cycle.
- Sub-tasks have different risk profiles, priorities, or review requirements.
- Parallel work by multiple agents or contributors is possible.
- The original request mixes bug fixes, features, and documentation.

## Do Not Use When

- The task is already a single, atomic change.
- Decomposition would create artificial boundaries that increase complexity.
- The user explicitly requests a single combined change.

## Steps

1. **Read the full scope**: understand the original request, constraints, and
   acceptance criteria before splitting.
2. **Identify independent concerns**: group related changes by module, risk
   level, or review requirement. Flag shared dependencies.
3. **Define sub-task boundaries**: each sub-task should be completable in one
   PR, pass independent validation, and leave the system working.
4. **Order by dependency**: implement foundational changes first (interfaces,
   shared utilities, config), then consumers. Document the intended merge
   order.
5. **Write scoped acceptance**: each sub-task gets its own acceptance criteria
   that can be verified without reference to other sub-tasks.
6. **Track in a single parent spec**: link all sub-tasks to the parent issue
   or spec so the decomposition is auditable.

## Validation

- Each sub-task has its own issue, PR, or task checklist with acceptance
  criteria.
- No sub-task introduces a regression that requires another sub-task to fix.
- The parent spec or issue links to all sub-tasks and records overall
  completion status.
- Merge order is documented and safe (no forward dependencies).
