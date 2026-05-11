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
the maintainer account. Future agent-assisted maintenance should use a distinct
automation identity where practical.

The preferred long-term identity is a GitHub App installed only on this
repository with least-privilege permissions. Until that identity is active,
agent-assisted issues and pull requests should state the actor boundary in the
issue or pull request body.

## Required Labels

Use these labels for agent-assisted maintenance:

- `source:agent`: proposed or prepared by an agent-assisted workflow.
- `source:human`: proposed by a human maintainer or contributor.
- `triage:accepted`: accepted for implementation.
- `triage:rejected`: rejected as not planned.
- `triage:deferred`: valid but deferred.
- `triage:needs-human`: needs maintainer judgment before implementation.
- `review:needs-human`: requires human maintainer review before merge.

Additional scope or risk labels may be added later if the maintenance load
justifies them.

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
- validation evidence;
- rollback plan;
- human decision checklist.

Documentation-only changes may mark rollback details as "revert this pull
request." Changes to scripts, CI, installation, release metadata, or generated
runtime behavior should include more specific rollback notes.

## Repository Controls

The intended repository control model is:

- agent-created changes use feature branches;
- `main` requires pull requests;
- required validation must pass before merge;
- conversations should be resolved before merge;
- force pushes and branch deletion on protected branches should be disabled;
- merge and release authority stays with the maintainer.

Branch protection or repository rulesets are maintainer-controlled settings and
may be tightened as the automation identity matures.

## GitHub App Adoption

The preferred future automation identity is `agent-ecosystem-agent` or an
equivalent GitHub App.

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
