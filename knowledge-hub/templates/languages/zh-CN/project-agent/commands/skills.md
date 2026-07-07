# 技能发现

项目记忆语言：简体中文。

## 用途

盘点当前项目或 runtime 可用的 skills，但不修改 runtime 配置、不安装工具、
不启用或禁用 skill，也不验证具体客户端兼容性。

## 何时使用

- 用户询问当前有哪些 skills，或询问如何发现 skills。
- 项目命令、交接或复核需要一份 public-safe 的已安装 skill 名称和描述清单。
- 在决定使用哪个 skill 前，需要区分 Workflow Kernel skills、项目本地
  skills、个人 skills、admin / system skills 或 plugin 提供的 skills。

## 发现位置

只检查当前环境中实际存在的位置。常见位置包括：

| 范围 | 常见位置 |
| --- | --- |
| 项目本地 | `.agents/skills`、`.github/skills`、`.claude/skills` |
| Runtime 或仓库 | `<runtime>/skills`、`<repo>/skills` |
| 用户本地 | `%USERPROFILE%\.agents\skills`、`$HOME/.agents/skills`、`$HOME/.copilot/skills` |
| System / admin | `/etc/codex/skills` 或 runtime 管理的 system skill 目录 |

对每个候选 skill 目录，先只读取 `SKILL.md`。使用渐进式披露：除非当前任务已经选择该
skill 且确实需要，否则不要预加载 `scripts/`、`references/` 或 `assets/`。

## 汇报内容

对每个发现的 skill，汇报：

- Skill name：优先来自 `SKILL.md` frontmatter；缺失时使用目录名。
- 来自 `description` 的简短描述或触发摘要。
- 位置范围，例如 project-local、runtime、user-local、system 或 plugin。
- 当 frontmatter 或 metadata 包含 `category: kernel` 时，标注 kernel 分类。
- Frontmatter 中已存在的保守 compatibility 说明。

## 边界

- 本命令卡只读。除非另一个明确任务授权，否则不要 install、remove、enable、
  disable、symlink、copy 或 validate skills。
- 不要仅因为 metadata 形状类似外部标准，就声称某个 skill 已兼容 Codex、
  Copilot、Claude Code 或其他客户端。
- 不要把 `agents/openai.yaml` 当作 Codex Agent Skills 兼容证据。它是并行
  metadata 层。
- 不要通过本发现命令添加 `allowed-tools`、`invocation`、adapter wrappers、
  marketplace entries、registry publishing 或 release-blocking external
  validator checks。

## 预期证据

- 已检查的位置清单，以及每个位置是否存在。
- 已发现的 `SKILL.md` 文件清单。
- Frontmatter 字段摘要：`name`、`description`、`metadata`、`compatibility`
  以及项目特定字段。
- 对当前环境中不存在的位置给出明确说明。

