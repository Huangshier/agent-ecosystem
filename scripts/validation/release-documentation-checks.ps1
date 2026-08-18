# release-documentation-checks.ps1
# Extracted from scripts/validate-release.ps1 Invoke-ReleaseValidationSpecAndDocumentationChecks (Phase 2).
# Runs static documentation boundary checks: anti-drift, diagnostics design, template guidance, adoption,
# readme entrypoints, release alignment, shell strategy, and release notes token/stale-wording checks.
# Depends on: release-test-helper.ps1 (Add-Check, Get-FileText, Get-MissingRequiredText), path-guard.ps1 (Join-PathParts).
# Scope: script-level $repoRoot, $script:evidence, $checks, $targetReleaseVersion.

# Invoke-ReleaseDocumentationBoundaryChecks: No parameters; runs anti-drift hardening, structural memory
# diagnostics design, agent template startup guidance, adoption surface, readme language entrypoints,
# publish-ready release alignment, cross-platform shell strategy, and all release notes checks in the
# original order.
function Invoke-ReleaseDocumentationBoundaryChecks {

try {
    $antiDriftFiles = [ordered]@{
        "skills/workflow-spec-lite/references/spec-template.md" = @("## 4. Goals", "## 5. Non-Goals", "## 10. Acceptance / Evidence", "Scope control:", "scope drift", "skipped acceptance")
        "knowledge-hub/templates/languages/en/project-root/docs/specs/_templates/spec-lite.md" = @("## 4. Goals", "## 5. Non-Goals", "## 10. Acceptance / Evidence", "Scope control:", "scope drift", "skipped acceptance")
        "skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/en/project-root/docs/specs/_templates/spec-lite.md" = @("## 4. Goals", "## 5. Non-Goals", "## 10. Acceptance / Evidence", "Scope control:", "scope drift", "skipped acceptance")
        "knowledge-hub/templates/languages/en/project-root/AGENTS.md" = @("Scope discipline:", "unrelated refactors", "acceptance checks are skipped")
        "skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/en/project-root/AGENTS.md" = @("Scope discipline:", "unrelated refactors", "acceptance checks are skipped")
        "skills/workflow-spec-lite/SKILL.md" = @("scope drift", "unrelated refactors", "skipped acceptance checks", "validate_spec.ps1", "memory_diagnose.ps1", "finding count")
        "skills/memory-governance/SKILL.md" = @("Scope drift", "Unrelated refactor", "Skipped acceptance")
    }

    $antiDriftMissing = New-Object 'System.Collections.Generic.List[string]'
    foreach ($relativePath in $antiDriftFiles.Keys) {
        $text = Get-FileText -RelativePath $relativePath
        foreach ($token in $antiDriftFiles[$relativePath]) {
            if ($text -notlike ("*{0}*" -f $token)) {
                $antiDriftMissing.Add("$relativePath missing token: $token")
            }
        }
    }

    if ($antiDriftMissing.Count -gt 0) {
        Add-Check "anti-drift hardening" "FAIL" "Spec templates or memory-governance guidance are missing scope drift protections." @($antiDriftMissing.ToArray())
    }
    else {
        Add-Check "anti-drift hardening" "PASS" "Spec templates, project-agent template, workflow-spec-lite, and memory-governance guidance include scope drift, unrelated refactor, and skipped acceptance protections." ([ordered]@{
            checked_files = @($antiDriftFiles.Keys)
        })
    }
}
catch {
    Add-Check "anti-drift hardening" "FAIL" $_.Exception.Message
}

try {
    $rootGuidanceFiles = [ordered]@{
        "AGENTS.md" = @('唯一 public agent behavior entry', 'GitHub issues and pull requests', '## Project Language Policy', 'docs/agent-governance.md', 'docs/language-policy.md', 'docs/release-process.md', 'Actor Boundary')
        "knowledge-hub/templates/languages/en/project-root/AGENTS.md" = @("single authoritative project behavior contract", "## Working Philosophy", "## On Stopping to Ask", "## Write Authorization Boundaries", "## Ambiguous Task Gate", "## Verification And Completion", "## Delivery Protocol & Working Loop", "## PR-Ready And Phase-Close Memory Sync Gate", "## Project Work Packages", '`.agents/commands/README.md`')
        "knowledge-hub/templates/languages/zh-CN/project-root/AGENTS.md" = @("唯一权威的项目行为契约", "## 工作方式", "## 何时停下来询问", "## 写入授权边界", "## 模糊任务入口", "## 验证与完成", "## 交付流程", "## PR 就绪与阶段收尾记忆同步门禁", "## 项目工作包", '`.agents/commands/README.md`')
        "skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/en/project-root/AGENTS.md" = @("single authoritative project behavior contract", "## Working Philosophy", "## On Stopping to Ask", "## Write Authorization Boundaries", "## Ambiguous Task Gate", "## Verification And Completion", "## Delivery Protocol & Working Loop", "## PR-Ready And Phase-Close Memory Sync Gate", "## Project Work Packages", '`.agents/commands/README.md`')
        "skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/zh-CN/project-root/AGENTS.md" = @("唯一权威的项目行为契约", "## 工作方式", "## 何时停下来询问", "## 写入授权边界", "## 模糊任务入口", "## 验证与完成", "## 交付流程", "## PR 就绪与阶段收尾记忆同步门禁", "## 项目工作包", '`.agents/commands/README.md`')
    }
    $claudeShimFiles = [ordered]@{
        "knowledge-hub/templates/languages/en/project-root/CLAUDE.md" = @('@AGENTS.md', '@.agents/AGENTS.md', '@.agents/process.txt', '@.agents/plan.md', '@.agents/context/README.md', '@.agents/commands/README.md')
        "knowledge-hub/templates/languages/zh-CN/project-root/CLAUDE.md" = @('@AGENTS.md', '@.agents/AGENTS.md', '@.agents/process.txt', '@.agents/plan.md', '@.agents/context/README.md', '@.agents/commands/README.md')
        "skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/en/project-root/CLAUDE.md" = @('@AGENTS.md', '@.agents/AGENTS.md', '@.agents/process.txt', '@.agents/plan.md', '@.agents/context/README.md', '@.agents/commands/README.md')
        "skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/zh-CN/project-root/CLAUDE.md" = @('@AGENTS.md', '@.agents/AGENTS.md', '@.agents/process.txt', '@.agents/plan.md', '@.agents/context/README.md', '@.agents/commands/README.md')
    }
    $agentGuidanceFiles = [ordered]@{
        "knowledge-hub/templates/languages/en/project-agent/AGENTS.md" = @('Project behavior rules live exclusively in the root `AGENTS.md`', "## Project Memory Language", "## Directory Responsibilities And Memory Routing", "## Progressive Load Order", "## Template Source And Conservative Refresh", '`.agents/context/README.md`', '`.agents/commands/README.md`', '`.agents/hub.lock.json`', "-RefreshUnmodifiedTemplates", "manual review")
        "knowledge-hub/templates/languages/zh-CN/project-agent/AGENTS.md" = @('项目行为规则仅以根 `AGENTS.md` 为准', "## 项目记忆语言", "## 目录职责与记忆路由", "## 渐进加载顺序", "## 模板来源与保守刷新", '`.agents/context/README.md`', '`.agents/commands/README.md`', '`.agents/hub.lock.json`', "-RefreshUnmodifiedTemplates", "manual review")
        "skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/en/project-agent/AGENTS.md" = @('Project behavior rules live exclusively in the root `AGENTS.md`', "## Project Memory Language", "## Directory Responsibilities And Memory Routing", "## Progressive Load Order", "## Template Source And Conservative Refresh", '`.agents/context/README.md`', '`.agents/commands/README.md`', '`.agents/hub.lock.json`', "-RefreshUnmodifiedTemplates", "manual review")
        "skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/zh-CN/project-agent/AGENTS.md" = @('项目行为规则仅以根 `AGENTS.md` 为准', "## 项目记忆语言", "## 目录职责与记忆路由", "## 渐进加载顺序", "## 模板来源与保守刷新", '`.agents/context/README.md`', '`.agents/commands/README.md`', '`.agents/hub.lock.json`', "-RefreshUnmodifiedTemplates", "manual review")
    }
    $commandGuidanceFiles = [ordered]@{
        "knowledge-hub/templates/languages/en/project-agent/commands/README.md" = @('`.agents/AGENTS.md`', "reusable high-frequency project workflows", "Do not invent commands", "Expected pass/fail evidence")
        "knowledge-hub/templates/languages/zh-CN/project-agent/commands/README.md" = @('`.agents/AGENTS.md`', "高频、可复用的项目工作流命令", "不要凭空发明命令", "预期通过/失败证据")
        "skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/en/project-agent/commands/README.md" = @('`.agents/AGENTS.md`', "reusable high-frequency project workflows", "Do not invent commands", "Expected pass/fail evidence")
        "skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/zh-CN/project-agent/commands/README.md" = @('`.agents/AGENTS.md`', "高频、可复用的项目工作流命令", "不要凭空发明命令", "预期通过/失败证据")
    }

    $guidanceExpectations = [ordered]@{}
    foreach ($relativePath in $rootGuidanceFiles.Keys) {
        $guidanceExpectations[$relativePath] = $rootGuidanceFiles[$relativePath]
    }
    foreach ($relativePath in $agentGuidanceFiles.Keys) {
        $guidanceExpectations[$relativePath] = $agentGuidanceFiles[$relativePath]
    }
    foreach ($relativePath in $commandGuidanceFiles.Keys) {
        $guidanceExpectations[$relativePath] = $commandGuidanceFiles[$relativePath]
    }
    foreach ($relativePath in $claudeShimFiles.Keys) {
        $guidanceExpectations[$relativePath] = $claudeShimFiles[$relativePath]
    }

    $guidanceMissing = New-Object 'System.Collections.Generic.List[string]'
    foreach ($relativePath in $guidanceExpectations.Keys) {
        $text = Get-FileText -RelativePath $relativePath
        foreach ($token in $guidanceExpectations[$relativePath]) {
            if (-not $text.Contains($token)) {
                $guidanceMissing.Add("$relativePath missing token: $token")
            }
        }
    }

    $nestedBehaviorForbidden = [ordered]@{
        "knowledge-hub/templates/languages/en/project-agent/AGENTS.md" = @("## Working Philosophy", "## Write Authorization Boundaries", "## Ambiguous Task Gate", "## Delivery Protocol & Working Loop", "## PR-Ready And Phase-Close Memory Sync Gate", "External writes include")
        "knowledge-hub/templates/languages/zh-CN/project-agent/AGENTS.md" = @("## 工作方式", "## 写入授权边界", "## 模糊任务入口", "## 交付流程", "## PR 就绪与阶段收尾记忆同步门禁", "外部写入包括")
        "skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/en/project-agent/AGENTS.md" = @("## Working Philosophy", "## Write Authorization Boundaries", "## Ambiguous Task Gate", "## Delivery Protocol & Working Loop", "## PR-Ready And Phase-Close Memory Sync Gate", "External writes include")
        "skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/zh-CN/project-agent/AGENTS.md" = @("## 工作方式", "## 写入授权边界", "## 模糊任务入口", "## 交付流程", "## PR 就绪与阶段收尾记忆同步门禁", "外部写入包括")
    }
    foreach ($relativePath in $nestedBehaviorForbidden.Keys) {
        $text = Get-FileText -RelativePath $relativePath
        foreach ($token in $nestedBehaviorForbidden[$relativePath]) {
            if ($text.Contains($token)) {
                $guidanceMissing.Add("$relativePath contains forbidden behavior-contract token: $token")
            }
        }
    }

    $script:evidence.agent_template_guidance = [ordered]@{
        checked_files = @($guidanceExpectations.Keys)
        missing = @($guidanceMissing.ToArray())
    }

    if ($guidanceMissing.Count -gt 0) {
        Add-Check "agent template startup guidance" "FAIL" "Root behavior contracts, project-memory guides, Claude shims, or command templates violate ownership/startup guidance." $evidence.agent_template_guidance
    }
    else {
        Add-Check "agent template startup guidance" "PASS" "Root templates own the full behavior contract, nested guides own only project-memory routing/provenance, and Claude/command startup surfaces remain aligned." $evidence.agent_template_guidance
    }
}
catch {
    Add-Check "agent template startup guidance" "FAIL" $_.Exception.Message
}

try {
    $contextTemplateRoots = @(
        "knowledge-hub/templates/languages",
        "skills/project-bootstrap/assets/knowledge-hub-template/templates/languages"
    )
    $contextIndexExpectations = [ordered]@{
        "en/project-agent/context/README.md" = @(
            "## Optional Entry Index",
            "| File | Summary | Keywords |",
            "public-safe and human-maintained",
            "telemetry-derived fields",
            '`last_accessed`',
            "automatic decay state"
        )
        "en/project-agent/context/business/README.md" = @(
            "## Entry Index",
            "| File | Summary | Keywords |",
            "public-safe discovery metadata",
            '`Maturity`',
            '`Reviewed`',
            "runtime telemetry",
            '`last_accessed`'
        )
        "en/project-agent/context/experience/README.md" = @(
            "## Entry Index",
            "| File | Summary | Keywords |",
            "public-safe discovery metadata",
            '`Maturity`',
            '`Reviewed`',
            "runtime telemetry",
            '`last_accessed`'
        )
        "en/project-agent/context/tech/README.md" = @(
            "## Entry Index",
            "| File | Summary | Keywords |",
            "human-maintained",
            "public-safe discovery metadata",
            '`Maturity` or `Reviewed`',
            '`last_accessed`'
        )
        "zh-CN/project-agent/context/README.md" = @(
            "example.md",
            "keyword-a, keyword-b",
            "public-safe",
            "telemetry-derived",
            "runtime usage counts",
            '`last_accessed`',
            "automatic decay state"
        )
        "zh-CN/project-agent/context/business/README.md" = @(
            "example-rule.md",
            "public-safe discovery metadata",
            '`Maturity`',
            '`Reviewed`',
            "runtime telemetry",
            "usage counts",
            '`last_accessed`'
        )
        "zh-CN/project-agent/context/experience/README.md" = @(
            "example-fix.md",
            "public-safe discovery metadata",
            '`Maturity`',
            '`Reviewed`',
            "runtime telemetry",
            "usage counts",
            '`last_accessed`'
        )
        "zh-CN/project-agent/context/tech/README.md" = @(
            "testing-conventions.md",
            "public-safe discovery metadata",
            '`Maturity`',
            '`Reviewed`',
            "usage counts",
            '`last_accessed`'
        )
    }

    $contextIndexMissing = New-Object 'System.Collections.Generic.List[string]'
    foreach ($root in $contextTemplateRoots) {
        foreach ($relativePath in $contextIndexExpectations.Keys) {
            $fullRelativePath = "{0}/{1}" -f $root, $relativePath
            $text = Get-FileText -RelativePath $fullRelativePath
            foreach ($token in $contextIndexExpectations[$relativePath]) {
                if (-not $text.Contains($token)) {
                    $contextIndexMissing.Add("$fullRelativePath missing token: $token")
                }
            }
        }
    }

    $script:evidence.context_index_guidance = [ordered]@{
        template_roots = @($contextTemplateRoots)
        checked_files_per_root = @($contextIndexExpectations.Keys)
        missing = @($contextIndexMissing.ToArray())
    }

    if ($contextIndexMissing.Count -gt 0) {
        Add-Check "context index guidance" "FAIL" "Project-agent context README templates are missing public-safe optional Entry Index guidance." $evidence.context_index_guidance
    }
    else {
        Add-Check "context index guidance" "PASS" "English and Simplified Chinese context README templates and project-bootstrap snapshots include public-safe optional Entry Index guidance without telemetry-derived fields." $evidence.context_index_guidance
    }
}
catch {
    Add-Check "context index guidance" "FAIL" $_.Exception.Message
}

try {
    $readmeZh = Get-FileText -RelativePath "README.md"
    $readmeEn = Get-FileText -RelativePath "README.en.md"
    $readmeCompat = Get-FileText -RelativePath "README.zh-CN.md"
    $releaseIndex = Get-FileText -RelativePath "docs/releases/README.md"

    $readmeExpectations = [ordered]@{
        "README.md" = @(
            "English: [README.en.md](README.en.md)",
            "简体中文（当前）",
            "当前版本：``$targetReleaseVersion``",
            "一句话理解",
            "5 分钟上手",
            "分层模型",
            "Profiles",
            "示例和常见任务路径",
            "Release notes",
            "project-bootstrap",
            "project-workspace"
        )
        "README.en.md" = @(
            "Simplified Chinese: [README.md](README.md)",
            "Current release: ``$targetReleaseVersion``",
            "One-Line Summary",
            "Five-Minute Start",
            "Layer Model",
            "Profiles",
            "Examples And Common Paths",
            "Release notes",
            "project-bootstrap",
            "project-workspace"
        )
        "README.zh-CN.md" = @(
            "简体中文首页已迁移到 [README.md](README.md)",
            "English version: [README.en.md](README.en.md)"
        )
        "docs/releases/README.md" = @(
            "[$targetReleaseVersion]($targetReleaseVersion.md)",
            "[v0.4.3](v0.4.3.md)",
            "[v0.4.2](v0.4.2.md)",
            "[v0.4.1](v0.4.1.md)",
            "[v0.4.0](v0.4.0.md)",
            "[v0.3.1](v0.3.1.md)",
            "[v0.3.0](v0.3.0.md)",
            "[v0.2.0](v0.2.0.md)",
            "[v0.1.0](v0.1.0.md)"
        )
    }

    $readmeMissing = New-Object 'System.Collections.Generic.List[string]'
    foreach ($relativePath in $readmeExpectations.Keys) {
        $text = switch ($relativePath) {
            "README.md" { $readmeZh }
            "README.en.md" { $readmeEn }
            "README.zh-CN.md" { $readmeCompat }
            default { $releaseIndex }
        }
        foreach ($token in $readmeExpectations[$relativePath]) {
            if (-not $text.Contains($token)) {
                $readmeMissing.Add("$relativePath missing token: $token")
            }
        }
    }

    if ($readmeMissing.Count -gt 0) {
        Add-Check "readme language entrypoints" "FAIL" "README or release index entrypoint assertions failed." @($readmeMissing.ToArray())
    }
    else {
        Add-Check "readme language entrypoints" "PASS" "Simplified Chinese homepage, English mirror, compatibility redirect, and release index are wired." ([ordered]@{
            checked_files = @($readmeExpectations.Keys)
        })
    }
}
catch {
    Add-Check "readme language entrypoints" "FAIL" $_.Exception.Message
}

try {
    $targetReleaseNotesPath = "docs/releases/$targetReleaseVersion.md"
    $alignmentFiles = [ordered]@{
        "README.md" = Get-FileText -RelativePath "README.md"
        "README.en.md" = Get-FileText -RelativePath "README.en.md"
        $targetReleaseNotesPath = Get-FileText -RelativePath $targetReleaseNotesPath
        "docs/release-readiness.md" = Get-FileText -RelativePath "docs/release-readiness.md"
        "docs/releases/README.md" = Get-FileText -RelativePath "docs/releases/README.md"
    }

    $alignmentExpectations = [ordered]@{
        "README.md" = @("当前版本：``$targetReleaseVersion``")
        "README.en.md" = @("Current release: ``$targetReleaseVersion``")
        $targetReleaseNotesPath = @(
            "# $targetReleaseVersion Release Notes",
            "Status: public release",
            "Published GitHub Release:",
            "Tag target:"
        )
        "docs/release-readiness.md" = @(
            "Status: ``$targetReleaseVersion`` published public release",
            "GitHub Release ``$targetReleaseVersion`` has been published"
        )
        "docs/releases/README.md" = @("[$targetReleaseVersion]($targetReleaseVersion.md)")
    }

    $alignmentFailures = New-Object 'System.Collections.Generic.List[string]'
    foreach ($relativePath in $alignmentExpectations.Keys) {
        $text = [string]$alignmentFiles[$relativePath]
        foreach ($token in $alignmentExpectations[$relativePath]) {
            if (-not $text.Contains($token)) {
                $alignmentFailures.Add("$relativePath missing target-version token: $token")
            }
        }
    }

    $staleFinalizationTokens = @(
        "release-prep draft",
        "release-prep candidate",
        "release prep draft",
        "release prep candidate",
        "not yet tagged",
        "not yet published",
        "latest published public release",
        "fill with #",
        "to be filled",
        "to be confirmed",
        "maintainer:"
    )
    foreach ($relativePath in @($targetReleaseNotesPath, "docs/release-readiness.md")) {
        $text = [string]$alignmentFiles[$relativePath]
        foreach ($token in $staleFinalizationTokens) {
            if ($text -like ("*{0}*" -f $token)) {
                $alignmentFailures.Add("$relativePath contains pre-publication wording: $token")
            }
        }
    }

    $releaseIndexLines = @(([string]$alignmentFiles["docs/releases/README.md"]) -split "`r?`n")
    $targetIndexToken = "[{0}]({0}.md)" -f $targetReleaseVersion
    $targetIndexLines = @($releaseIndexLines | Where-Object { $_.Contains($targetIndexToken) })
    if ($targetIndexLines.Count -eq 0) {
        $alignmentFailures.Add("docs/releases/README.md missing target release index entry for $targetReleaseVersion")
    }
    foreach ($line in $targetIndexLines) {
        if ($line -match '(?i)release[- ]prep|draft|candidate|not yet|unpublished') {
            $alignmentFailures.Add("docs/releases/README.md target release entry still looks pre-publication: $line")
        }
    }

    if ($alignmentFailures.Count -gt 0) {
        Add-Check "publish-ready release alignment" "FAIL" "Target release metadata is not publish-ready." ([ordered]@{
            target_version = $targetReleaseVersion
            failures = @($alignmentFailures.ToArray())
        })
    }
    else {
        Add-Check "publish-ready release alignment" "PASS" "README, release notes, release readiness, and release index match the target published version." ([ordered]@{
            target_version = $targetReleaseVersion
            checked_files = @($alignmentExpectations.Keys)
        })
    }
}
catch {
    Add-Check "publish-ready release alignment" "FAIL" $_.Exception.Message
}

try {
    $shellStrategy = Get-FileText -RelativePath "docs/shell-strategy.md"
    $releaseProcess = Get-FileText -RelativePath "docs/release-process.md"
    $workflow = Get-FileText -RelativePath ".github/workflows/release-validation.yml"
    $readme = Get-FileText -RelativePath "README.md"
    $readmeEn = Get-FileText -RelativePath "README.en.md"
    $shellExpectations = [ordered]@{
        "docs/shell-strategy.md" = @("PowerShell 7.6", "pwsh -NoProfile -NonInteractive -File", "No Bash or Zsh wrappers", "canonical", ".ps1")
        "docs/release-process.md" = @("Shell strategy", "Bash or Zsh wrappers", "canonical", ".ps1")
        "README.md" = @("Shell strategy")
        "README.en.md" = @("Shell strategy")
    }
    $shellMissing = New-Object 'System.Collections.Generic.List[string]'
    foreach ($relativePath in $shellExpectations.Keys) {
        $text = switch ($relativePath) {
            "docs/shell-strategy.md" { $shellStrategy }
            "docs/release-process.md" { $releaseProcess }
            "README.md" { $readme }
            "README.en.md" { $readmeEn }
        }
        foreach ($token in $shellExpectations[$relativePath]) {
            if ($text -notlike ("*{0}*" -f $token)) {
                $shellMissing.Add("$relativePath missing token: $token")
            }
        }
    }

    $workflowTokens = @("windows-latest", "ubuntu-latest", "macos-latest", "shell: pwsh")
    foreach ($token in $workflowTokens) {
        if ($workflow -notlike ("*{0}*" -f $token)) {
            $shellMissing.Add(".github/workflows/release-validation.yml missing token: $token")
        }
    }

    if ($shellMissing.Count -gt 0) {
        Add-Check "cross-platform shell strategy" "FAIL" "Shell strategy docs or CI shell entries are inconsistent." @($shellMissing.ToArray())
    }
    else {
        Add-Check "cross-platform shell strategy" "PASS" "PowerShell host support and deferred non-PowerShell wrapper policy are documented and aligned with CI." ([ordered]@{
            docs = @($shellExpectations.Keys)
            ci_tokens = @($workflowTokens)
        })
    }
}
catch {
    Add-Check "cross-platform shell strategy" "FAIL" $_.Exception.Message
}

try {
    $releaseNotes = Get-FileText -RelativePath "docs/releases/v0.2.0.md"
    $releaseTokens = @(
        "v0.2.0",
        "zero deferred",
        "ProjectLanguage",
        "spec completeness validator",
        "domain-pack scaffold",
        "PASS=21 FAIL=0 WARN=0 DEFERRED=0"
    )
    $missingReleaseTokens = @(Get-MissingRequiredText -Text $releaseNotes -RequiredText $releaseTokens)
    if ($missingReleaseTokens.Count -gt 0) {
        Add-Check "v0.2.0 release notes" "FAIL" "Release notes are missing required v0.2.0 summary tokens." @($missingReleaseTokens)
    }
    else {
        $staleReleaseBodyTokens = @(
            "Status: release candidate",
            "Expected local result for the release candidate"
        )
        $staleReleaseBodyMatches = @($staleReleaseBodyTokens | Where-Object { $releaseNotes -like "*$_*" })
        if ($staleReleaseBodyMatches.Count -gt 0) {
            Add-Check "v0.2.0 release notes" "FAIL" "Release notes still contain stale release-candidate wording after publication." @($staleReleaseBodyMatches)
        }
        else {
            Add-Check "v0.2.0 release notes" "PASS" "v0.2.0 release notes summarize closeout features, historical validation, and public boundary."
        }
    }
}
catch {
    Add-Check "v0.2.0 release notes" "FAIL" $_.Exception.Message
}

try {
    $releaseNotes = Get-FileText -RelativePath "docs/releases/v0.3.0.md"
    $releaseTokens = @(
        "v0.3.0",
        "manifest-based uninstall",
        "localized context discovery headings",
        "Bilingual Public/Private Routing",
        "context gate large context benchmark",
        "PASS=32 FAIL=0 WARN=0 DEFERRED=0"
    )
    $missingReleaseTokens = @(Get-MissingRequiredText -Text $releaseNotes -RequiredText $releaseTokens)
    if ($missingReleaseTokens.Count -gt 0) {
        Add-Check "v0.3.0 release notes" "FAIL" "Release notes are missing required v0.3.0 summary tokens." @($missingReleaseTokens)
    }
    else {
        $staleReleaseBodyTokens = @(
            "Expected local result for the release candidate"
        )
        $staleReleaseBodyMatches = @($staleReleaseBodyTokens | Where-Object { $releaseNotes -like "*$_*" })
        if ($staleReleaseBodyMatches.Count -gt 0) {
            Add-Check "v0.3.0 release notes" "FAIL" "Release notes still contain stale release-candidate wording after publication." @($staleReleaseBodyMatches)
        }
        else {
            Add-Check "v0.3.0 release notes" "PASS" "v0.3.0 release notes summarize backlog remediation, issue fixes, historical validation, and public boundary."
        }
    }
}
catch {
    Add-Check "v0.3.0 release notes" "FAIL" $_.Exception.Message
}

try {
    $releaseNotes = Get-FileText -RelativePath "docs/releases/v0.3.1.md"
    $releaseTokens = @(
        "v0.3.1",
        "Workflow Kernel",
        "Public Reader Review",
        "actions/checkout@v6",
        "actions/upload-artifact@v7",
        "PASS=33 FAIL=0 WARN=0 DEFERRED=0"
    )
    $missingReleaseTokens = @(Get-MissingRequiredText -Text $releaseNotes -RequiredText $releaseTokens)
    if ($missingReleaseTokens.Count -gt 0) {
        Add-Check "v0.3.1 release notes" "FAIL" "Release notes are missing required v0.3.1 summary tokens." @($missingReleaseTokens)
    }
    else {
        Add-Check "v0.3.1 release notes" "PASS" "v0.3.1 release notes summarize positioning stabilization, release hygiene, CI runtime maintenance, validation expectation, and public boundary."
    }
}
catch {
    Add-Check "v0.3.1 release notes" "FAIL" $_.Exception.Message
}

try {
    $releaseNotes = Get-FileText -RelativePath "docs/releases/v0.4.0.md"
    $releaseTokens = @(
        "v0.4.0",
        "conservative",
        "zh-CN",
        "proposal-first",
        "backup-first",
        "narrative migration",
        "PASS=40 FAIL=0 WARN=0 DEFERRED=0"
    )
    $missingReleaseTokens = @(Get-MissingRequiredText -Text $releaseNotes -RequiredText $releaseTokens)
    if ($missingReleaseTokens.Count -gt 0) {
        Add-Check "v0.4.0 release notes" "FAIL" "Release notes are missing required v0.4.0 summary tokens." @($missingReleaseTokens)
    }
    else {
        Add-Check "v0.4.0 release notes" "PASS" "v0.4.0 release notes summarize language migration, proposal/backup safety, validation expectation, and public boundary."
    }
}
catch {
    Add-Check "v0.4.0 release notes" "FAIL" $_.Exception.Message
}

try {
    $releaseNotes = Get-FileText -RelativePath "docs/releases/v0.4.1.md"
    $releaseTokens = @(
        "v0.4.1",
        "project-memory template authority",
        "knowledge-hub/templates/project-memory",
        "bundled snapshot",
        "skills/project-bootstrap/templates/project-memory",
        "PASS=40 FAIL=0 WARN=0 DEFERRED=0"
    )
    $missingReleaseTokens = @(Get-MissingRequiredText -Text $releaseNotes -RequiredText $releaseTokens)
    if ($missingReleaseTokens.Count -gt 0) {
        Add-Check "v0.4.1 release notes" "FAIL" "Release notes are missing required v0.4.1 summary tokens." @($missingReleaseTokens)
    }
    else {
        Add-Check "v0.4.1 release notes" "PASS" "v0.4.1 release notes summarize template authority consolidation, bundled snapshot alignment, validation expectation, and public boundary."
    }
}
catch {
    Add-Check "v0.4.1 release notes" "FAIL" $_.Exception.Message
}

try {
    $releaseNotes = Get-FileText -RelativePath "docs/releases/v0.4.2.md"
    $releaseTokens = @(
        "v0.4.2",
        "language-scoped model",
        "templates/languages",
        "project-root|project-agent",
        "Plain bootstrap now defaults to English",
        "minimal",
        "recommended",
        "full",
        "dev",
        "PASS=40 FAIL=0 WARN=0 DEFERRED=0"
    )
    $missingReleaseTokens = @(Get-MissingRequiredText -Text $releaseNotes -RequiredText $releaseTokens)
    if ($missingReleaseTokens.Count -gt 0) {
        Add-Check "v0.4.2 release notes" "FAIL" "Release notes are missing required v0.4.2 summary tokens." @($missingReleaseTokens)
    }
    else {
        Add-Check "v0.4.2 release notes" "PASS" "v0.4.2 release notes summarize language-scoped template convergence, bootstrap behavior, validation expectation, and public boundary."
    }
}
catch {
    Add-Check "v0.4.2 release notes" "FAIL" $_.Exception.Message
}

try {
    $releaseNotes = Get-FileText -RelativePath "docs/releases/v0.4.3.md"
    $releaseTokens = @(
        "v0.4.3",
        "public release",
        "post-convergence stabilization",
        "Issue #53",
        "Issue #54",
        "Issue #55",
        "Issue #56",
        "Issue #57",
        "PR #63",
        "PASS=46 FAIL=0 WARN=0 DEFERRED=0",
        "25841179794",
        "26072b7f8e25e2a5b1092b6af45d47ae1c43cac8",
        "Published GitHub Release"
    )
    $missingReleaseTokens = @(Get-MissingRequiredText -Text $releaseNotes -RequiredText $releaseTokens)
    if ($missingReleaseTokens.Count -gt 0) {
        Add-Check "v0.4.3 release notes" "FAIL" "Release notes are missing required v0.4.3 published-release tokens." @($missingReleaseTokens)
    }
    else {
        $staleReleasePrepTokens = @(
            "release prep draft",
            "This document is a draft",
            "not a published release",
            "Hosted release validation must pass on the draft PR",
            "Before publishing",
            "Do not tag or publish"
        )
        $staleReleasePrepMatches = @($staleReleasePrepTokens | Where-Object { $releaseNotes -like "*$_*" })
        if ($staleReleasePrepMatches.Count -gt 0) {
            Add-Check "v0.4.3 release notes" "FAIL" "Release notes still contain release-prep-only wording after v0.4.3 publication." @($staleReleasePrepMatches)
        }
        else {
            Add-Check "v0.4.3 release notes" "PASS" "v0.4.3 release notes summarize published stabilization scope, validation evidence, linked work, and public boundary."
        }
    }
}
catch {
    Add-Check "v0.4.3 release notes" "FAIL" $_.Exception.Message
}

try {
    $releaseNotes = Get-FileText -RelativePath "docs/releases/v0.4.4.md"
    $releaseTokens = @(
        "v0.4.4",
        "Status: public release",
        "GitHub Release title",
        "Published GitHub Release:",
        "Tag target: ``71fabb372a4cbc024f07c920a0c17b903a77afc2``",
        "Copyable GitHub Release Body",
        "RELEASE_BODY_START",
        "RELEASE_BODY_END",
        "English",
        "stabilization / docs / governance",
        "Issue #23",
        "PR #87",
        "PASS=51 FAIL=0 WARN=0 DEFERRED=0",
        "26269908157",
        "71fabb372a4cbc024f07c920a0c17b903a77afc2",
        "Upgrade / Usage Impact",
        "Risk / Rollback",
        "Internal Release Record",
        "Release Boundary"
    )
    $missingReleaseTokens = @($releaseTokens | Where-Object { -not $releaseNotes.Contains($_) })
    if ($missingReleaseTokens.Count -gt 0) {
        Add-Check "v0.4.4 published release notes" "FAIL" "Release notes are missing required v0.4.4 published-release tokens." @($missingReleaseTokens)
    }
    else {
        $staleReleasePrepTokens = @(
            "release-prep draft",
            "release-prep candidate",
            "not yet tagged",
            "not yet published",
            "Hosted checks for the release-prep PR",
            "do not create the tag",
            "Before a tag",
            "Maintainer Record",
            "维护者记录",
            "维护者建议",
            "after merging",
            "合并后",
            "no additional commits required",
            "无需额外提交"
        )
        $staleReleasePrepMatches = @($staleReleasePrepTokens | Where-Object { $releaseNotes -like "*$_*" })
        if ($staleReleasePrepMatches.Count -gt 0) {
            Add-Check "v0.4.4 published release notes" "FAIL" "Release notes still contain pre-publication wording after v0.4.4 publication." @($staleReleasePrepMatches)
        }
        else {
            Add-Check "v0.4.4 published release notes" "PASS" "v0.4.4 release notes summarize published scope, validation evidence, usage impact, risk, and release boundary."
        }
    }
}
catch {
    Add-Check "v0.4.4 published release notes" "FAIL" $_.Exception.Message
}

try {
    $releaseNotes = Get-FileText -RelativePath "docs/releases/v0.4.5.md"
    $releaseTokens = @(
        "v0.4.5",
        "Status: public release",
        "GitHub Release title",
        "Published GitHub Release:",
        "Tag target:",
        "Copyable GitHub Release Body",
        "RELEASE_BODY_START",
        "RELEASE_BODY_END",
        "English",
        "maintenance / compatibility / governance",
        "Issue #102",
        "PR #104",
        "PASS=53 FAIL=0 WARN=0 DEFERRED=0",
        "Upgrade / Usage Impact",
        "Risk / Rollback",
        "Internal Release Record",
        "Release Boundary"
    )
    $missingReleaseTokens = @($releaseTokens | Where-Object { -not $releaseNotes.Contains($_) })
    if ($missingReleaseTokens.Count -gt 0) {
        Add-Check "v0.4.5 published release notes" "FAIL" "Release notes are missing required v0.4.5 published-release tokens." @($missingReleaseTokens)
    }
    else {
        $staleReleasePrepTokens = @(
            "release-prep draft",
            "release-prep candidate",
            "not yet tagged",
            "not yet published",
            "in preparation",
            "pending maintainer",
            "Hosted checks for the release-prep PR",
            "do not create the tag",
            "Before a tag",
            "fill with #",
            "after merge",
            "After merging",
            "Maintainer Record",
            "维护者记录",
            "维护者建议",
            "no additional commits required",
            "无需额外提交",
            "maintainer:",
            "to be filled",
            "to be confirmed"
        )
        $staleReleasePrepMatches = @($staleReleasePrepTokens | Where-Object { $releaseNotes -like "*$_*" })
        if ($staleReleasePrepMatches.Count -gt 0) {
            Add-Check "v0.4.5 published release notes" "FAIL" "Release notes still contain pre-publication wording after v0.4.5 publication." @($staleReleasePrepMatches)
        }
        else {
            Add-Check "v0.4.5 published release notes" "PASS" "v0.4.5 release notes summarize published scope, validation evidence, usage impact, risk, and release boundary."
        }
    }
}
catch {
    Add-Check "v0.4.5 published release notes" "FAIL" $_.Exception.Message
}

try {
    $releaseNotes = Get-FileText -RelativePath "docs/releases/v0.4.6.md"
    $releaseTokens = @(
        "v0.4.6",
        "Status: public release",
        "GitHub Release title",
        "Published GitHub Release:",
        "Tag target:",
        "Copyable GitHub Release Body",
        "RELEASE_BODY_START",
        "RELEASE_BODY_END",
        "English",
        "documentation / governance / release-hygiene",
        "Issue #98",
        "Issue #100",
        "Issue #113",
        "PR #111",
        "PR #112",
        "PR #114",
        "PASS=54 FAIL=0 WARN=0 DEFERRED=0",
        "Upgrade / Usage Impact",
        "Risk / Rollback",
        "Internal Release Record",
        "Merge-to-publish: yes",
        "Release Boundary"
    )
    $missingReleaseTokens = @($releaseTokens | Where-Object { -not $releaseNotes.Contains($_) })
    if ($missingReleaseTokens.Count -gt 0) {
        Add-Check "v0.4.6 published release notes" "FAIL" "Release notes are missing required v0.4.6 published-release tokens." @($missingReleaseTokens)
    }
    else {
        $staleReleasePrepTokens = @(
            "release-prep draft",
            "release-prep candidate",
            "not yet tagged",
            "not yet published",
            "in preparation",
            "pending maintainer",
            "Hosted checks for the release-prep PR",
            "do not create the tag",
            "Before a tag",
            "fill with #",
            "after merge",
            "After merging",
            "Maintainer Record",
            "维护者记录",
            "维护者建议",
            "no additional commits required",
            "无需额外提交",
            "maintainer:",
            "to be filled",
            "to be confirmed"
        )
        $staleReleasePrepMatches = @($staleReleasePrepTokens | Where-Object { $releaseNotes -like "*$_*" })
        if ($staleReleasePrepMatches.Count -gt 0) {
            Add-Check "v0.4.6 published release notes" "FAIL" "Release notes still contain pre-publication wording after v0.4.6 publication." @($staleReleasePrepMatches)
        }
        else {
            Add-Check "v0.4.6 published release notes" "PASS" "v0.4.6 release notes summarize published scope, validation evidence, usage impact, risk, and release boundary."
        }
    }
}
catch {
    Add-Check "v0.4.6 published release notes" "FAIL" $_.Exception.Message
}

}
