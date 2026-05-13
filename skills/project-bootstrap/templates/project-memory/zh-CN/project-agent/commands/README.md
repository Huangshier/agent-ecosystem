# 命令目录

项目记忆语言：简体中文。

此目录用于沉淀高频、可复用的项目工作流命令。它与
`.agents/AGENTS.md` 配合使用：agent 指南说明何时查看这里，本目录记录
可重复执行的精确命令流程。

优先使用项目文档、package scripts、Makefile、任务运行器、CI workflows 或本目录已有文件中记录的命令。项目未记录某类工作流时，不要凭空发明命令；先检查项目现有入口。

当细节不适合继续放在本 README 时，为每个可复用工作流新增一个简短 Markdown 文件。建议字段：
- 用途和何时使用
- 前置条件
- 命令
- 预期通过/失败证据
- 外部副作用的安全说明

示例：
- setup/install workflow
- format/lint workflow
- test workflow
- build workflow
- release validation workflow
- review checklist
