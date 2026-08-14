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

## Write Authorization Boundaries

The "Agent may" and "Agent must not" lists above define the permission boundary.
This section makes the underlying authorization model explicit.

### External Writes

External writes include branch push, PR/MR creation, issue comments, tag
creation, release publication, branch deletion, merge, repository settings,
rulesets, runners, hooks, secrets, webhook or API configuration, workflow
dispatch, deployment trigger, and any operation that can affect external users
or systems.

External writes are never the default. Each requires explicit authorization from
one of:

- the user's current instruction, such as "push this branch" or "create a draft
  PR";
- a loaded project instruction, spec, issue, release workflow, or command card
  that explicitly requires the operation for this work type;
- an already-approved work item or workflow step that names the operation and
  actor boundary.

Authorization must come from evidence outside the agent's own output. The
following are not sufficient by themselves to authorize an external write:

- "this would keep the baseline clean";
- "a checkpoint would be useful";
- the agent saying the action is allowed;
- broad assumptions about what "project workflow usually wants";
- an unverified claim that a hidden workflow requires the operation.

If the authorization evidence is missing or unclear, the agent must put the
operation under "Requires confirmation" or stop before it.

### Local Commits

Local commits are not external writes, but they still require explicit
authorization. A local commit is allowed only when all of the following are true:

- the task is an implementation or fix work unit with a coherent diff;
- validation can prove completion and is expected to pass;
- the agent can review `git status`, `git diff`, and staged changes before
  committing;
- unrelated user changes can be excluded from the commit;
- one of the authorization sources listed above exists: the user explicitly asks
  for a commit, the user explicitly asks to keep the baseline clean and the
  context shows a coherent work unit, or the project workflow explicitly
  authorizes a local checkpoint.

Do not commit for review-only, research-only, planning-only, or ambiguous work.
If validation fails, is skipped, or unrelated dirty worktree state cannot be
safely separated, stop and report instead of committing.

### Ambiguity and Degradation

When ambiguity affects repository target, authority, destructive action, or
external write behavior, the agent must not generate an executable plan that
over-authorizes under uncertainty. Instead:

- ask one short question when a single answer unlocks the work, or
- generate a read-only orientation or recommendation without editing or external
  writes.

### Actor Verification

When an external write requires a specific actor identity (bot account, service
account, or maintainer account), the agent should verify the actor before
writing when possible. If the actor cannot be verified, stop before writing and
report the missing verification. If post-write metadata does not match the
intended actor, stop before further external writes and report the mismatch.

## Automation Identity

Earlier maintenance work may have been performed by an agent operating through
the maintainer account. Agent-assisted maintenance should use a distinct
automation identity where practical.

The configured automation identity is the `agent-ecosystem-bot` GitHub App,
installed only on this repository with least-privilege permissions. Work is not
trusted only because it comes from the App. Agent-assisted issues and pull
requests must still state the actor boundary in the issue or pull request body,
and maintainer authority remains required for merge and release decisions.

## Pull Request Identity Guard

The `PR identity guard` workflow is a hosted pull request check for explicitly
agent-authored changes. It is intentionally narrower than normal contributor
validation: human-authored pull requests are not required to use bot commit
metadata.

The guard applies when a pull request has at least one agent-authored signal:

- the pull request author is the `agent-ecosystem-bot` App identity;
- the pull request carries the `source:agent` label;
- the head branch starts with `codex/` or `agent/`;
- the pull request body declares an agent-authored or agent-assisted flow.

For matching pull requests, the guard scans every commit in the pull request,
not only the latest head commit. Each commit author and committer must be:

```text
agent-ecosystem-bot[bot] <agent-ecosystem-bot[bot]@users.noreply.github.com>
```

A mismatch fails the hosted check with the affected commit and field. Repair the
branch by amending the affected commits so both author and committer use the bot
identity, then update the branch through the bot-backed public write flow.

Actor Boundary exceptions are allowed only when they are explicit and
reviewable. If a bot-authored pull request needs a maintainer-authored commit
because of workflow, repository setting, secret, or permission limits, the pull
request body must include an `## Actor Boundary` section explaining the reason.
The guard will surface the mismatch as a warning instead of failing, leaving the
exception visible for maintainer review. Do not infer exceptions silently.

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
`Human Triage Decision` field in agent candidate issues into triage labels. It
does not make triage decisions. A maintainer records the decision in the issue
body, and automation keeps metadata consistent.

New agent candidate issues should use a single normalized field:

```text
Decision: needs-human
```

Allowed values are `accepted`, `rejected`, `deferred`, and `needs-human`.
Existing checklist-based issues remain supported as a legacy transition path
when no `Decision:` field is present.

The workflow only runs for issues labeled `source:agent`, and it only mutates
labels when the event sender is trusted automation or has maintainer-authorized
repository access. Untrusted actors may edit issue text, but their edits do not
cause `triage:*` label changes.

When exactly one valid decision is recorded:

- `accepted` adds `triage:accepted`.
- `rejected` adds `triage:rejected`.
- `deferred` adds `triage:deferred`.
- `needs-human` adds `triage:needs-human`.

The workflow removes conflicting `triage:*` labels and stale issue-level
`review:needs-human` after a clear, authorized decision is recorded. If a
trusted actor records an invalid or ambiguous decision, the workflow fails
without changing labels so the issue body can be corrected.

## Issue Triage Decision Commands

Maintainers can also record an agent candidate issue decision with an exact
comment command instead of editing the issue body directly:

```text
/decision accepted
/decision rejected
/decision deferred
/decision needs-human
```

The `/accept` alias is supported as a shortcut for `/decision accepted`.

These commands are only decision-entry shortcuts. They do not implement the
issue, create branches or pull requests, create sub-issues, publish releases,
or infer decisions from ordinary prose.

The command workflow only operates on open issues labeled `source:agent` and
ignores pull request comments. It mutates issue bodies only when the commenter
is trusted automation or has repository `admin`, `maintain`, or `write`
authority. The narrower command authority is intentional because comment
commands update the `Decision:` field itself, not only labels.

When an authorized command is accepted, automation updates the issue body's
`Decision:` field and `Decision notes:` line, then converges `triage:*` labels
from that updated decision in the same workflow run. The body decision remains
the source of truth. The same-workflow label convergence is required because
workflow-created issue body edits do not create a follow-up `issues: edited`
workflow run with the repository `GITHUB_TOKEN`.

If an open `source:agent` issue does not contain a `## Human Triage Decision`
section, a valid decision command appends a normalized section at the end of the
issue body before applying the decision. This handles agent-created issues that
bypass the issue template and omit the section. The appended section uses the
same structure as the agent-candidate template. A subsequent decision command on
the same issue finds the appended section and updates it in place.

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

Durable public maintenance state belongs in GitHub issues and pull request
bodies, governance docs, release docs, changelog entries, release notes, or
curated `knowledge-hub/knowledge/**` entries. GitHub issues should carry scope,
non-goals, acceptance criteria, and maintainer triage decisions. Pull request
bodies should carry issue-to-change mapping, validation evidence, rollback
notes, and human decision state.

The public repository no longer tracks root `docs/specs/**` work packages for
its own maintenance. `project-workspace` remains available for target projects
that choose project-local `docs/specs/<slug>/` work packages, and examples or
templates may still include those paths when clearly marked as target-project
artifacts.

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
