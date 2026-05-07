# Embedded Core Domain Pack

Maturity: draft
Scope: cross-project
Source: public migration closeout
Last reviewed: 2026-05-08

## Summary

Public-safe embedded engineering guidance for agents working around firmware
builds, device flashing, serial ports, and hardware-adjacent validation.

This pack is intentionally knowledge-first. It is not a domain skill and does
not assume a specific vendor SDK, board, serial port, or local toolchain path.

## Use When

- A task involves firmware build or device validation planning.
- A serial, flashing, or monitor workflow needs explicit safety boundaries.
- The agent needs to decide whether to use project-local instructions, a
  private domain skill, or generic public knowledge.

## Non-Goals

- No private board names, local ports, local toolchain paths, or project-specific
  test commands.
- No SDK-specific automation that would require private environment knowledge.
- No replacement for project documentation or hardware-owner instructions.

## Entries

- [Validation Checklist](validation-checklist.md): generic embedded validation
  boundaries for build, flash, monitor, and post-flash checks.

## Promotion Rule

Promote a domain pack entry into a skill only after the same workflow recurs
across projects, has stable inputs and outputs, and can be validated without
private assumptions.
