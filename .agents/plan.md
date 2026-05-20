# Active Plan

Active Spec
- `docs/specs/accepted-stabilization-guardrails/spec.md`

Current Branch
- `codex/issue-65-cross-workspace-goal-guardrails`

Current Task
- PR-C / #65 Phase A: start generic high-risk evidence gate.

Session Status
- Public `main` and `origin/main` are at
  `5e217c9549a8436ab8e8b1a10a6aa400be6d0466`.
- Open public PRs were empty when this sequence started.
- Draft PR #70 is open for PR-A / #69.
- Draft PR #71 is open for PR-B / #65 Phase B/C.
- Accepted issue order: #69, #65 Phase B/C, #65 Phase A, #68, #66.
- Deferred and out of scope: #67, #56, #23, and README redesign.

Next Work
- Create `codex/issue-65-high-risk-evidence-gate` from PR-B.
- Add generic high-risk evidence-gate guidance without adding domain packs or
  specific firmware migration content.
- Run local validation and open draft PR-C with PR-B as the base branch.

Notes
- Do not move tags, publish or edit GitHub Releases, close or edit issues, push
  directly to `main`, merge PRs, mark PRs ready for review, or change repository
  settings without explicit maintainer approval.
- Do not use tracked `.agents` memory for repeated CI timestamp refresh commits.
- Do not introduce private overlay content, local-only paths, authentication
  material, or domain-specific incubator templates into this public repository.
