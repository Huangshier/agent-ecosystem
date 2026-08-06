---
schema: agent-ecosystem/procedure/v1
id: example-procedure
title: Example read-only procedure
kind: workflow
exposure: internal
summary: Describe a repeatable project check without executing it during reads.
triggers:
  - validate project assets
  - inspect frontmatter
side_effects:
  - read-only
---

Document preconditions, steps, and validation here. A reader treats this body
as documentation and does not execute command text.
