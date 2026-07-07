# 上下文路由

项目记忆语言：简体中文。

此目录是长期项目记忆入口。

- `tech/`：架构、模块、构建/部署细节、环境说明。
- `business/`：产品逻辑、状态机、领域规则。
- `experience/`：踩坑、事故、修复和可复用 playbook。

可选上下文文件（仅在项目确实受益时创建）：
- `tech/terminology.md`：项目特有术语、缩写和领域行话——适用于领域术语密集、多团队协作或缩写较多的项目；小项目或文档完善的项目可跳过。

渐进读取规则：非模板 context 文件应在靠前位置包含 `## Summary` 和 `## Keywords`，方便 agent 先读 README / index，再只打开匹配的上下文条目。

## 可选条目索引

当某个分类目录条目较多，或更快扫描能明显降低加载成本时，可在分类 README 中维护
`条目索引` 表。索引必须 public-safe 且由人工维护：

| 文件 | 摘要 | 关键词 |
| --- | --- | --- |
| `example.md` | 一句话说明何时需要打开该条目。 | keyword-a, keyword-b |

只有在 `Maturity` 或 `Reviewed` 等字段由人工复核维护时，才允许把它们作为可选列。
不要把 telemetry-derived 字段、runtime usage counts、`last_accessed` 或 automatic decay state
写入 context 索引。
