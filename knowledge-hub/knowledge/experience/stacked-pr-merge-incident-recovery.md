# Stacked PR Merge Incident Recovery

Maturity: verified
Scope: cross-project
Source: public post-v0.4.3 maintenance review
Last reviewed: 2026-05-21

## Summary
When a stacked PR is accidentally merged into another feature branch instead of
`main`, repair the chain by landing a replacement PR on `main` and then applying
the remaining PRs' net scoped diffs to latest `main`. Avoid replaying old
runtime memory state commits.

## Keywords
stacked-pr, merge-incident, replacement-pr, pull-request-checks, agents-memory,
issue-closeout, force-with-lease

## Problem Pattern
- A stacked PR can be marked merged by GitHub even when its base was another
  feature branch rather than `main`.
- The merged PR cannot be reopened and merged again into `main`.
- Later stacked PR branches may carry both their intended implementation diff
  and old runtime status narration from the previous branch topology.

## Recovery Rules
- Do not revert `main` when `main` was not polluted.
- Create a replacement PR from latest `main` for the accidentally missed layer.
- For remaining stacked PRs, prefer applying each PR's net scoped diff from its
  original base commit to its original head onto latest `main`.
- Do not replay old runtime-memory status commits when they only describe the
  prior stacked branch topology.
- Keep checkout-local memory concise and current; use specs and tasks only for
  durable phase state.

## CI Checks
- After a base retarget or force-with-lease update, confirm check results belong
  to the intended head commit.
- If a PR shows no checks for the intended head, a successful manual workflow
  run validates the branch but may not satisfy required PR checks.
- A no-op amend plus `git push --force-with-lease` can create a new pull request
  synchronize event and restore required check reporting.

## Issue Closeout
- `Refs #...` links an issue but does not close it.
- Use `Closes #...` or `Fixes #...` when automatic closeout is intended.
- If closeout wording was not used, close completed issues manually only after
  maintainer authorization.

## Prevention Rule
Before merging stacked maintenance work, verify the PR base, the intended target
branch, and whether any later branch contains stale runtime memory commits from
an older stack topology.
