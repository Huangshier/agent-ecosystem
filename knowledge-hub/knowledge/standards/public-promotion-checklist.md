# Public Promotion Checklist

Maturity: verified
Scope: cross-project
Source: promoted
Last reviewed: 2026-05-24

## Rule

Promote only reusable, public-safe knowledge from project-local or private
evidence into public artifacts. The public record should describe the generic
lesson, required evidence, write boundary, validation, and review path without
copying private logs, machine paths, access material, or repository mappings.

## Applies To

- Agent-assisted issues and pull requests that originate from private or
  project-local evidence.
- Public knowledge hub entries, standards, patterns, docs, release notes, and
  project templates.
- Multi-repository work where one repository is evidence-only and another is
  the public write target.
- Public follow-ups from local audits, retrospectives, long debugging sessions,
  or private control-plane work.

## Does Not Apply To

- Purely private remediation that should stay in a private overlay.
- Project-local `.agents/` memory that is not a public source of truth.
- Raw session transcripts, sensitive access material, private logs, or local
  environment setup.
- Maintainer-only repository settings, release publication, secrets, or access
  management.

## Checklist

- The public artifact states the reusable lesson, not the private incident.
- The source evidence is summarized at the right granularity; raw private
  material stays outside the public repository.
- The target repository root, branch, and write boundary were verified before
  editing.
- Any source repository, private checkout, or local audit folder is treated as
  read-only evidence unless the maintainer explicitly authorizes writes there.
- The issue or work spec records non-goals for secrets, private paths,
  repository mappings, settings, rulesets, tags, releases, and automation
  access material.
- The pull request links an accepted issue or records why the scope is already
  authorized.
- Validation matches the touched surface and records skipped checks before the
  work is claimed complete.
- The rollback plan is public-safe and does not depend on private state.
- Human review remains required before merge, release, or settings changes.

## Permission Preflight

Before making public changes from private or project-local evidence:

1. Run a context gate for each repository that will be read or written.
2. Record which root is read-only evidence and which root is the write target.
3. Check `git status -sb` and the current branch in the write target.
4. Confirm GitHub authentication is sufficient for issues, pull requests, and
   branch pushes, but does not imply permission to manage secrets, settings,
   rulesets, tags, or releases.
5. Stop if the intended write root, base branch, issue scope, or authorization
   boundary is ambiguous.

## Public Record Shape

Use a public issue, work spec, or pull request body to record:

- public summary of the evidence;
- accepted scope and non-goals;
- files or knowledge surfaces changed;
- validation tier and evidence;
- public/private boundary check;
- rollback plan;
- human decision checklist.
