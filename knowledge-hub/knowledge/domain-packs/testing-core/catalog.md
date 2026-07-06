# Testing Core Domain Pack

Maturity: draft
Scope: cross-project
Source: issue #210
Last reviewed: 2026-07-06

## Summary

Public-safe testing guidance for agents that need to reason about validation
evidence, test boundaries, and project-owned test commands across target
projects.

This pack is intentionally knowledge-first. It is not a kernel skill, test
runner, fixture executor, or framework policy, and it does not make downstream
project tests part of this repository's release gate.

## Use When

- A task needs reusable testing vocabulary or validation boundaries.
- A project-specific test workflow exists and needs evidence recorded clearly.
- The agent needs to distinguish generic testing guidance from target-project
  commands, project-only harnesses, or future skill behavior.

## Non-Goals

- No `test-verification` kernel skill.
- No real target-project test runner, fixture executor, or command execution.
- No mandatory framework, coverage threshold, or language-specific policy.
- No LLM-dependent pass/fail judgment.
- No downstream test command becomes this repository's release gate.

## Entries

- [Validation Checklist](validation-checklist.md): generic boundaries for
  deciding what validation evidence belongs in a target-project task.

## Promotion Rule

Promote a testing domain pack entry into a skill only after repeated
cross-project use shows stable inputs, outputs, trigger rules, stop rules, and
deterministic validation options.
