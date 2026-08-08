# 项目 workspace

此目录是项目本地 workspace 表面。

- `work/`、`context/`、`procedures/` 和 `skills/` 是项目本地目录。
- canonical durable asset 只有 Work、Context、Procedure、Spec。
- `docs/specs/` 是项目本地 spec 表面，不属于 runtime 所有。
- `skills/` 保存项目本地 Skills 和晋升后的 Skills；packaged runtime Skill 保持独立。
- `.cache/` 是可重建的派生数据；卸载 runtime 不得删除此 workspace。

Bootstrap 只创建结构，不创建占位资产。
