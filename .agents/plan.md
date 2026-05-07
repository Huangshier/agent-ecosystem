# Active Plan

Active Spec
- `none in public repository`

Current Task
- Local `v0.1.0` release validation is complete; next public work is maintainer
  review.

Session Status
- Public engineering memory remains English-first.
- Workflow Kernel files are present under `skills/`.
- Public installer/profile entrypoint exists.
- Recommended profile was validated against a temporary runtime target.
- A new project was bootstrapped from the temporary runtime install.
- Public-tree sensitive audit refresh found no high-risk matches.
- First-release Chinese entrypoint exists at `README.zh-CN.md`.
- Release readiness docs record installer fallback metadata and duplicate
  helper script review.
- Release validation workflow exists at `scripts/validate-release.ps1`.
- Release process guidance exists at `docs/release-process.md`.
- Latest local release validation passed with 12 pass, 0 fail, 0 warn, and
  1 deferred non-blocking behavior check.

Next Work
- Maintainer review.
- Re-run `scripts/validate-release.ps1` if review changes public release inputs.
- Push/tag/release only when explicitly requested.

Notes
- Do not store private mappings, local paths, or sensitive audit findings here.
