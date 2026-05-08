# Bilingual Public/Private Routing

Maturity: verified
Scope: cross-project
Source: manual
Last reviewed: 2026-05-08

## Summary

Route language by audience, repository boundary, and artifact type. Do not let a
single conversation language override public documentation policy or private
memory policy.

## Use When

- A workflow spans public and private repositories.
- The user conversation is in one language while public release artifacts use
  another language.
- Project memory, specs, release notes, and code identifiers need different
  language rules.

## Standard

- User-facing conversation should follow the user's current language when
  practical.
- Public community-facing artifacts should stay English-first unless the
  repository explicitly defines a translation path such as `README.zh-CN.md` or
  `docs/zh-CN/`.
- Project-local memory should follow the target project's `.agents/AGENTS.md`
  language policy.
- Private control docs and private overlay memory should stay in the private
  repository and use that repository's language policy.
- Code identifiers, commands, paths, APIs, file names, Markdown field labels,
  and raw error text may stay in English or their original form.
- Cross-repository work should run a context gate for each repository before
  writing files there.

## Public Boundary

Public artifacts may describe the routing rule generically. They must not
include private repository mappings, local machine paths, private overlay
details, or sensitive audit findings.

## Validation

- Release or review checks should verify that public docs link the policy and
  that public release notes do not rely on private context.
- Memory diagnostics may accept localized discovery headings while still
  preserving English-first public templates.
