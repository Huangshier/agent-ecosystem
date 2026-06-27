# 工作说明

- **Title（标题）**: 中文章节 fixture
- **Slug（标识）**: chinese-section-fixture
- **Status（状态）**: Active
- **Owner（负责人）**: release validation
- **Updated（更新时间）**: 2026-05-08

## 1. Summary（摘要）
- 验证真实 zh-CN 模板的双语 anchor 可以通过轻量 spec validator。

## 2. 当前上下文
- release validation 需要覆盖中文项目记忆场景。

## 4. 目标
- 确认中文章节正例通过。

## 5. 非目标
- 不改写 fixture 文件。

## 6. 约束
- 只使用临时 fixture。

## 7. 假设
- 中文章节标题保持模板约定。

## 8. 风险
- 中文章节别名缺失会影响中文项目 spec。

## 9. 方案
- 执行 validator 并检查 pass 字段。

## 10. 验收与证据
- 中文章节 fixture 通过验证。

## 12. 循环契约
- 不适用。

## 13. 执行契约
- **Autonomy level（自主级别）**: bounded-autonomous
- **Phase list（阶段列表）**:
  - P01: 验证中文章节 fixture。
- **Continue rule（继续规则）**: fixture 通过时继续。
- **Stop rule（停止规则）**: 必需章节缺失时停止。
- **State record（状态记录）**: release validation evidence。

## 14. 开放问题
- 无。
