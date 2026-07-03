# Claude Code Guardrails

这些 guardrails 是 project-bootstrap 生成 Claude Code 项目的模板可靠性
contract。它们帮助 agent 在继续工作前发现项目入口、上下文、边界或授权信息缺失。

它们不是 security sandbox、安全权限隔离模型，也不是自动授权外部写入的机制。项目仍然
需要声明允许的外部写入路径；review、merge、tag 和 release 决策仍由维护者负责。

## 必须感知的内容

Claude Code 执行工作前应确认这些 surface：

- `CLAUDE.md` 已加载项目入口。
- 存在时已考虑 `AGENTS.md`、`.agents/AGENTS.md`、`.agents/process.txt`
  和 `.agents/plan.md`。
- memory refresh、upgrade、reset 或 migration 前，已检查项目记忆语言和
  `.agents/hub.lock.json` 状态。
- public 与 private 内容保持正确边界。
- 外部写入符合当前 write authorization profile。
- 危险 memory refresh 或 reset 模式需要明确确认。
- 缺少权限、缺少上下文、写入路径错误或 scope 不确定时，应停在
  `needs-human` 等 stop point，而不是静默继续。
- raw artifacts 仅保留在 local 或 private 层，除非明确准备 public-safe 摘要。

## Write Authorization Profiles

默认 profile 是 `local-only`：当用户或项目指令授权时允许本地文件工作；外部写入需要
明确确认。

`public-contributor` profile 保持普通公开协作路径可用：issue、fork pull request、
CI 和 maintainer review 不需要 bot 身份。

有声明自动化身份或仓库特化 workflow 的项目，可以定义更严格的 maintenance profile。
该 profile 是项目特化规则，不是 project-bootstrap 的通用要求。

`profile.json` 给出 release validator 检查的 deterministic profile 结构。
