# Agent Governance

This repository uses agent-assisted maintenance for some issue triage,
documentation, workflow, and release-readiness work. The goal is not to make the
agent more autonomous. The goal is to make agent participation explicit,
reviewable, and limited by maintainer authority.

## Principles

- Agent proposes.
- Agent implements.
- CI validates.
- Human reviews.
- Human merges.
- Human releases.

## Roles

### Agent

An agent may:

- create candidate issues;
- collect evidence and suggest triage;
- prepare pull requests;
- update its own pull request branch;
- run or report validation;
- suggest follow-up issues.

An agent must not:

- merge to `main`;
- publish releases;
- modify repository settings;
- manage repository secrets;
- bypass required review or CI;
- present an unreviewed agent decision as a maintainer decision.

### Maintainer

The maintainer:

- accepts, rejects, defers, or redirects candidate issues;
- reviews pull request scope and diff;
- checks validation evidence;
- decides whether a pull request may merge;
- publishes releases.

## Automation Identity

Earlier maintenance work may have been performed by an agent operating through
the maintainer account. Agent-assisted maintenance should use a distinct
automation identity where practical.

The configured automation identity is the `agent-ecosystem-bot` GitHub App,
installed only on this repository with least-privilege permissions. Work is not
trusted only because it comes from the App. Agent-assisted issues and pull
requests must still state the actor boundary in the issue or pull request body,
and maintainer authority remains required for merge and release decisions.

## Required Labels

Use these labels for agent-assisted maintenance:

- `source:agent`: proposed or prepared by an agent-assisted workflow.
- `source:human`: proposed by a human maintainer or contributor.
- `triage:accepted`: accepted for implementation.
- `triage:rejected`: rejected as not planned.
- `triage:deferred`: valid but deferred.
- `triage:needs-human`: needs maintainer judgment before implementation.
- `review:needs-human`: requires human maintainer review before merge.
- `stack:allowed`: permits an intentionally stacked pull request to target a
  non-`main` base branch for review organization.

Additional scope or risk labels may be added later if the maintenance load
justifies them.

## Issue Triage Label Sync

The `Issue triage label sync` workflow mirrors the explicit
`Human Triage Decision` checklist in agent candidate issues into triage labels.
It does not make triage decisions. A maintainer records the decision in the
issue body, and automation keeps metadata consistent.

The workflow only runs for issues labeled `source:agent`. When exactly one
decision is checked:

- `Accepted` adds `triage:accepted`.
- `Rejected` adds `triage:rejected`.
- `Deferred` adds `triage:deferred`.
- `Needs human investigation` adds `triage:needs-human`.

The workflow removes conflicting `triage:*` labels and stale issue-level
`review:needs-human` after a clear decision is recorded. If multiple decisions
are checked, it fails without changing labels so the maintainer can correct the
issue body.

## Issue Requirements

Agent candidate issues should include:

- background and evidence;
- the agent hypothesis;
- a necessity assessment;
- non-goals;
- acceptance criteria;
- suggested validation;
- a human triage decision.

Rejected and deferred issues are useful records when they arise naturally. Do
not create artificial rejected issues only to demonstrate process maturity.

## Pull Request Requirements

Agent-assisted pull requests should include:

- actor information;
- linked issues;
- issue-to-change mapping;
- necessity assessment;
- scope control checks;
- validation tier and evidence, using the tiers in
  [Release process](release-process.md#validation-tiers);
- base branch and stack-safety declaration;
- rollback plan;
- human decision checklist.

Documentation-only changes may mark rollback details as "revert this pull
request." Changes to scripts, CI, installation, release metadata, or generated
runtime behavior should include more specific rollback notes.

By default, pull requests must target `main`. Stacked pull requests may be used
for review organization only when the PR explicitly declares it is intentionally
stacked and carries the `stack:allowed` label. A merged PR state alone does not
prove content landed on `main`, especially after squash merges or stacked-base
merges. Before merge, reviewers should confirm the base branch, expected files,
and whether the PR replaces or supersedes another PR. After merge, verify the
content reached `main` with a file-level compare or equivalent evidence.

## Runtime Memory Boundary

The root `.agents/` directory is checkout-local runtime memory for this
repository. It may be useful while an agent is working in one local clone, but
it is not a public fact source and must not be tracked in the public repository.

Durable public state belongs in GitHub issues and pull requests,
`docs/specs/**`, governance docs, release docs, changelog entries, release
notes, or curated `knowledge-hub/knowledge/**` entries. `docs/specs/**` should
record goals, non-goals, accepted scope, durable decisions, risks, acceptance
criteria, and completed evidence. It should not preserve local branch status,
waiting pull-request merge steps, pending hosted checks, branch publishing
steps, or duplicate issue-label dashboards as long-lived state.

## Cross-Repository Promotion

When agent-assisted work promotes a reusable lesson from private, project-local,
or local audit evidence into this public repository, the public issue or pull
request should reference the generic evidence summary and the public work
surface. It must not copy raw private logs, local paths, private repository
mappings, credentials, or sensitive audit details.

Before editing public files, the agent should:

- run the project context gate for each repository that will be read or written;
- record which repository is read-only evidence and which repository is the
  public write target;
- verify the write target root, branch, and `git status -sb`;
- confirm GitHub access is being used only for issue, pull request, branch, and
  validation workflows in scope;
- stop for ambiguity around write root, base branch, settings, secrets,
  rulesets, tags, releases, or other maintainer-controlled actions.

Use
[Public Promotion Checklist](../knowledge-hub/knowledge/standards/public-promotion-checklist.md)
for reusable promotion boundaries, and
[Long Session Phase Split](../knowledge-hub/knowledge/patterns/long-session-phase-split.md)
when the source work is large enough that spec, implementation, and closeout
should be separate reviewable phases.

## Repository Controls

The current repository control model is:

- agent-created changes use feature branches;
- root `.agents/` runtime memory is ignored and untracked;
- `main` requires pull requests through the `protect-main` repository ruleset;
- required release validation checks must pass before merge;
- the `PR base guard` workflow fails pull requests that target a non-`main`
  base without explicit stacked-PR markers;
- conversations must be resolved before merge;
- force pushes and branch deletion on the default branch are blocked;
- the ruleset has no bypass actors;
- merge and release authority stays with the maintainer.

Branch protection and repository rulesets are maintainer-controlled settings and
may be tightened as the automation identity matures.

## GitHub App Adoption

The configured GitHub App identity is `agent-ecosystem-bot`.

Initial repository permissions should be limited to the abilities actually
needed for issue and pull request preparation:

- repository contents: read/write for feature branches and pull request branch
  updates;
- issues: read/write for candidate issues and labels;
- pull requests: read/write for pull request creation and updates;
- checks, statuses, or actions: read only when the automation reads CI state.

Do not grant administration, secrets, members, deployments, release publishing,
or branch-protection modification permissions for the first phase.

The GitHub App private key, installation token, and repository secrets must not
be committed, pasted into issues or pull requests, or stored in project memory.
