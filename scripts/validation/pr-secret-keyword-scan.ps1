# pr-secret-keyword-scan.ps1
# 轻量 PR 新增行 secret keyword 扫描。
# 复用与 main 全仓 secret keyword scan 一致的关键词、白名单和精确允许规则。
# 仅扫描 PR 相对 base 的新增行；删除行、上下文行和历史未修改内容不触发。
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BaseRef,
    [Parameter(Mandatory = $true)][string]$HeadRef,
    [switch]$Json
)

$ErrorActionPreference = "Stop"

# 与 release-parser-safety-checks.ps1 完全一致的高风险格式规则
$highRiskPatterns = @(
    [ordered]@{ name = "windows_user_path"; pattern = '(?i)\b[A-Z]:[\\/]+Users[\\/]+[^\\/ ]+' },
    [ordered]@{ name = "windows_projects_path"; pattern = '(?i)\b[A-Z]:[\\/]+Projects[\\/]+[^\\/ ]+' },
    [ordered]@{ name = "private_key_marker"; pattern = '-----BEGIN [A-Z ]*PRIVATE KEY-----' },
    [ordered]@{ name = "github_token"; pattern = '(?i)\b(ghp|github_pat)_[A-Za-z0-9_]{20,}\b' },
    [ordered]@{ name = "openai_key"; pattern = '(?i)\bsk-[A-Za-z0-9]{20,}\b' },
    [ordered]@{ name = "aws_access_key"; pattern = '\bAKIA[0-9A-Z]{16}\b' },
    [ordered]@{ name = "slack_token"; pattern = '(?i)\bxox[abprs]-[A-Za-z0-9-]{20,}\b' }
)

# 与 release-parser-safety-checks.ps1 完全一致的 secret keyword 规则
$secretPattern = '(?i)\b(secret|password|api[_ -]?key|credential|credentials|cookie|cookies|token|tokens|private key|private keys)\b'
$allowedSecretReferences = @{
    ".github/workflows/release-validation.yml" = '^\s*LINEAGE_GITHUB_AUTH:\s+\$\{\{\s*github\.token\s*\}\}\s*$'
}
$allowedSecretPaths = @(
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
    "scripts/validate-release.ps1"
)

# 获取 PR diff 中的新增行（仅 + 行，排除 +++ 文件头）
$global:LASTEXITCODE = 0
$diffLines = @(& git diff "$BaseRef...$HeadRef" --unified=0 --diff-filter=ACMR 2>$null)
if ($LASTEXITCODE -ne 0) {
    # fail-soft：diff 不可用时跳过扫描（main 全仓扫描仍为兜底）
    if ($Json.IsPresent) {
        [ordered]@{ status = "SKIP"; reason = "diff-unavailable"; base_ref = $BaseRef; head_ref = $HeadRef; violation_count = 0; violations = @() } | ConvertTo-Json -Depth 4
    } else {
        Write-Output "PR secret keyword scan: SKIP (diff unavailable between $BaseRef and $HeadRef)"
    }
    exit 0
}
$global:LASTEXITCODE = 0

# 解析 diff：提取每个文件的新增行及行号
$violations = New-Object 'System.Collections.Generic.List[object]'
$currentFile = ""
$currentLine = 0

foreach ($line in $diffLines) {
    if ($line -match '^\+\+\+ b/(.+)$') {
        $currentFile = $Matches[1] -replace '\\', '/'
        continue
    }
    if ($line -match '^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@') {
        $currentLine = [int]$Matches[1]
        continue
    }
    if ($line.StartsWith("+") -and -not $line.StartsWith("+++")) {
        $text = $line.Substring(1)

        # 高风险格式规则：任何路径均不允许
        foreach ($rule in $highRiskPatterns) {
            if ($text -match $rule.pattern) {
                $violations.Add([ordered]@{
                    rule = $rule.name
                    path = $currentFile
                    line = $currentLine
                    text = $text.Trim()
                })
            }
        }

        # secret keyword 规则：允许路径和精确允许规则豁免
        if ($text -match $secretPattern) {
            $isAllowedPath = $currentFile -in $allowedSecretPaths
            $isExactAllowed = $allowedSecretReferences.ContainsKey($currentFile) -and
                $text -match $allowedSecretReferences[$currentFile]
            if (-not $isAllowedPath -and -not $isExactAllowed) {
                $violations.Add([ordered]@{
                    rule = "secret_keyword"
                    path = $currentFile
                    line = $currentLine
                    text = $text.Trim()
                })
            }
        }

        $currentLine++
    }
    elseif ($line.StartsWith("-")) {
        # 删除行不递增行号
    }
    else {
        # 上下文行（unified=0 时通常不出现）
        $currentLine++
    }
}

if ($Json.IsPresent) {
    [ordered]@{
        status = if ($violations.Count -eq 0) { "PASS" } else { "FAIL" }
        base_ref = $BaseRef
        head_ref = $HeadRef
        violation_count = $violations.Count
        violations = @($violations.ToArray())
    } | ConvertTo-Json -Depth 4
} else {
    if ($violations.Count -eq 0) {
        Write-Output "PR secret keyword scan: PASS (0 violations in added lines)"
    } else {
        Write-Output "PR secret keyword scan: FAIL ($($violations.Count) violations in added lines)"
        foreach ($v in $violations) {
            Write-Output ("  {0}:{1} [{2}] {3}" -f $v.path, $v.line, $v.rule, $v.text)
        }
    }
}

if ($violations.Count -gt 0) { exit 1 }
exit 0
