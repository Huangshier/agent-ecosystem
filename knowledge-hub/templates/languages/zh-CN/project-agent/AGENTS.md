# 项目记忆指南

项目行为规则仅以根 `AGENTS.md` 为准。本指南只描述工程记忆子系统，不得重复完整的工作方式、写入授权、交付、spec、commit、push 或 PR 契约。

## 项目记忆语言
项目记忆语言：简体中文。

本项目工程记忆默认使用简体中文。文件名、目录名、Markdown 字段标签、命令、路径、API 名称、代码符号和原始错误文本可以保留英文或原文。面向公开受众的产物使用目标仓库或目标受众要求的语言。

## 目录职责与记忆路由
- `.agents/process.txt`：当前运行状态、阻塞和下一步。
- `.agents/plan.md`：会话本地的当前任务指针与清单状态。
- `.agents/notes.md`：值得保留的已验证决策和稳定事实。
- `.agents/context/tech/`：稳定技术事实和术语。
- `.agents/context/business/`：持久产品或业务规则。
- `.agents/context/experience/`：重复踩坑、修复和可复用经验。
- `.agents/context/experience/cases/`：结构化排障案例。
- `.agents/commands/`：已记录的可复用项目工作流和证据要求。
- `docs/specs/<slug>/`：根契约和项目工作流要求时使用的持久工作包。
- `.agents/hub.lock.json`：模板来源、语言、已安装 hash 和刷新 provenance。

非模板 context 条目应在靠前位置包含 `## Summary` 和 `## Keywords`，方便在不预加载整个目录的情况下发现相关记忆。

## 渐进加载顺序
读取根 `AGENTS.md` 后，按以下顺序渐进加载记忆：

1. **热记忆**：`.agents/AGENTS.md`、`.agents/process.txt`，以及非平凡任务所需的 `.agents/plan.md`。
2. **温记忆**：热记忆引用的当前 `docs/specs/<slug>/spec.md` 和 `tasks.md`。
3. **冷发现**：`.agents/context/README.md` 和目录索引，然后只读取 Summary、Keywords 或任务相关性匹配的条目；仅在稳定事实相关时读取 `.agents/notes.md`。
4. **工作流发现**：`.agents/commands/README.md`，然后只读取当前工作流相关的命令卡片。

不要预加载完整 `.agents/context/` 或 `.agents/commands/` 目录。

## 模板来源与保守刷新
Canonical 工程记忆模板位于 `knowledge-hub/templates/languages/<language>/`。安装后的 runtime 可以使用逐字节对齐的 bundled `project-bootstrap` snapshot。`.agents/hub.lock.json` 记录所选语言、模板来源和已安装模板 hash。

使用项目 status/context 入口检查漂移。当根契约授权刷新时，使用 `bootstrap_project.ps1 -RefreshUnmodifiedTemplates`：仍匹配已记录旧模板 hash 的文件可以在备份后刷新；已定制文件或缺少可信旧 hash 的文件保持不变并报告为 manual review。Language migration 必须走 proposal-first、backup-first 的复核流程。Reset 不是刷新路径，必须遵守根 `AGENTS.md` 定义的明确授权。
