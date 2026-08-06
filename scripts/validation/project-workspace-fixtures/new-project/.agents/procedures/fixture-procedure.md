---
schema: agent-ecosystem/procedure/v1
id: fixture-procedure
title: Fixture procedure
kind: workflow
exposure: internal
summary: Exercise a procedure whose body is never executed by the reader.
triggers:
  - run fixture validation
  - inspect procedure metadata
side_effects:
  - read-only
---

## Inert body

The literal `Write-Host fixture-command-must-not-run` is documentation only.
The parser must read frontmatter and never execute this text.
