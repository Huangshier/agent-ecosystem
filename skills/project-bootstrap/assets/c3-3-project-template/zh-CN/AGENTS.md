# AGENTS.md

此文件是项目行为入口。

- canonical durable asset 只有 Work、Context、Procedure、Spec。
- 项目本地 Skills 是独立的晋升表面，不是第五种 canonical asset。
- packaged runtime 只拥有 manifest 管理的已安装内容；项目 workspace 文件始终属于项目本地。
- discovery 和 status 默认只读；写入必须来自明确的 authoring 操作。
