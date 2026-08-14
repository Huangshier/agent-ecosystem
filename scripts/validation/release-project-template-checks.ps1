# Invoke-ReleaseValidationLanguageTemplateChecks: No parameters; runs language policy, template auto-write checks in the original order.
# Bilingual public/private routing check was extracted to release-template-language-checks.ps1 (Phase 3)
# and is now invoked via Invoke-ReleaseTemplateLanguageChecks.
function Invoke-ReleaseValidationLanguageTemplateChecks {

try {
    $repoGuide = Get-FileText -RelativePath "AGENTS.md"
    $languagePolicyPresent = $repoGuide -match '(?m)^## Project Language Policy\s*$'
    $c33WorkspaceBootstrapPresent = $false
    $autoWriteEvidence = @()
    $fileTemplateEvidence = @()
    $fallbackEvidence = @()
    $smokeEvidence = @($evidence.runtime_smoke | Where-Object {
        if ($null -eq $_) {
            return $false
        }
        $projectValue = if ($_ -is [System.Collections.IDictionary]) {
            [string]$_["project"]
        } else {
            [string]$_.project
        }
        return -not [string]::IsNullOrWhiteSpace($projectValue)
    })
    if ($smokeEvidence.Count -gt 0) {
        $projectDir = if ($smokeEvidence[0] -is [System.Collections.IDictionary]) {
            [string]$smokeEvidence[0]["project"]
        } else {
            [string]$smokeEvidence[0].project
        }
        $lockPath = Join-PathParts $projectDir ".agents" "hub.lock.json"
        if (Test-Path -LiteralPath $lockPath -PathType Leaf) {
            $smokeLock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
            $c33WorkspaceBootstrapPresent = ([string]$smokeLock.workspace_model -ceq "c3.3") -and
                (Test-Path -LiteralPath (Join-PathParts $projectDir "AGENTS.md")) -and
                (Test-Path -LiteralPath (Join-PathParts $projectDir ".agents" "README.md"))
        }
    }

    function Test-ProjectLanguageBootstrap {
        param(
            [Parameter(Mandatory = $true)][string]$Language,
            [Parameter(Mandatory = $true)][string]$ExpectedLockLanguage
        )

        if ([string]::IsNullOrWhiteSpace($script:recommendedCopyRuntime)) {
            throw "Recommended copy runtime was not created."
        }

        $projectName = "language-auto-write-{0}" -f ($Language -replace '[^A-Za-z0-9-]', '-')
        $languageProjectDir = Join-PathParts $scratchRootFull $projectName
        New-Item -ItemType Directory -Force -Path $languageProjectDir | Out-Null
        Assert-PathInsideRoot -Path $languageProjectDir -Root $scratchRootFull

        $hubDir = Join-PathParts $script:recommendedCopyRuntime "knowledge-hub"
        $bootstrapScript = Join-PathParts $script:recommendedCopyRuntime "skills" "project-bootstrap" "scripts" "bootstrap_project.ps1"
        & $bootstrapScript -ProjectDir $languageProjectDir -HubDir $hubDir -ProjectLanguage $Language -SkipMemoryUpgradeAnalysis | Out-Host

        $lock = Get-Content -LiteralPath (Join-PathParts $languageProjectDir ".agents" "hub.lock.json") -Raw | ConvertFrom-Json
        $missing = New-Object 'System.Collections.Generic.List[string]'
        if ([string]$lock.project_language -cne $ExpectedLockLanguage) {
            $missing.Add("project_language=$($lock.project_language) expected=$ExpectedLockLanguage")
        }
        if ([string]$lock.workspace_model -cne "c3.3" -or [string]$lock.workspace_state -cne "active") {
            $missing.Add("workspace_model=$($lock.workspace_model)/$($lock.workspace_state) expected c3.3/active")
        }
        foreach ($relative in @("AGENTS.md", ".agents/README.md", ".agents/work", ".agents/context", ".agents/procedures", ".agents/skills", "docs/specs")) {
            if (-not (Test-Path -LiteralPath (Join-PathParts $languageProjectDir $relative))) {
                $missing.Add("$relative missing")
            }
        }

        if ($missing.Count -gt 0) {
            throw ("C3.3 language bootstrap failed for {0}: {1}" -f $Language, ($missing.ToArray() -join "; "))
        }

        return [ordered]@{
            language = $Language
            project = $languageProjectDir
            project_language = [string]$lock.project_language
            workspace_model = [string]$lock.workspace_model
            workspace_state = [string]$lock.workspace_state
        }
    }

    function Test-ProjectMemoryTemplateFiles {
        param(
            [Parameter(Mandatory = $true)][string]$RuntimeDir
        )

        $authorityRoot = Join-PathParts $RuntimeDir "knowledge-hub" "templates" "languages"
        $snapshotRoot = Join-PathParts $RuntimeDir "skills" "project-bootstrap" "assets" "knowledge-hub-template" "templates" "languages"
        $legacyRoots = @(
            (Join-PathParts $RuntimeDir "knowledge-hub" "templates" "project-root"),
            (Join-PathParts $RuntimeDir "knowledge-hub" "templates" "project-agent"),
            (Join-PathParts $RuntimeDir "knowledge-hub" "templates" "project-memory"),
            (Join-PathParts $RuntimeDir "skills" "project-bootstrap" "assets" "knowledge-hub-template" "templates" "project-root"),
            (Join-PathParts $RuntimeDir "skills" "project-bootstrap" "assets" "knowledge-hub-template" "templates" "project-agent"),
            (Join-PathParts $RuntimeDir "skills" "project-bootstrap" "assets" "knowledge-hub-template" "templates" "project-memory"),
            (Join-PathParts $RuntimeDir "skills" "project-bootstrap" "templates" "project-memory")
        )
        $requiredRelativePaths = @(
            "project-root/AGENTS.md",
            "project-root/CLAUDE.md",
            "project-root/.claude/settings.json",
            "project-root/.claude/guardrails/README.md",
            "project-root/.claude/guardrails/profile.json",
            "project-root/.claude/hooks/README.md",
            "project-root/.claude/hooks/guardrail.ps1",
            "project-root/docs/specs/README.md",
            "project-root/docs/specs/_templates/spec-lite.md",
            "project-root/docs/specs/_templates/tasks-lite.md",
            "project-agent/AGENTS.md",
            "project-agent/process.txt",
            "project-agent/plan.md",
            "project-agent/notes.md",
            "project-agent/commands/README.md",
            "project-agent/commands/test-workflow.md",
            "project-agent/commands/skills.md",
            "project-agent/context/README.md",
            "project-agent/context/tech/README.md",
            "project-agent/context/tech/testing-conventions.md",
            "project-agent/context/business/README.md",
            "project-agent/context/experience/README.md",
            "project-agent/context/experience/cases/README.md",
            "project-agent/context/experience/cases/case_template.md"
        )

        $missing = New-Object 'System.Collections.Generic.List[string]'
        $mismatched = New-Object 'System.Collections.Generic.List[string]'
        $testingGuidanceErrors = New-Object 'System.Collections.Generic.List[string]'
        $learningDepositGuidanceErrors = New-Object 'System.Collections.Generic.List[string]'
        $ownershipGuidanceErrors = New-Object 'System.Collections.Generic.List[string]'
        foreach ($language in @("en", "zh-CN")) {
            foreach ($relativePath in $requiredRelativePaths) {
                $authorityPath = Join-PathParts $authorityRoot $language $relativePath
                $snapshotPath = Join-PathParts $snapshotRoot $language $relativePath
                if (-not (Test-Path -LiteralPath $authorityPath)) {
                    $missing.Add("authority/$language/$relativePath")
                }
                if (-not (Test-Path -LiteralPath $snapshotPath)) {
                    $missing.Add("snapshot/$language/$relativePath")
                }
                if ((Test-Path -LiteralPath $authorityPath) -and (Test-Path -LiteralPath $snapshotPath)) {
                    $authorityHash = (Get-FileHash -LiteralPath $authorityPath -Algorithm SHA256).Hash
                    $snapshotHash = (Get-FileHash -LiteralPath $snapshotPath -Algorithm SHA256).Hash
                    if ($authorityHash -ne $snapshotHash) {
                        $mismatched.Add("$language/$relativePath")
                    }
                }
            }
        }

        $learningDepositExpectations = [ordered]@{
            "en" = [ordered]@{
                delivery_heading = "## Delivery Protocol & Working Loop"
                gate_heading = "## PR-Ready And Phase-Close Memory Sync Gate"
                next_heading = "## Tooling Constraints"
                delivery_tokens = @(
                    "Session Learning Extraction",
                    "user correction",
                    "rework after a validation failure",
                    "scope drift",
                    "skipped acceptance",
                    "tool workaround",
                    "up to 3 deposit suggestions",
                    "user confirmation",
                    "project-local lessons",
                    "candidate intake / triage",
                    "Do not auto-promote",
                    "If no trigger occurred"
                )
                gate_tokens = @(
                    "learning-deposit check",
                    "new trigger events",
                    "Session Learning Extraction",
                    "no-auto-promotion"
                )
            }
            "zh-CN" = [ordered]@{
                delivery_heading = "## 交付流程"
                gate_heading = "## PR 就绪与阶段收尾记忆同步门禁"
                next_heading = "## 工具约束"
                delivery_tokens = @(
                    "Session Learning Extraction",
                    "用户纠正",
                    "验证失败后重做",
                    "范围漂移",
                    "跳过验收",
                    "工具绕行",
                    "最多 3 条沉淀建议",
                    "用户确认",
                    "项目本地经验",
                    "candidate intake / triage",
                    "禁止自动 promotion",
                    "没有触发事件"
                )
                gate_tokens = @(
                    "经验沉淀判断",
                    "新触发事件",
                    "Session Learning Extraction",
                    "禁止自动 promotion"
                )
            }
        }
        foreach ($language in @("en", "zh-CN")) {
            $expectation = $learningDepositExpectations[$language]
            foreach ($templateKind in @("authority", "snapshot")) {
                $templateRoot = if ($templateKind -eq "authority") { $authorityRoot } else { $snapshotRoot }
                $rootGuidePath = Join-PathParts $templateRoot $language "project-root" "AGENTS.md"
                if (-not (Test-Path -LiteralPath $rootGuidePath)) {
                    $learningDepositGuidanceErrors.Add("missing $templateKind/$language/project-root/AGENTS.md")
                    continue
                }
                $rootGuideText = [System.IO.File]::ReadAllText($rootGuidePath, [System.Text.Encoding]::UTF8)
                $deliveryStart = $rootGuideText.IndexOf([string]$expectation.delivery_heading, [System.StringComparison]::Ordinal)
                $gateStart = $rootGuideText.IndexOf([string]$expectation.gate_heading, [System.StringComparison]::Ordinal)
                $nextStart = $rootGuideText.IndexOf([string]$expectation.next_heading, [System.StringComparison]::Ordinal)
                if ($deliveryStart -lt 0 -or $gateStart -le $deliveryStart -or $nextStart -le $gateStart) {
                    $learningDepositGuidanceErrors.Add("$templateKind/$language project-root learning-deposit section boundaries are missing or out of order")
                    continue
                }
                $deliveryText = $rootGuideText.Substring($deliveryStart, $gateStart - $deliveryStart)
                $gateText = $rootGuideText.Substring($gateStart, $nextStart - $gateStart)
                foreach ($token in $expectation.delivery_tokens) {
                    if (-not $deliveryText.Contains([string]$token)) {
                        $learningDepositGuidanceErrors.Add("$templateKind/$language Delivery Protocol missing learning-deposit token: $token")
                    }
                }
                foreach ($token in $expectation.gate_tokens) {
                    if (-not $gateText.Contains([string]$token)) {
                        $learningDepositGuidanceErrors.Add("$templateKind/$language PR-ready gate missing learning-deposit token: $token")
                    }
                }
            }
        }

        $ownershipExpectations = [ordered]@{
            "en" = [ordered]@{
                root_required = @(
                    "single authoritative project behavior contract",
                    "## Working Philosophy",
                    "## On Stopping to Ask",
                    "## Write Authorization Boundaries",
                    "## Ambiguous Task Gate",
                    "## Engineering Memory Refresh, Migration, And Reset",
                    "## Global Experience Discovery",
                    "toolchains, host environments",
                    '`keywords` first, then `title`',
                    "Read only the matched entries",
                    "If the index is missing or no entry matches, fail soft",
                    "business logic, hardware wiring, protocol implementation",
                    "existing intake / triage workflow; never",
                    "promote them automatically",
                    "## Verification And Completion",
                    "## Delivery Protocol & Working Loop",
                    "## PR-Ready And Phase-Close Memory Sync Gate",
                    "## Project Work Packages"
                )
                nested_required = @(
                    'Project behavior rules live exclusively in the root `AGENTS.md`',
                    "## Project Memory Language",
                    "## Directory Responsibilities And Memory Routing",
                    "## Progressive Load Order",
                    "## Template Source And Conservative Refresh",
                    '`.agents/hub.lock.json`',
                    "-RefreshUnmodifiedTemplates",
                    "manual review"
                )
                nested_forbidden = @(
                    "## Working Philosophy",
                    "## On Stopping to Ask",
                    "## Write Authorization Boundaries",
                    "## Ambiguous Task Gate",
                    "## Global Experience Discovery",
                    "## Verification And Completion",
                    "## Delivery Protocol & Working Loop",
                    "## PR-Ready And Phase-Close Memory Sync Gate",
                    "## Project Work Packages",
                    "External writes include",
                    "Local commit is allowed only"
                )
            }
            "zh-CN" = [ordered]@{
                root_required = @(
                    "唯一权威的项目行为契约",
                    "## 工作方式",
                    "## 何时停下来询问",
                    "## 写入授权边界",
                    "## 模糊任务入口",
                    "## 工程记忆刷新、迁移与重置",
                    "## 全局经验发现",
                    "toolchain、host、shell、build",
                    '匹配条目的 `keywords`，再匹配 `title`',
                    "只读取命中的条目",
                    "索引缺失或无匹配时 fail-soft",
                    "业务逻辑、硬件接线、协议实现或模块设计",
                    "既有 intake / triage",
                    "禁止自动 promotion",
                    "## 验证与完成",
                    "## 交付流程",
                    "## PR 就绪与阶段收尾记忆同步门禁",
                    "## 项目工作包"
                )
                nested_required = @(
                    '项目行为规则仅以根 `AGENTS.md` 为准',
                    "## 项目记忆语言",
                    "## 目录职责与记忆路由",
                    "## 渐进加载顺序",
                    "## 模板来源与保守刷新",
                    '`.agents/hub.lock.json`',
                    "-RefreshUnmodifiedTemplates",
                    "manual review"
                )
                nested_forbidden = @(
                    "## 工作方式",
                    "## 何时停下来询问",
                    "## 写入授权边界",
                    "## 模糊任务入口",
                    "## 全局经验发现",
                    "## 验证与完成",
                    "## 交付流程",
                    "## PR 就绪与阶段收尾记忆同步门禁",
                    "## 项目工作包",
                    "外部写入包括",
                    "本地 commit 仅在"
                )
            }
        }
        foreach ($language in @("en", "zh-CN")) {
            $expectation = $ownershipExpectations[$language]
            foreach ($templateKind in @("authority", "snapshot")) {
                $templateRoot = if ($templateKind -eq "authority") { $authorityRoot } else { $snapshotRoot }
                $rootGuidePath = Join-PathParts $templateRoot $language "project-root" "AGENTS.md"
                $nestedGuidePath = Join-PathParts $templateRoot $language "project-agent" "AGENTS.md"
                if (-not (Test-Path -LiteralPath $rootGuidePath) -or -not (Test-Path -LiteralPath $nestedGuidePath)) {
                    $ownershipGuidanceErrors.Add("missing $templateKind/$language ownership guide")
                    continue
                }
                $rootGuideText = [System.IO.File]::ReadAllText($rootGuidePath, [System.Text.Encoding]::UTF8)
                $nestedGuideText = [System.IO.File]::ReadAllText($nestedGuidePath, [System.Text.Encoding]::UTF8)
                foreach ($token in $expectation.root_required) {
                    if (-not $rootGuideText.Contains([string]$token)) {
                        $ownershipGuidanceErrors.Add("$templateKind/$language project-root missing ownership token: $token")
                    }
                }
                foreach ($token in $expectation.nested_required) {
                    if (-not $nestedGuideText.Contains([string]$token)) {
                        $ownershipGuidanceErrors.Add("$templateKind/$language project-agent missing memory-guide token: $token")
                    }
                }
                foreach ($token in $expectation.nested_forbidden) {
                    if ($nestedGuideText.Contains([string]$token)) {
                        $ownershipGuidanceErrors.Add("$templateKind/$language project-agent contains forbidden behavior-contract token: $token")
                    }
                }
            }
        }

        $bootstrapSkillPath = Join-PathParts $RuntimeDir "skills" "project-bootstrap" "SKILL.md"
        if (-not (Test-Path -LiteralPath $bootstrapSkillPath)) {
            $ownershipGuidanceErrors.Add("missing project-bootstrap/SKILL.md")
        }
        else {
            $bootstrapSkillText = [System.IO.File]::ReadAllText($bootstrapSkillPath, [System.Text.Encoding]::UTF8)
            foreach ($token in @("Global Experience Discovery", "project-root/AGENTS.md", 'not `project-agent/AGENTS.md`')) {
                if (-not $bootstrapSkillText.Contains([string]$token)) {
                    $ownershipGuidanceErrors.Add("project-bootstrap/SKILL.md missing global experience installation token: $token")
                }
            }
        }

        $testingGuidanceTokens = @(
            "Testing / Verification Evidence",
            ".agents/commands/test-workflow.md",
            ".agents/context/tech/testing-conventions.md"
        )
        foreach ($language in @("en", "zh-CN")) {
            $authoritySpecPath = Join-PathParts $authorityRoot $language "project-root" "docs" "specs" "_templates" "spec-lite.md"
            $snapshotSpecPath = Join-PathParts $snapshotRoot $language "project-root" "docs" "specs" "_templates" "spec-lite.md"
            foreach ($specPath in @($authoritySpecPath, $snapshotSpecPath)) {
                if (-not (Test-Path -LiteralPath $specPath)) {
                    $testingGuidanceErrors.Add("missing spec-lite template for testing guidance: $specPath")
                    continue
                }
                $specText = Get-Content -LiteralPath $specPath -Raw
                foreach ($token in $testingGuidanceTokens) {
                    if ($specText -notlike ("*{0}*" -f $token)) {
                        $testingGuidanceErrors.Add("$specPath missing testing guidance token: $token")
                    }
                }
            }
        }
        # workflow-spec-lite is retired from C3.3 authority and no longer
        # installed, so the testing-guidance contract is validated only against
        # the spec-lite templates still present in the runtime snapshot.
        $workflowSpecReference = ""
        foreach ($legacyRoot in $legacyRoots) {
            if (Test-Path -LiteralPath $legacyRoot) {
                $missing.Add("legacy template directory should not exist: $legacyRoot")
            }
        }

        if ($missing.Count -gt 0 -or $mismatched.Count -gt 0 -or $testingGuidanceErrors.Count -gt 0 -or $learningDepositGuidanceErrors.Count -gt 0 -or $ownershipGuidanceErrors.Count -gt 0) {
            throw ("Project language file templates are missing, mismatched, missing testing/learning-deposit/ownership guidance, or legacy paths remain. Missing: {0}; mismatched: {1}; testing guidance: {2}; learning-deposit guidance: {3}; ownership guidance: {4}" -f ($missing.ToArray() -join "; "), ($mismatched.ToArray() -join "; "), ($testingGuidanceErrors.ToArray() -join "; "), ($learningDepositGuidanceErrors.ToArray() -join "; "), ($ownershipGuidanceErrors.ToArray() -join "; "))
        }

        return [ordered]@{
            authority_root = $authorityRoot
            bundled_snapshot_root = $snapshotRoot
            legacy_roots_absent = -not [bool](@($legacyRoots | Where-Object { Test-Path -LiteralPath $_ }).Count)
            languages = @("en", "zh-CN")
            checked_files_per_language = @($requiredRelativePaths)
            testing_evidence_guidance = [ordered]@{
                workflow_spec_reference = $workflowSpecReference
                checked_tokens = @($testingGuidanceTokens)
            }
            learning_deposit_guidance = [ordered]@{
                checked_languages = @("en", "zh-CN")
                checked_template_kinds = @("authority", "snapshot")
                delivery_protocol_triggers = @("user correction", "validation failure rework", "scope drift", "skipped acceptance", "tool workaround")
                write_requires_user_confirmation = $true
                auto_promotion_forbidden = $true
            }
            ownership_guidance = [ordered]@{
                root_contract_authoritative = $true
                nested_memory_guide_only = $true
                nested_forbidden_behavior_tokens_checked = $true
                global_experience_discovery_root_only = $true
                bootstrap_skill_aligned = $true
            }
        }
    }

    function Test-ProjectLanguageTemplateFallback {
        param(
            [Parameter(Mandatory = $true)][string]$RuntimeDir
        )

        $sourceTemplateRoot = Join-PathParts $RuntimeDir "skills" "project-bootstrap" "assets" "knowledge-hub-template" "templates" "languages"
        $fallbackTemplateRoot = Join-PathParts $scratchRootFull "language-template-fallback-root"
        Copy-Item -LiteralPath $sourceTemplateRoot -Destination $fallbackTemplateRoot -Recurse -Force

        $removedTemplate = Join-PathParts $fallbackTemplateRoot "zh-CN" "project-agent" "notes.md"
        Remove-Item -LiteralPath $removedTemplate -Force

        $projectDir = Join-PathParts $scratchRootFull "language-template-fallback-project"
        New-Item -ItemType Directory -Force -Path $projectDir | Out-Null
        Assert-PathInsideRoot -Path $projectDir -Root $scratchRootFull

        $languageScript = Join-PathParts $RuntimeDir "skills" "project-bootstrap" "scripts" "set_project_language.ps1"
        $jsonText = & $languageScript -ProjectDir $projectDir -ProjectLanguage "zh-CN" -TemplateRoot $fallbackTemplateRoot
        $result = $jsonText | ConvertFrom-Json

        if ([int]$result.fallback_count -lt 1) {
            throw "Missing zh-CN template did not report a fallback."
        }
        if (".agents/notes.md" -notin @($result.fallback_paths)) {
            throw "Missing zh-CN notes template did not fall back for .agents/notes.md."
        }

        $notesPath = Join-PathParts $projectDir ".agents" "notes.md"
        $notesText = Get-Content -LiteralPath $notesPath -Raw
        if ($notesText -notlike "*Project memory language: English.*") {
            throw "Fallback notes file did not use the English template."
        }

        return [ordered]@{
            template_root = $fallbackTemplateRoot
            project = $projectDir
            removed_template = "zh-CN/project-agent/notes.md"
            fallback_count = [int]$result.fallback_count
            fallback_paths = @($result.fallback_paths)
        }
    }

    function Test-PlainBootstrapDefaultsToEnglish {
        param(
            [Parameter(Mandatory = $true)][string]$RuntimeDir
        )

        $projectDir = Join-PathParts $scratchRootFull "plain-bootstrap-default-language"
        New-Item -ItemType Directory -Force -Path $projectDir | Out-Null
        Assert-PathInsideRoot -Path $projectDir -Root $scratchRootFull

        $hubDir = Join-PathParts $RuntimeDir "knowledge-hub"
        $bootstrapScript = Join-PathParts $RuntimeDir "skills" "project-bootstrap" "scripts" "bootstrap_project.ps1"
        & $bootstrapScript -ProjectDir $projectDir -HubDir $hubDir -SkipMemoryUpgradeAnalysis | Out-Host

        $lock = Get-Content -LiteralPath (Join-PathParts $projectDir ".agents" "hub.lock.json") -Raw | ConvertFrom-Json
        if ([string]$lock.project_language -ne "en") {
            throw "Plain bootstrap lock did not record project_language=en."
        }
        if ([string]$lock.workspace_model -ne "c3.3" -or [string]$lock.workspace_state -ne "active") {
            throw "Plain bootstrap did not produce the active C3.3 workspace contract."
        }
        if (-not (Test-Path -LiteralPath (Join-PathParts $projectDir "AGENTS.md")) -or -not (Test-Path -LiteralPath (Join-PathParts $projectDir ".agents" "README.md"))) {
            throw "Plain bootstrap did not write the C3.3 workspace entrypoint files."
        }

        return [ordered]@{
            project = $projectDir
            project_language = [string]$lock.project_language
            workspace_model = [string]$lock.workspace_model
            workspace_state = [string]$lock.workspace_state
            template_source = [string]$lock.template_source
        }
    }

    if ($languagePolicyPresent -and $c33WorkspaceBootstrapPresent) {
        $fileTemplateEvidence += Test-ProjectMemoryTemplateFiles -RuntimeDir $script:recommendedCopyRuntime
        $autoWriteEvidence += Test-PlainBootstrapDefaultsToEnglish -RuntimeDir $script:recommendedCopyRuntime
        $autoWriteEvidence += Test-ProjectLanguageBootstrap -Language "en" -ExpectedLockLanguage "en"
        $autoWriteEvidence += Test-ProjectLanguageBootstrap -Language "zh-CN" -ExpectedLockLanguage "zh-CN"
        $fallbackEvidence += Test-ProjectLanguageTemplateFallback -RuntimeDir $script:recommendedCopyRuntime
    }

    $script:evidence.language_policy = [ordered]@{
        project_language_policy_present = [bool]$languagePolicyPresent
        c33_workspace_bootstrap_present = [bool]$c33WorkspaceBootstrapPresent
        file_template_sources = @($fileTemplateEvidence)
        auto_language_write_behavior = if ($autoWriteEvidence.Count -gt 0) { "passed" } else { "not_checked" }
        auto_language_write_projects = @($autoWriteEvidence)
        missing_template_fallback = @($fallbackEvidence)
    }
    if ($languagePolicyPresent -and $c33WorkspaceBootstrapPresent) {
        Add-Check "language policy templates" "PASS" "Project Language Policy is present in root guidance; fresh bootstrap produces the active C3.3 workspace with the recorded project language." $evidence.language_policy
        Add-Check "file-based memory template sources" "PASS" "English and Simplified Chinese project memory templates exist as files for root, hot memory, context, commands, testing surfaces, and spec scaffolds." @($fileTemplateEvidence)
        Add-Check "first-session language auto-write behavior" "PASS" "Bootstrap records English and Simplified Chinese project language in the C3.3 workspace lock when the agent/workflow supplies the first-session language." @($autoWriteEvidence)
        Add-Check "missing language template fallback" "PASS" "A missing Simplified Chinese template file falls back to the English template with fallback metadata." @($fallbackEvidence)
    }
    else {
        Add-Check "language policy templates" "FAIL" "Language policy guidance or C3.3 workspace bootstrap generation check failed." $evidence.language_policy
        Add-Check "file-based memory template sources" "FAIL" "Language template validation did not complete the file-based source contract." @($fileTemplateEvidence)
        Add-Check "first-session language auto-write behavior" "FAIL" "Language template validation did not complete the first-session auto-write contract." @($autoWriteEvidence)
        Add-Check "missing language template fallback" "FAIL" "Language template validation did not complete the missing-template fallback contract." @($fallbackEvidence)
    }
}
catch {
    Add-Check "language policy templates" "FAIL" $_.Exception.Message
    Add-Check "file-based memory template sources" "FAIL" "Blocked by the language template validation exception."
    Add-Check "first-session language auto-write behavior" "FAIL" "Blocked by the language template validation exception."
    Add-Check "missing language template fallback" "FAIL" "Blocked by the language template validation exception."
}

}
