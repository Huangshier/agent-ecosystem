# Runtime Adoption Bridge

本文说明不同 agent runtime 如何进入同一 Workflow Kernel project memory model，
同时保持 fresh C3.3 bootstrap runtime-neutral。

完成一次性的 C3.3 default cutover 后，fresh project 会直接 bootstrap 到
canonical C3.3 workspace（`project-bootstrap` + `project-workspace`）。这两个是
唯一 active Runtime Skills。`project-context-gate`、`workflow-spec-lite` 和
`memory-governance` 已 retired；历史记录或 compatibility fixture 中仍有这些
名称，并不意味着它们是当前 startup 或 migration path。

首次安装和 bootstrap path 见 [how-to-adapt](how-to-adapt.md)；完整 adoption
walkthrough 见 [minimal project adoption](walkthroughs/minimal-project-adoption.md)。

## 范围

本文覆盖三类 runtime：

- **Codex**（OpenAI）：原生支持 `AGENTS.md` 和 skill discovery。
- **Claude Code**（Anthropic）：fresh bootstrap 不生成 client-specific startup
  file；project-local Skill 可通过显式 adapter 发布到其 discovery surface。
- **Generic agents**：startup surface 未知；读取 `AGENTS.md`，然后显式使用
  `project-workspace` 的 `check` 和 `discover` entrypoint。

本文不做以下事情：

- 不向 fresh bootstrap template 添加 `CLAUDE.md`、`GEMINI.md`、`.clinerules`
  或其他 runtime-specific startup/hook file；
- 不实现 shared session state store、lifecycle hooks 或 state schema，也不重新
  设计既有 project-Skill adapter；
- 不控制任何 runtime 的内部加载行为；
- 不包含 private overlay path、local runtime state 或 sensitive material。

## C3.3 Runtime 边界

一次性的 default cutover 已使 `recommended`（以及 `full` / `dev`）成为 active
C3.3 Runtime。其 manifest 将 workspace capability 记录为 `active`，并设置
`default_cutover: true`，同时打包 `project-workspace` Skill 及其 project
template。打包后的 runtime 只拥有其 manifest 管理的 runtime content；
`AGENTS.md`、`.agents/` workspace、canonical Work/Context/Procedure/Spec
asset、project-local Skill 和 `docs/specs/` 仍属于 project-local，不在 runtime
uninstall ownership 内。

Runtime Skill authority 仅限 `project-bootstrap` 和 `project-workspace`。
`project-context-gate`、`memory-governance` 和 `workflow-spec-lite` 已从 C3.3
authority retired：没有 public profile 安装或 bridge 它们，也没有 alias、
forwarder 或 dual-write path。下文描述的 legacy project-loading path 仅作
历史解释。现有 legacy project 通过 Runtime-level
`scripts/migrate-project.ps1` 的 Analyze -> explicit Apply -> guarded Rollback
flow 迁移；fresh project 则直接 bootstrap 到 canonical C3.3 workspace。

## 共享入口

Workflow Kernel 使用 project root 的 `AGENTS.md` 作为 canonical entrypoint。
该文件告诉 agent 去哪里查找更深层的 guidance：

```text
<project>/
  AGENTS.md                       ← authoritative project behavior contract
  .agents/
    README.md                     ← canonical workspace guide
    .gitignore                    ← derived/backup workspace exclusions
    hub.lock.json                 ← bootstrap language/workspace metadata
    context/                      ← canonical Context assets and discovery index
    procedures/                   ← canonical Procedure assets
    work/                         ← unfinished-work continuity assets
    skills/                       ← optional project-local Skill publication
  docs/
    specs/                        ← canonical durable Spec assets
```

Existing legacy project 还可能包含旧的 `.agents/AGENTS.md`、`process.txt`、
`plan.md`、`notes.md`、command index、`CLAUDE.md` 或 `.claude/**`。这些是
compatibility-only migration input；保留 project-owned content 不会使它们成为
第二套 C3.3 authority。
`project-workspace` 仍是 canonical Work、Context、Procedure 和 Spec discovery
及 authoring 的 public entrypoint。

## 渐进加载

