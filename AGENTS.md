# AGENTS.md

本文件是 `Huangshier/agent-ecosystem` 的唯一 public agent behavior entry。
它只保留跨任务都必须知道的边界；详细规则以本文件链接的 authority 为准。

## Public / Private Boundary

- 本仓库是 public Agent Ecosystem 的治理、Runtime 和公开文档仓库。
- private control repo、bot 实现、凭据、审计原文和本地运行态不得进入
  public 产物。
- 根 `.agents/` 是 checkout-local runtime memory，不是 public fact source。
- 本仓库的 GitHub issues and pull requests 是公开维护记录，承载范围、决定、
  验收、验证和 closeout；不要为 public maintenance 创建本仓库专用的
  `docs/specs/**` work package。

## Project Language Policy

公开治理的语言规则见 [docs/language-policy.md](docs/language-policy.md)：
maintainer-facing Issue/PR body、review、decision 和 closeout 默认使用简体
中文，机器可读字段和必须逐字匹配的原文保持原样。该规则不改变
target-project 的 `ProjectLanguage` 或 Runtime language behavior。

## External Writes and Identity

- 普通公开写入优先使用既有 bot workflow / GitHub App 路径，并核对
  `agent-ecosystem-bot[bot]` 的 commit author、committer 和 PR author。
- bot 写入路径失败时停止；不得自行切换到 maintainer 身份。只有 maintainer
  明确授权的 fallback 才能使用 maintainer actor，并在 PR 中写明 `Actor Boundary`。
- agent 可以准备 branch、Draft PR、验证和证据，但不得自行 mark ready、merge、
  tag、publish GitHub Release，或修改 settings、rulesets、secrets、permissions。

## Authority Map

- agent / maintainer / bot / identity / external-write authority：
  [docs/agent-governance.md](docs/agent-governance.md)
- public governance language：
  [docs/language-policy.md](docs/language-policy.md)
- version、Release impact 和 Release trigger：
  [docs/release-process.md](docs/release-process.md)
- validation routing：
  [docs/pr-validation-risk-tiers.md](docs/pr-validation-risk-tiers.md)
- Issue/PR 模板只镜像这些 authority，不建立第二套规则。

遵循 system、runtime、当前用户指令和上述 authority 的优先级；遇到仓库、
身份、权限、settings、secrets、tag 或 Release 边界歧义时停止并报告。
