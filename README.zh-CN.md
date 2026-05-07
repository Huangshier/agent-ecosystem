# Agent Ecosystem

轻量 Agent 工程脚手架，用于在软件项目中管理上下文、规格、记忆和可复用经验。

公开文档以英文优先；本文件提供第一版 public release 的简短中文入口。

当前公开版本是 `v0.2.0`。第一版公开 release 包含
Workflow Kernel、public installer、public knowledge templates 和 release
validation workflow；`v0.2.0` 补充 language write、spec validator、
domain-pack scaffold 和 adoption examples。

## 第一版公开范围

第一版只包含通用 Workflow Kernel，不包含领域专用 skill：

- `project-bootstrap`
- `project-context-gate`
- `workflow-spec-lite`
- `memory-governance`
- public knowledge hub templates
- installer/profile scaffolding
- public-safe domain-pack scaffold
- adaptation guide 和 minimal project example

## 快速开始

```powershell
.\scripts\install.ps1 -Profile recommended
```

建议先安装到临时 runtime 做验证：

```powershell
.\scripts\install.ps1 -Profile recommended -TargetDir <temp-runtime> -Copy -Force
```

默认安装模式会优先创建链接；如果链接创建失败，安装器会回退到 copy mode。
安装器会在目标 runtime 下生成 `install-manifest.json`，记录 profile、skills 和
每个安装项使用的模式。

## Profiles

`v0.1.0` release 提供四个公开 profile 名称：

- `minimal`：安装 bootstrap skill 和 public knowledge hub templates。
- `recommended`：安装 Workflow Kernel 和 public knowledge hub。
- `full`：当前安装内容与 `recommended` 相同。
- `dev`：当前安装内容与 `recommended` 相同。

`full` 和 `dev` 会在 kernel release 稳定后用于后续 public domain packs 和
developer maintenance tooling。

## 边界

- domain skills 暂不进入第一版公开 release。
- private overlay、敏感知识、本机迁移映射和审计细节不属于 public repo。
- live runtime cutover 需要在 release 决策后单独执行。

更多细节请以英文文档为准：

- [Architecture](docs/architecture.md)
- [How to adapt](docs/how-to-adapt.md)
- [Release readiness](docs/release-readiness.md)
- [v0.2.0 release notes](docs/releases/v0.2.0.md)
- [Examples](examples/README.md)