所有 runtime 都应渐进加载 project guidance，而不是一次性预加载全部内容。这样
context cost 才会与 task complexity 保持相称。

**Required startup**——在 session start 立即加载：

1. root `AGENTS.md`
2. 使用 `project-workspace` `check` 验证 workspace contract。
3. 仅对 task 匹配的 asset 使用 `project-workspace` `discover`。

**Warm tier**——non-trivial task active 时加载：

- task 需要 durable project-local work package 时，加载
  `docs/specs/<slug>/spec.md` 和 `tasks.md`

**On-demand tier**——仅在 task keyword 匹配时打开：

- 按 `Summary` 或 `Keywords` 匹配的 `.agents/context/**` entry
- documented workflow 相关时匹配的 `.agents/procedures/**` entry
- 恢复未完成工作时匹配的 `.agents/work/**` continuity record

使用 `project-workspace create-spec` 创建 durable Spec；未完成工作使用其
Work/Context continuity operation。可选文件缺失时跳过，不要把它们当作 error。

## Codex 路径

Codex 原生支持 `AGENTS.md`，entry sequence 如下：

1. Codex 在 session start 读取 root `AGENTS.md`。
2. 运行 active `project-workspace` check，并只 discover 匹配的 Work、Context、
   Procedure 和 Spec asset。
3. 对 durable project work package，在 `docs/specs/<slug>/` 下使用
   `project-workspace create-spec`。
4. 对未完成 work 或稳定的 handoff fact，使用 `project-workspace` 的
   Work/Context continuity operation。

Codex 还会通过已安装的 skill registry 发现 active Skill。retired Skill 不是当前
startup 的必需项，不得恢复为 alias 或 compatibility forwarder。

## Claude Code 路径

fresh C3.3 bootstrap 不创建 `CLAUDE.md`、`.claude/settings.json`、legacy
guardrail/hook scaffold，也不推断 Claude Code 的 behavior-entry configuration。
这使 canonical project workspace 与 client-specific loading policy 保持分离。

无论 client 如何加载项目行为，持续检查 canonical workspace 时都使用 active
`project-workspace`：

```powershell
pwsh -NoProfile -NonInteractive -File <runtime>/skills/project-workspace/scripts/check-project-workspace.ps1 -ProjectRoot <project> -Json
pwsh -NoProfile -NonInteractive -File <runtime>/skills/project-workspace/scripts/discover-project-assets.ps1 -ProjectRoot <project> -Query <query> -Json
```

### Optional Project-Skill Adapter

项目已在 `.agents/skills/<name>/` 发布本地 Skill 且需要 Claude Code discovery
时，可以显式创建唯一支持的 adapter target：

```powershell
pwsh -NoProfile -NonInteractive -File <runtime>/skills/project-workspace/scripts/project-workspace.ps1 -Operation create-adapter -ProjectRoot <project> -Target claude-code -Json
pwsh -NoProfile -NonInteractive -File <runtime>/skills/project-workspace/scripts/project-workspace.ps1 -Operation status-adapter -ProjectRoot <project> -Target claude-code -Json
```

