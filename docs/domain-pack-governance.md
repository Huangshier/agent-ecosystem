# Domain Pack Governance

This document is the authoritative public governance entrypoint for domain
packs in Agent Ecosystem.

Domain packs are optional, public-safe knowledge bundles for recurring
technical domains. They may begin as Markdown catalogs, checklists, boundaries,
or examples. A domain pack becomes installable public content only after a
separate accepted issue and pull request updates the relevant profile behavior
and validation. This document does not enable that expansion by itself.

## Scope

This governance applies to public domain-pack content under
`knowledge-hub/knowledge/domain-packs/` and to any future public skill or
installable package derived from that content.

It does not apply to:

- private overlays;
- project-local `.agents/` memory;
- project-specific `docs/specs/` work packages;
- private domain skills;
- local hardware, SDK, access-material, or machine-specific automation.

Private or environment-specific domain automation belongs outside this public
repository unless it has been reduced to generic, public-safe guidance.

## Lifecycle

Domain-pack maturity is explicit. A lifecycle state records evidence; it does
not automatically change installer behavior.

| State | Meaning | Allowed form | Exit condition |
| --- | --- | --- | --- |
| `draft` | Early public-safe notes, vocabulary, or checklist content. | Markdown catalog or checklist. | Reused enough to justify incubation. |
| `incubating` | Repeated use is visible, but interfaces and validation are still changing. | Markdown plus examples or fixtures. | Stable inputs, outputs, stop rules, and validation evidence exist. |
| `validated` | Public-safe success and failure paths can be exercised without private assumptions. | Markdown plus fixtures, examples, or validator coverage. | Promotion evidence is complete and maintainer review agrees it is candidate skill content. |
| `promotable` | The pack is eligible for a later PR that turns stable parts into a public skill or installable content. | Markdown, fixtures, and a promotion proposal. | A separate accepted expansion issue authorizes installer/profile changes. |
| `installable` | Future state for content intentionally included by one or more public profiles. | Skill, package, or profile-managed bundle. | Release validation and profile documentation cover the install behavior. |
| `deprecated` | The pack is obsolete, replaced, or no longer safe to recommend. | Archived Markdown with replacement or removal notes. | Removal or replacement is complete in a later scoped PR. |

State changes should be reviewable in Git history and should cite the evidence
that justified the transition. Moving to `promotable` or `installable` requires
maintainer approval through a separate issue or pull request.

## Minimum Manifest Fields

When a new domain pack is proposed, or when an existing pack changes lifecycle
state, its catalog or manifest should include these fields. Existing draft
Markdown entries may converge to this shape on their next substantive update;
this governance pass does not promote or rewrite them automatically.

```yaml
name:
summary:
maturity:
scope:
owner:
last_reviewed:
source:
public_safety:
validation:
promotion_evidence:
private_assumption_check:
```

Field guidance:

- `name`: stable package name in kebab-case.
- `summary`: short statement of the reusable domain need.
- `maturity`: one lifecycle state from this document.
- `scope`: expected reuse boundary, such as `cross-project` or a narrower
  public-safe scope.
- `owner`: maintainer or group responsible for review.
- `last_reviewed`: ISO date of the last governance review.
- `source`: public evidence source, issue, PR, release note, or migration
  record that can be safely shared.
- `public_safety`: short statement of why the content is safe for the public
  repository.
- `validation`: commands, fixtures, examples, or manual checks that prove the
  content can be used without private assumptions.
- `promotion_evidence`: links or notes showing repeated successful reuse and
  stable workflow shape.
- `private_assumption_check`: explicit confirmation that private paths, access
  material, repository names, hardware-only checks, and machine-specific
  assumptions are absent or isolated outside the public pack.

## Promotion Criteria

A domain pack can be considered for promotion only when all criteria are met:

- It has been reused successfully in at least two independent projects or by
  two independent maintainers.
- Inputs, outputs, stop rules, and validation commands are stable enough to
  document without private environment assumptions.
- Public-safe success and failure fixtures, examples, or equivalent review
  evidence exist.
- It does not depend on private access material, local-only paths, private
  repository names, hardware-specific access, or maintainer-only machine state.
- SDK-specific or vendor-specific automation is either absent or isolated in a
  private overlay.
- The release validator can pass in a clean public environment without the
  private overlay.
- Maintainer review accepts that promotion is necessary, not merely convenient.

Promotion to `promotable` records readiness for a future implementation issue.
It does not by itself create a public skill, add installable content, or change
profiles.

## Public-Safety Checklist

Before a domain pack changes state or becomes a promotion candidate, review the
diff against this checklist:

- No private paths, home-directory paths, drive-specific paths, or local runtime
  manifests.
- No sensitive access material, private certificates, login screenshots, or
  access-control identifiers.
- No private repository names, internal hostnames, customer names, or migration
  mappings.
- No machine-specific assumptions such as fixed ports, fixed toolchain
  locations, user-specific environment variables, or maintainer-only setup.
- No hardware-only validation as the only proof path. Hardware work may be
  described, but public validation must have a safe fallback such as fixtures,
  examples, dry-run checks, or explicitly recorded manual deferral.
- No SDK-specific automation enters the public kernel unless it is generic,
  documented, fixture-backed, and separately approved for public release.
- No sensitive audit findings or private incident details.
- No generated runtime state, temporary scratch data, or local project memory.

If any item fails, keep the content in a private overlay, project-local memory,
or a narrower private skill until it can be generalized safely.

## Release-Validation Expectations

Governance-only documentation changes must run the Tier 2 validation path from
the release process:

```powershell
git diff --check
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\validate-release.ps1 -ScratchRoot <scratch>
```

Future PRs that create installable domain-pack content must add validation for:

- manifest or catalog fields required by this document;
- public-safe fixture or example coverage for expected success and failure
  paths;
- knowledge catalog links and release documentation updates;
- installer profile matrix behavior, if a public profile changes;
- absence of private paths, sensitive access material, generated runtime state, and
  private-overlay assumptions.

Hosted release validation remains a hard gate for pull requests to `main`.
Maintainer approval remains required before merge or release.

## Profile Boundary

Post-cutover public profile behavior:

- `minimal` installs bootstrap support and public knowledge hub templates; a
  fresh bootstrap produces a minimal C3.3 workspace.
- `recommended` installs the active C3.3 Runtime (`project-bootstrap` +
  `project-workspace`), project workspace templates/schemas, and the public
  knowledge hub.
- `full` currently installs the same public content as `recommended`.
- `dev` currently installs the same public content as `recommended`.

`recommended` / `full` / `dev` are the only C3.3 Runtime authority after the
one-time default cutover. The `c3-3-candidate` profile has been removed and no
compatibility alias or second default exists. The retired
`project-context-gate`, `memory-governance`, and `workflow-spec-lite` Skills are
no longer installed or newly bridged by any public profile.

The `full` and `dev` names remain reserved for future public domain packs and
developer maintenance tooling. A domain pack reaching `installable` maturity is
not enough to change those profiles automatically. Profile expansion requires a
later accepted issue and scoped PR that updates installer behavior,
documentation, release validation, and rollback notes together.

Issue #56 authorizes this governance document only. It does not authorize a new
public domain pack, `embedded-core` promotion, or any `full` / `dev` profile
behavior change.

## Relationship To Existing Content

The existing `embedded-core` Markdown content remains a draft, knowledge-first
domain pack. It is not a scriptable public skill and is not installed by any
extra profile behavior. Future edits may align its metadata with the manifest
fields above, but doing so should not be treated as promotion without the
separate evidence and approval gates described here.