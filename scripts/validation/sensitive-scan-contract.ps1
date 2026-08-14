# sensitive-scan-contract.ps1
# Sensitive scan 单一共享契约。
# main 全仓扫描和 PR 新增行扫描共同 dot-source 本文件，不复制规则。
# 修改本文件即同时变更两个扫描路径的行为。

$SensitiveScanHighRiskPatterns = @(
    [ordered]@{ name = "windows_user_path"; pattern = '(?i)\b[A-Z]:[\\/]+Users[\\/]+[^\\/ ]+' },
    [ordered]@{ name = "windows_projects_path"; pattern = '(?i)\b[A-Z]:[\\/]+Projects[\\/]+[^\\/ ]+' },
    [ordered]@{ name = "private_key_marker"; pattern = '-----BEGIN [A-Z ]*PRIVATE KEY-----' },
    [ordered]@{ name = "github_token"; pattern = '(?i)\b(ghp|github_pat)_[A-Za-z0-9_]{20,}\b' },
    [ordered]@{ name = "openai_key"; pattern = '(?i)\bsk-[A-Za-z0-9]{20,}\b' },
    [ordered]@{ name = "aws_access_key"; pattern = '\bAKIA[0-9A-Z]{16}\b' },
    [ordered]@{ name = "slack_token"; pattern = '(?i)\bxox[abprs]-[A-Za-z0-9-]{20,}\b' }
)

$SensitiveScanKeywordPattern = '(?i)\b(secret|password|api[_ -]?key|credential|credentials|cookie|cookies|token|tokens|private key|private keys)\b'

$SensitiveScanAllowedReferences = @{
    "scripts/validate-change.ps1" = '^\s*\$scanScript = Join-Path \$scriptDir "validation/pr-secret-keyword-scan\.ps1"\s*$'
}

$SensitiveScanAllowedPaths = @(
    "AGENTS.md",
    "README.en.md",
    ".agents/AGENTS.md",
    "CONTRIBUTING.md",
    "SECURITY.md",
    "docs/agent-governance.md",
    "docs/claude-code-hooks-guardrails.md",
    "docs/global-candidate-workflow.md",
    "docs/release-readiness.md",
    "docs/release-process.md",
    "docs/roadmap/evolution-plan.md",
    "docs/roadmap/release-validator-thin-entrypoint-plan.md",
    "knowledge-hub/templates/languages/en/project-root/AGENTS.md",
    "knowledge-hub/templates/languages/en/project-agent/AGENTS.md",
    "skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/en/project-root/AGENTS.md",
    "skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/en/project-agent/AGENTS.md",
    "skills/project-bootstrap/scripts/set_project_language.ps1",
    "skills/project-context-gate/SKILL.md",
    "scripts/validation/release-repository-checks.ps1",
    "scripts/validation/release-parser-safety-checks.ps1",
    "scripts/validation/release-documentation-checks.ps1",
    "scripts/validation/release-knowledge-hub-checks.ps1",
    "scripts/validation/release-knowledge-candidate-checks.ps1",
    "scripts/validation/release-runtime-smoke-checks.ps1",
    "scripts/validation/release-bootstrap-checks.ps1",
    "scripts/validation/release-claude-hooks-guardrails-checks.ps1",
    "scripts/validation/release-project-template-checks.ps1",
    "scripts/validation/release-hub-initialization-checks.ps1",
    "scripts/validation/release-knowledge-search-checks.ps1",
    "scripts/validation/release-shard-contract.ps1",
    "scripts/validation/release-shard-contract.json",
    "scripts/validation/release-template-language-checks.ps1",
    "scripts/validation/release-eval-iteration-checks.ps1",
    "scripts/validation/release-memory-diagnostics-fixture-checks.ps1",
    "scripts/validation/release-governance-workflow-checks.ps1",
    "knowledge-hub/knowledge/patterns/examples/issue-decomposition-positive-fixture.md",
    "docs/roadmap/eval-driven-skill-iteration-plan.md",
    "scripts/validation/eval-iteration-fixtures/workflow-spec-lite/evals.json",
    "scripts/validation/eval-iteration-fixtures/workflow-spec-lite/report.json",
    "scripts/validation/eval-iteration-fixtures/workflow-spec-lite/baseline.json",
    "scripts/validation/eval-iteration-fixtures/README.md",
    "knowledge-hub/knowledge/patterns/eval-driven-skill-iteration.md",
    "knowledge-hub/scripts/manage_candidates.ps1",
    "skills/project-bootstrap/scripts/manage_candidates.ps1",
    "scripts/validate-release.ps1",
    "scripts/validation/pr-secret-keyword-scan.ps1",
    "scripts/validation/sensitive-scan-contract.ps1",
    "scripts/validation/test-sensitive-scan.ps1"
)