该 adapter 将 `.agents/skills/<name>` 作为 source，以 managed copy 发布到
`.claude/skills/<name>`。它不由 bootstrap 自动创建，不生成行为 shim，不修改
`.gitignore`，也不授予任何执行或外部写入权限。modified、unowned、invalid 或
conflicting target 会 fail closed；完整 lifecycle 见
[`project-workspace`](../skills/project-workspace/SKILL.md#claude-code-project-adapter)。

### Existing Legacy Project (Compatibility-Only)

existing legacy project 可能仍有 project-owned `CLAUDE.md`、`.claude/**`、nested
guide 或 hot-memory import。legacy bootstrap compatibility path 可以保留这些
内容，但它们不是 fresh/default contract。迁移使用 Runtime-level authority：

```powershell
pwsh -NoProfile -NonInteractive -File <runtime>/scripts/migrate-project.ps1 -Mode Analyze -ProjectRoot <project> -Json
pwsh -NoProfile -NonInteractive -File <runtime>/scripts/migrate-project.ps1 -Mode Apply -ProjectRoot <project> -AnalyzeEvidence <analyze-json> -ConfirmMigration -Json
pwsh -NoProfile -NonInteractive -File <runtime>/scripts/migrate-project.ps1 -Mode Rollback -ProjectRoot <project> -BackupId <backup-id> -ConfirmRollback -Json
```

pre-C3.3 hook/guardrail contract 仅保留为
[historical / compatibility-only documentation](claude-code-hooks-guardrails.md)，
不得作为 new-project adoption guidance。

## Generic Agent 路径

当 agent runtime 没有已知的 `AGENTS.md` startup surface 时，使用显式 workspace
discovery path：

1. 运行 active `project-workspace` checks，盘点可用 asset：

   ```powershell
   pwsh -NoProfile -NonInteractive -File <runtime>/skills/project-workspace/scripts/check-project-workspace.ps1 -ProjectRoot <project> -Json
   pwsh -NoProfile -NonInteractive -File <runtime>/skills/project-workspace/scripts/discover-project-assets.ps1 -ProjectRoot <project> -Query <query> -Json
   ```

2. 读取 `AGENTS.md`，然后只打开匹配的 canonical Work、Context、Procedure 或
   Spec asset。

3. 当前任务有 durable Spec 时，读取 `docs/specs/<slug>/spec.md` 及其配套
   `tasks.md`（如果存在）。

4. 只有 task keyword 与 metadata 对齐时，才读取匹配 asset。

5. 对 durable work，使用 `project-workspace create-spec` 创建 Spec；对未完成
   work，使用其 Work continuity operation。

## 首次使用诊断

不确定 project memory 是否正确加载时，检查：

```powershell
# 1. Verify scaffold exists
Test-Path <project>/AGENTS.md
Test-Path <project>/.agents/README.md
Test-Path <project>/.agents/hub.lock.json

# 2. Check the active C3.3 workspace
pwsh -NoProfile -NonInteractive -File <runtime>/skills/project-workspace/scripts/check-project-workspace.ps1 -ProjectRoot <project> -Json

# 3. Discover matching canonical assets
pwsh -NoProfile -NonInteractive -File <runtime>/skills/project-workspace/scripts/discover-project-assets.ps1 -ProjectRoot <project> -Query <query> -Json
```

如果 fresh project 缺少 scaffold，为 project 重新运行 `project-bootstrap`。如果
existing project 是 legacy，在 Analyze 后使用显式 migration authority，不要恢复
retired helper：

```powershell
pwsh -NoProfile -NonInteractive -File <runtime>/skills/project-bootstrap/scripts/bootstrap_project.ps1 -ProjectDir <project>
pwsh -NoProfile -NonInteractive -File <runtime>/scripts/migrate-project.ps1 -Mode Analyze -ProjectRoot <project> -Json
```

## Public / Private 边界

- target project 内的 `AGENTS.md`、`.agents/` 和 `docs/specs/` 属于
  **project-local**，归 project 所有，不归 public kernel repository 所有。
- public kernel repository（`agent-ecosystem`）提供 template、skill 和文档，
  不拥有 project-local memory。
- private overlay、runtime state、sensitive material 和 local-only path 不得
  出现在 public documentation、issue 或 pull request 中。
- 将 private project 的 reusable lesson 晋升到 public knowledge hub 时，遵循
  [public promotion checklist](../knowledge-hub/knowledge/standards/public-promotion-checklist.md)。

## 长期方向

issue #116 的近期讨论提出将 session state 外置到 shared store，并加入
cross-runtime lifecycle hooks 和 standardized state schema，使任意 agent runtime
都能从 checkpoint 恢复另一个 runtime 的 session。该 proposal 在架构上有意义，
但仍需验证是否对应真实用户痛点，而且与当前 file-driven progressive
disclosure model 冲突。因此它只记录为 long-term exploration topic，不属于本文
档 bridge 的范围。

## 验证

本文档的 documentation-only 变更应运行：

```powershell
git diff --check
pwsh -NoProfile -NonInteractive -File scripts/invoke-local-validation.ps1 -Stage iteration
pwsh -NoProfile -NonInteractive -File scripts/invoke-local-validation.ps1 -Stage pre-push
```

完整 Release validator 仅用于明确的 Release/checkpoint decision。
