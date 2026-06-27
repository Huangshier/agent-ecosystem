# Knowledge Catalog

This catalog is the human and agent reading map for the public knowledge hub.
Use it before opening individual knowledge files.

## Reading Rule

- Start here when a task may benefit from reusable cross-project knowledge.
- Open only the entries that match the current task.
- Use `knowledge/experience/index.json` and `scripts/search_experience.ps1` for
  scriptable experience search.
- Treat this catalog as the curated reading map; do not use it as generated
  registry state.

## Knowledge Layers

| Layer | Purpose | Open when |
| --- | --- | --- |
| `knowledge/experience/` | Reusable lessons from toolchains, host environments, shells, build systems, caches, ports, permissions, path handling, and workflow failures. | You see a recurring failure shape or host/tooling symptom. |
| `knowledge/patterns/` | Reusable engineering workflows that coordinate agent work across context loading, planning, implementation, and validation. | You need a proven work sequence, not a troubleshooting case. |
| `knowledge/standards/` | Cross-project rules and boundaries that should stay stable across projects and releases. | You need to decide where content belongs or how public artifacts should behave. |
| `knowledge/domain-packs/` | Optional public-safe domain knowledge bundles that start as Markdown before becoming skills. | A task needs reusable domain vocabulary, checklists, or boundaries without private assumptions. Read [Domain pack governance](../docs/domain-pack-governance.md) before changing lifecycle, manifest, promotion, safety, validation, or profile boundaries. |

## Current Entries

### Experience

- [Windows PowerShell Command Chaining](knowledge/experience/windows-powershell-command-chaining.md)
  - Maturity: verified
  - Scope: cross-project
  - Use when: PowerShell command chaining or host shell parsing behaves
    differently from expected.
- [Stacked PR Merge Incident Recovery](knowledge/experience/stacked-pr-merge-incident-recovery.md)
  - Maturity: verified
  - Scope: cross-project
  - Use when: a stacked pull request landed on a feature branch instead of the
    default branch, or PR checks need recovery after retargeting.

### Patterns

- [Context Gate to Spec to Validation Loop](knowledge/patterns/context-gate-spec-validation-loop.md)
  - Maturity: verified
  - Scope: cross-project
  - Use when: a non-trivial task needs durable intent, bounded execution, and
    validation evidence.
- [Long Session Phase Split](knowledge/patterns/long-session-phase-split.md)
  - Maturity: verified
  - Scope: cross-project
  - Use when: large, restart-prone, or evidence-heavy work should be split into
    spec, implementation, and closeout phases.
- [Staged Refactor Execution](knowledge/patterns/staged-refactor-execution.md)
  - Maturity: draft
  - Scope: cross-project
  - Use when: a large refactor needs to be broken into independent, reviewable
    stages with per-stage validation and rollback boundaries.
- [Issue Decomposition](knowledge/patterns/issue-decomposition.md)
  - Maturity: draft
  - Scope: cross-project
  - Use when: a complex issue or task spans multiple modules, concerns, or
    review cycles and needs independent, verifiable sub-tasks.
- [Error Diagnosis Framing](knowledge/patterns/error-diagnosis-framing.md)
  - Maturity: draft
  - Scope: cross-project
  - Use when: an agent encounters an error and needs to present it to the user
    with structured context for actionable diagnosis.
- [Test Strategy](knowledge/patterns/test-strategy.md)
  - Maturity: draft
  - Scope: cross-project
  - Use when: a project needs a documented testing approach, test level
    priorities, and coverage targets before investing in test infrastructure.
- [Test-Driven Development](knowledge/patterns/test-driven-development.md)
  - Maturity: draft
  - Scope: cross-project
  - Use when: desired behavior can be specified as observable inputs and outputs
    before implementation, and the project benefits from writing failing tests
    first.
- [Eval-Driven Skill Iteration](knowledge/patterns/eval-driven-skill-iteration.md)
  - Maturity: draft
  - Scope: cross-project
  - Use when: a skill's output quality needs data-driven measurement,
    comparison against baseline, or structured improvement across versions.

### Standards

- [Public Knowledge Boundary](knowledge/standards/public-knowledge-boundary.md)
  - Maturity: verified
  - Scope: cross-project
  - Use when: deciding whether a knowledge item belongs in the public hub,
    private overlay, or project-local memory.
- [Bilingual Public/Private Routing](knowledge/standards/bilingual-public-private-routing.md)
  - Maturity: verified
  - Scope: cross-project
  - Use when: deciding language routing across conversation, public artifacts,
    project memory, and private overlay work.
- [Public Promotion Checklist](knowledge/standards/public-promotion-checklist.md)
  - Maturity: verified
  - Scope: cross-project
  - Use when: promoting reusable lessons from project-local or private evidence
    into public issues, PRs, docs, templates, or knowledge entries.

### Domain Packs

- [Domain Pack Governance](../docs/domain-pack-governance.md)
  - Maturity: verified
  - Scope: public governance
  - Use when: changing domain-pack lifecycle, manifest, promotion criteria,
    public-safety checks, release-validation expectations, or profile boundary.
- [Embedded Core](knowledge/domain-packs/embedded-core/catalog.md)
  - Maturity: draft
  - Scope: cross-project
  - Use when: firmware build, flash, monitor, or device validation tasks need
    public-safe boundaries before project-local or private domain automation.

## Maintenance

- Add new public knowledge only after confirming it is generic and reusable.
- Keep private mappings, local machine paths, and project-only facts out of this
  public hub.
- Update this catalog when adding, moving, deprecating, or renaming knowledge
  entries.
- Rebuild `knowledge/experience/index.json` after editing experience files.
