# [Problem Title（问题标题）]

项目记忆语言：简体中文。

## Summary（摘要）
[一到两句话说明这条可复用经验及适用场景]

## Keywords（关键词）
[keyword1], [keyword2], [keyword3]

## Symptoms（症状）
- **Error message / observable behavior（错误信息/可观察行为）**: [exact error text or phenomenon]
- **Trigger condition（触发条件）**: [when / how it occurs]

## Root Cause（根因）
[说明根因，并引用具体代码位置或配置]

## Fix（修复）
[列出解决步骤或变更]

## Verification（验证）
[列出验证命令或确认方法]

## Prevention Rule（预防规则）
[可执行的预防规则]

## Scope（适用范围）
- Scope: Project-specific
- Global candidate: No
- Date: YYYY-MM-DD

## 全局晋升指引

默认将经验保留为项目本地条目。只有根因和预防规则已经确认可跨项目复用、且不包含
私有路径、原始日志或其他敏感信息时，才标记为全局候选。

如需由 `promote_experience.ps1` 晋升，保留以下英文结构锚点，不要替换为中文 metadata
aliases：

- `## Summary` 和 `## Keywords`；其中标题、正文、摘要和关键词值可以使用中文。
- `Global candidate: Yes` 或 `Scope: Cross-project reusable`。
- `Maturity`、`Scope`、`Source`、`Last reviewed`、`Decay policy` 生命周期字段；它们的值
  必须公开安全。

仅使用 `摘要`、`关键词`、`全局候选` 或 `范围` 等中文 aliases 的候选会被默认跳过。本模板
不要求中文 metadata aliases、schema v3 或语言自动检测。

可 promotion 条目的生命周期字段示例：

- Maturity: draft
- Source: public-safe reviewed project-local experience
- Last reviewed: YYYY-MM-DD
- Decay policy: Review when the relevant toolchain or workflow changes.
