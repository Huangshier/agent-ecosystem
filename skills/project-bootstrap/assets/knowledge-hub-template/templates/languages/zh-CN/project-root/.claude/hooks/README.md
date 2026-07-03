# Claude Code Guardrail Hooks

`.claude/settings.json` 为 `SessionStart`、`PreToolUse` 和 `Stop` 生命周期事件
注册 `guardrail.ps1`。runner 从 stdin 读取事件 JSON，只向 stdout 返回 Claude Code
需要的最小结构化判断；不会持久化 hook 输入、transcript 或 event ledger。

本 README 是运行维护文档，不由 `CLAUDE.md` 导入。settings 文件负责激活 runtime；
`CLAUDE.md` 继续加载项目上下文和静态 guardrails contract，这些内容只由 runtime
校验，不会被 runtime 替代。

runtime 检查生成的入口和项目上下文是否存在，使用
`.claude/guardrails/profile.json` 作为 write authorization contract，拒绝项目外
写入和明显的 raw artifact 发布路径，在 `local-only` 外部写入或危险 memory refresh
前请求确认，并在必要上下文缺失时返回 `needs-human`。

默认 `local-only` profile 不授权外部写入。`public-contributor` profile 保持普通
issue、fork pull request、CI 和 maintainer review 路径可用，不要求 bot。只有项目
自己的指令声明相应 profile 时，才应修改 `default_profile`。

这些 hooks 用于提高模板可靠性，不是 security sandbox、权限隔离，也不能替代
Claude Code permissions 和 maintainer review。runner 没有判断时保持静默，让正常权限
流程继续生效。

`PATH` 中必须提供 PowerShell 7（`pwsh`）。修改 settings、runner、profile 或模板后，
运行离线 validator：

```powershell
pwsh -NoProfile -File scripts/validation/test-claude-hooks-runtime.ps1
```
