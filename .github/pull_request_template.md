# 拉取请求

解释性标题和正文默认使用简体中文；`paths`、commands、code/API/config
fields、labels、state 以及其他机器可读值保留英文或原文。

## 参与者

- 提议者：agent / human
- 实施者：agent / human
- 审查者：pending / human / second-agent
- 合并权限：maintainer

<!-- 默认保持 None.；只有 maintainer 明确授权 fallback 时才替换为实际原因。 -->
## Actor Boundary

None.

## 关联议题

Refs #<number>

<!-- 只有确实应在 merge 后自动关闭 Issue 时才使用 `Fixes #<number>`。 -->

## 议题与变更映射

| 变更 | 来源议题 | 是否必填 | 验证 |
|---|---:|---|---|
|  |  | yes/no |  |

## 必要性评估

- 为什么需要：
- 未修复风险：
- 为什么现在：
- 已考虑的替代方案：

## 范围控制

- [ ] 没有夹带无关修改
- [ ] 已核对公共/私有边界
- [ ] 必要时已更新文档
- [ ] 必要时已更新 Release 元数据

Release impact:

<!-- 必填且仅填写：none / patch / minor / major；详见 docs/release-process.md。 -->

## 基线/堆叠安全

- 目标基线分支：`main`
- 是否有意堆叠：yes/no
- 如果是，为何需要非 `main` 基线？
- 合并前确认预期文件会进入 `main`。

## 验证

- 验证层级：
- 受影响表面命令：

```text
# command output summary
```

## 回滚计划

- 回滚提交：
- 受影响文件：
- 面向用户的兼容性风险：
- 安全回滚窗口：

## 人工决策

- [ ] 维护者已接受范围
- [ ] 维护者已审查 diff
- [ ] 维护者已核对 CI
- [ ] 维护者已批准 merge
