# Pull Request（Pull Request）

解释性标题和正文默认使用简体中文；`paths`、commands、code/API/config
fields、labels、state 以及其他机器可读值保留英文或原文。

## Actor

- Proposed by: agent / human
- Implemented by: agent / human
- Reviewed by: pending / human / second-agent
- Merge authority: maintainer
- Actor Boundary: bot-backed public write flow / maintainer fallback (reason required)

## Linked Issues

Refs #<number>

<!-- 只有确实应在 merge 后自动关闭 Issue 时才使用 `Fixes #<number>`。 -->

## Issue-To-Change Mapping

| 变更 | Source issue | Required? | Validation |
|---|---:|---|---|
|  |  | yes/no |  |

## Necessity Assessment

- Why this is needed：
- Risk if not fixed：
- Why now：
- Alternatives considered：

## Scope Control

- [ ] No unrelated opportunistic edits
- [ ] Public/private boundary checked
- [ ] Documentation updated if needed
- [ ] Release metadata updated if needed

Release impact: none

<!-- Allowed values: none / patch / minor / major。详见 docs/release-process.md。 -->

## Base / Stack Safety

- Target base branch: `main`
- Is this intentionally stacked? yes/no
- If yes, why is a non-main base required?
- Before merge, confirm expected files will land on `main`.

## Validation

- Validation tier：
- Affected-surface command(s)：

```text
# command output summary
```

## Rollback Plan

- Revert commit：
- Files affected：
- User-facing compatibility risk：
- Safe rollback window：

## Human Decision

- [ ] Maintainer accepted scope
- [ ] Maintainer reviewed diff
- [ ] Maintainer verified CI
- [ ] Maintainer approved merge
