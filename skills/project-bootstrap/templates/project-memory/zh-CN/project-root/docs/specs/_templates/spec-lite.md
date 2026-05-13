# 工作说明

项目记忆语言：简体中文。

- **Title**:
- **Slug**:
- **Status**: Draft / Active / Done / Archived
- **Owner**:
- **Updated**:

## 1. 摘要
- 本次要构建、修改或调查什么？

## 2. 当前上下文
- 相关代码路径、二进制、文档、产物或观察到的行为。
- 已确认的现有实现事实。

## 3. 目标
- 清晰列出完成结果。

## 4. 非目标
- 明确本工作项不覆盖的边界。

## 5. 约束
- 环境、兼容性、工具、时间、安全或接口约束。
- 范围控制：不要纳入目标之外的无关重构、清理或行为变更。

## 6. 假设
- 尚待证实但当前用于推进的假设。

## 7. 风险
- 可能失败或需要 fallback 的事项。

## 8. 方案
- 计划方向、实现轮廓或分析方法。

## 9. 验收与证据
- 如何验证结果。
- 完成时应留下什么证据或输出。
- 如果验收检查被跳过或暂不可用，必须先记录原因，再声明完成。

## 10. 循环契约
- 只在需要重复执行直到变量或条件满足时使用。
- **Variable**:
- **Source of truth**:
- **Check command**:
- **Pass predicate**:
- **Iteration action**:
- **State record**:
- **Limits**:
- **Abort conditions**:

## 11. 执行契约
- 多阶段工作需要 agent 在每个已验证阶段后继续时使用。
- **Autonomy level**: ask-before-each-phase / autonomous-until-blocked / bounded-autonomous
- **Phase list**:
  - P01:
  - P02:
  - P03:
- **Continue rule**:
- **Stop rule**: 包含 scope drift、unrelated refactor、skipped acceptance checks、安全/权限阻塞和无法消解的真实歧义。
- **State record**:

## 12. 开放问题
- 仍可能阻塞或改变执行方向的问题。
