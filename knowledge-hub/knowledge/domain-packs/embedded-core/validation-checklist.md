# Embedded Validation Checklist

Maturity: draft
Scope: cross-project
Source: public migration closeout
Last reviewed: 2026-05-08

## Summary

Generic validation boundaries for embedded firmware tasks. Use this checklist
to avoid mixing build-only checks, flashing, monitor capture, and device tests
without explicit intent.

## Checklist

- Confirm whether the task is build-only, flash, monitor, or post-flash testing.
- Use project-local instructions for SDK paths, board names, ports, and test
  commands.
- Treat serial ports as shared resources; do not run monitor and tests against
  the same port in parallel.
- Keep flash and device-control actions bounded and explicit.
- Record skipped hardware checks before claiming completion.
- Prefer project-local or private domain skills for SDK-specific automation.

## Boundary

This entry is public knowledge. It deliberately omits vendor-specific wrapper
commands, local paths, private boards, and private troubleshooting cases.
