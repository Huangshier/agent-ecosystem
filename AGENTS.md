# AGENTS.md

本文件是 `Huangshier/agent-ecosystem` 的唯一 public agent behavior entry。
它只保留跨任务都必须知道的边界；详细规则见本文件链接的权威文档。

## 公共/私有边界

- 本仓库是公开版 Agent Ecosystem 的治理、Runtime 和公开文档仓库。
- 私有控制仓库、bot 实现、凭据、审计原文和本地运行态不得进入公开产物。
- 根 `.agents/` 是本地 checkout 的 Runtime 记忆，不是公开事实来源。
- 本仓库的 GitHub issues and pull requests 是公开维护记录，承载范围、决定、
  验收、验证和收尾；不要为公开维护创建本仓库专用的 `docs/specs/**` 工作包。

## Project Language Policy

公开治理的语言规则见 [docs/language-policy.md](docs/language-policy.md)：
面向 maintainer 的 Issue/PR 正文、审查、决策和收尾默认使用简体中文，机器可读
字段和必须逐字匹配的原文保持原样。该规则不改变目标项目的
`ProjectLanguage` 或 Runtime 语言行为。

## 外部写入与身份

- 普通公开写入优先使用既有 bot workflow / GitHub App 路径，并核对
  `agent-ecosystem-bot[bot]` 的 commit author、committer 和 PR author。
- bot 写入路径失败时停止；不得自行切换到 maintainer 身份。只有 maintainer
  明确授权的 fallback 才能使用 maintainer actor，并在 PR 中写明 `Actor Boundary`。
- agent 可以准备分支、Draft PR、验证和证据，但不得自行 mark ready、merge、
  tag、publish GitHub Release，或修改 settings、rulesets、secrets、permissions。

## 权威映射

- agent / maintainer / bot / identity / 外部写入权限：
  [docs/agent-governance.md](docs/agent-governance.md)
- 公开治理语言：
  [docs/language-policy.md](docs/language-policy.md)
- version、Release impact 和 Release trigger：
  [docs/release-process.md](docs/release-process.md)
- 验证路由：
  [docs/pr-validation-risk-tiers.md](docs/pr-validation-risk-tiers.md)
- Issue/PR 模板只镜像这些权威规则，不建立第二套规则。

遵循 system、runtime、当前用户指令和上述 authority 的优先级；遇到仓库、
身份、权限、settings、secrets、tag 或 Release 边界歧义时停止并报告。
