# Memory Diagnose Structural Diagnostics Design

Status: design boundary for issue #155 Part B.

This document records the public-safe design boundary for future structural
diagnostics in `skills/memory-governance/scripts/memory_diagnose.ps1`. PR #160 completed #155 Part A by connecting `workflow-spec-lite` phase-close guidance
to the existing read-only diagnosis helper. Part B remains about what the
helper may detect later, how to avoid noisy heuristics, and what evidence
should exist before implementation.

This document is not an implementation plan for the current release. It does
not change `memory_diagnose.ps1` behavior.

## Goals

- Define the structural memory problems that future diagnostics may detect.
- Keep future checks reviewable, conservative, and fixture-driven.
- Preserve the helper's read-only contract and JSON/human output shape.
- Require staged implementation so high-risk heuristics do not land without
  public-safe positive and negative fixtures.
- Make false-positive risk explicit before any new finding code is added.

## Non-Goals

- Do not implement Completed list growth detection in this design PR.
- Do not implement information-density heuristics in this design PR.
- Do not change `LargeFileLineThreshold`.
- Do not change current `memory_diagnose.ps1` severity choices or output
  behavior.
- Do not infer user intent from private project history, private overlay
  content, or local review evidence.
- Do not add repository rulesets, hooks, or mandatory pre-commit behavior.

## Current Baseline

`memory_diagnose.ps1` is a read-only helper. Current checks focus on:

- missing `.agents` scaffolds;
- large hot memory files by line count;
- history-like language in `process.txt`;
- session-log or task-list language in `notes.md`;
- durable task checklist shape in `plan.md`;
- missing active `docs/specs/**` references;
- mismatch between active spec references in `process.txt` and `plan.md`;
- missing context discovery metadata.

Those checks are useful but mostly line-count, keyword, and reference based.
#155 Part B should add structure-aware diagnostics only after the repository has
reviewed deterministic examples and false-positive boundaries.

## Candidate Diagnostic Families

Future implementation may add checks in these families. Names below are
descriptive design labels, not committed public finding codes.

| Family | Example Signal | Initial Severity | Primary Risk |
| --- | --- | --- | --- |
| Completed list growth | `process.txt` carries many historical completed entries instead of a compact current-state summary. | `info` | A project may intentionally keep a short recent changelog in process memory. |
| Information-density pressure | `process.txt` or `plan.md` has many bullets, nested sections, or repeated evidence blocks while staying below the line threshold. | `info` | Simple line or bullet counts can penalize well-structured but temporarily busy phases. |
| Stable facts mixed with runtime state | `notes.md` contains active PR state, current branch state, checkbox tasks, or "next step" language. | `warning` only after strong evidence | Some durable decisions mention an issue or PR as evidence, not as live state. |
| Spec duplication | `.agents/plan.md` or `.agents/process.txt` copies detailed `docs/specs/**/tasks.md` content instead of pointing to it. | `warning` after fixture coverage | Some small projects may not use specs and may legitimately keep a short checklist. |
| Stale phase-close evidence | Memory still lists completed hosted-check waits, ready-for-review actions, or prior PRs as active. | `info` | A PR may remain intentionally active for review after checks pass. |

## Detection Principles

- Prefer structural signals over broad word matching.
- Require at least one positive fixture and one negative fixture for each new
  finding family before implementation.
- Start new structural diagnostics as `info` unless the finding is
  unambiguous and already covered by existing memory routing rules.
- Keep recommendations actionable and routing-specific: compress, move to
  `docs/specs/**`, move to `.agents/context/**`, or record an intentional
  deferral.
- Avoid language-specific prose assumptions unless the check already has
  localized metadata support.
- Do not make a single count threshold the only signal when section structure
  or routing context can reduce false positives.
- Preserve deterministic behavior. The helper should not call external models,
  rely on local private state, or inspect untracked private evidence.

## Fixture Matrix

Future implementation PRs should add public-safe fixtures before adding or
changing detection logic. Fixtures should be small synthetic projects under a
release-validation scratch directory or a tracked validation fixture directory.

| Fixture | Expected Result | Purpose |
| --- | --- | --- |
| Fresh bootstrap project | No new structural findings | Prevent regressions for default templates. |
| Compact active phase | No completed-list finding | Avoid penalizing a normal short process snapshot. |
| Process history backlog | Completed-list or density finding | Prove historical entries are detected. |
| Notes durable evidence | No runtime-state finding | Allow stable facts that cite an issue or PR as evidence. |
| Notes live task state | Stable/runtime mixing finding | Detect active branch, next-action, or checkbox state in notes. |
| Spec pointer only | No spec-duplication finding | Allow session-local pointers to `docs/specs/**`. |
| Copied task list | Spec-duplication finding | Detect duplicated long-lived task lists in hot memory. |

Each fixture should assert the finding code, severity, path, and recommendation
shape. Negative fixtures should prove that concise current-state memory does
not trigger a finding.

## Staged Implementation Plan

1. Design boundary PR:
   - publish this document;
   - link it from memory-governance documentation;
   - add release-validation required-text coverage for the design boundary;
   - do not change diagnosis behavior.
2. Fixture PR:
   - add public-safe positive and negative fixtures for one diagnostic family;
   - keep `memory_diagnose.ps1` behavior unchanged;
   - validate fixture readability and expected outcomes separately from
     detection logic.
3. First detection PR:
   - implement one diagnostic family only;
   - keep the new finding at `info` unless evidence supports `warning`;
   - prove default bootstrap projects remain clean;
   - run full release validation.
4. Calibration PR:
   - adjust thresholds or severity only with evidence from fixtures and real
     public-safe examples;
   - avoid mixing calibration with unrelated memory-governance features.
5. Follow-up families:
   - repeat the fixture-first and single-family implementation pattern for each
     additional structural diagnostic.

## Acceptance For Future Implementation

Future implementation PRs should demonstrate:

- default en and zh-CN bootstrap projects still produce zero findings;
- each new finding has at least one positive and one negative fixture;
- finding codes are stable and documented in PR body or helper tests;
- recommendations name the target memory routing surface;
- false-positive examples are documented and either pass cleanly or have a
  deliberate deferral rationale;
- `git diff --check` and `scripts/validate-release.ps1` pass.

## Rollback Boundary

This design can be rolled back by reverting the documentation and validator
required-text checks. Later implementation PRs should remain independently
revertible: one diagnostic family per PR, fixture evidence included, and no
unrelated changes to project-bootstrap, workflow-spec-lite, or release
publication paths.
