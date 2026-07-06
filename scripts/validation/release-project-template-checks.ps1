# Invoke-ReleaseValidationLanguageTemplateChecks: No parameters; runs language policy, template auto-write checks in the original order.
# Bilingual public/private routing check was extracted to release-template-language-checks.ps1 (Phase 3)
# and is now invoked via Invoke-ReleaseTemplateLanguageChecks.
function Invoke-ReleaseValidationLanguageTemplateChecks {

try {
    $repoGuide = Get-FileText -RelativePath "AGENTS.md"
    $languagePolicyPresent = $repoGuide -match '(?m)^## Project Language Policy\s*$'
    $hotMemoryExists = $false
    $bootstrapLanguagePolicyPresent = $false
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
        $hotMemoryExists = @("AGENTS.md", ".agents/AGENTS.md", ".agents/process.txt", ".agents/plan.md") |
            ForEach-Object { Test-Path -LiteralPath (Join-PathParts $projectDir $_) } |
            Where-Object { $_ -eq $true } |
            Measure-Object |
            Select-Object -ExpandProperty Count
        $hotMemoryExists = ($hotMemoryExists -eq 4)

        $bootstrapAgentGuidePath = Join-PathParts $projectDir ".agents" "AGENTS.md"
        if (Test-Path -LiteralPath $bootstrapAgentGuidePath) {
            $bootstrapAgentGuide = Get-Content -LiteralPath $bootstrapAgentGuidePath -Raw
            $bootstrapLanguagePolicyPresent = $bootstrapAgentGuide -match '(?m)^## Project Language Policy\s*$'
        }
    }

    function Test-ProjectLanguageBootstrap {
        param(
            [Parameter(Mandatory = $true)][string]$Language,
            [Parameter(Mandatory = $true)][string]$ExpectedMarker,
            [Parameter(Mandatory = $true)][string]$ExpectedContextToken,
            [Parameter(Mandatory = $true)][string]$ExpectedCommandToken,
            [Parameter(Mandatory = $true)][string]$ExpectedSpecToken
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

        $requiredMarkers = [ordered]@{
            "AGENTS.md" = $ExpectedMarker
            ".agents/AGENTS.md" = $ExpectedMarker
            ".agents/process.txt" = $ExpectedMarker
            ".agents/plan.md" = $ExpectedMarker
            ".agents/notes.md" = $ExpectedMarker
            ".agents/context/README.md" = $ExpectedContextToken
            ".agents/context/tech/README.md" = $ExpectedMarker
            ".agents/context/tech/testing-conventions.md" = "test framework"
            ".agents/context/business/README.md" = $ExpectedMarker
            ".agents/context/experience/README.md" = $ExpectedMarker
            ".agents/context/experience/cases/README.md" = $ExpectedMarker
            ".agents/context/experience/cases/case_template.md" = $ExpectedMarker
            ".agents/commands/README.md" = $ExpectedCommandToken
            ".agents/commands/test-workflow.md" = "test evidence"
            "docs/specs/README.md" = $ExpectedSpecToken
            "docs/specs/_templates/spec-lite.md" = $ExpectedMarker
            "docs/specs/_templates/tasks-lite.md" = $ExpectedMarker
        }

        $missing = New-Object 'System.Collections.Generic.List[string]'
        foreach ($relativePath in $requiredMarkers.Keys) {
            $path = Join-PathParts $languageProjectDir $relativePath
            if (-not (Test-Path -LiteralPath $path)) {
                $missing.Add("$relativePath missing")
                continue
            }
            $text = Get-Content -LiteralPath $path -Raw
            if ($text -notlike ("*{0}*" -f $requiredMarkers[$relativePath])) {
                $missing.Add("$relativePath missing expected language marker")
            }
        }

        if ($missing.Count -gt 0) {
            throw ("Language bootstrap failed for {0}: {1}" -f $Language, ($missing.ToArray() -join "; "))
        }

        return [ordered]@{
            language = $Language
            project = $languageProjectDir
            checked_files = @($requiredMarkers.Keys)
            marker = $ExpectedMarker
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
        $workflowSpecReference = Join-PathParts $RuntimeDir "skills" "workflow-spec-lite" "references" "spec-template.md"
        if (-not (Test-Path -LiteralPath $workflowSpecReference)) {
            $testingGuidanceErrors.Add("missing workflow-spec-lite reference template: $workflowSpecReference")
        }
        else {
            $workflowSpecReferenceText = Get-Content -LiteralPath $workflowSpecReference -Raw
            foreach ($token in $testingGuidanceTokens) {
                if ($workflowSpecReferenceText -notlike ("*{0}*" -f $token)) {
                    $testingGuidanceErrors.Add("$workflowSpecReference missing testing guidance token: $token")
                }
            }
        }
        foreach ($legacyRoot in $legacyRoots) {
            if (Test-Path -LiteralPath $legacyRoot) {
                $missing.Add("legacy template directory should not exist: $legacyRoot")
            }
        }

        if ($missing.Count -gt 0 -or $mismatched.Count -gt 0 -or $testingGuidanceErrors.Count -gt 0) {
            throw ("Project language file templates are missing, mismatched, missing testing guidance, or legacy paths remain. Missing: {0}; mismatched: {1}; testing guidance: {2}" -f ($missing.ToArray() -join "; "), ($mismatched.ToArray() -join "; "), ($testingGuidanceErrors.ToArray() -join "; "))
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

        $rootText = Get-Content -LiteralPath (Join-PathParts $projectDir "AGENTS.md") -Raw
        $agentText = Get-Content -LiteralPath (Join-PathParts $projectDir ".agents" "AGENTS.md") -Raw
        $lock = Get-Content -LiteralPath (Join-PathParts $projectDir ".agents" "hub.lock.json") -Raw | ConvertFrom-Json

        if ($rootText -notlike "*Project memory language: English.*") {
            throw "Plain bootstrap root template did not use English."
        }
        if ($agentText -notlike "*Project memory language: English.*") {
            throw "Plain bootstrap project-agent template did not use English."
        }
        if ([string]$lock.project_language -ne "en") {
            throw "Plain bootstrap lock did not record project_language=en."
        }

        return [ordered]@{
            project = $projectDir
            project_language = [string]$lock.project_language
            template_source = [string]$lock.template_source
        }
    }

    if ($languagePolicyPresent -and $hotMemoryExists -and $bootstrapLanguagePolicyPresent) {
        $fileTemplateEvidence += Test-ProjectMemoryTemplateFiles -RuntimeDir $script:recommendedCopyRuntime
        $autoWriteEvidence += Test-PlainBootstrapDefaultsToEnglish -RuntimeDir $script:recommendedCopyRuntime
        $autoWriteEvidence += Test-ProjectLanguageBootstrap -Language "en" -ExpectedMarker "Project memory language: English." -ExpectedContextToken "Use this folder as the long-term memory base." -ExpectedCommandToken "Use this folder for reusable high-frequency project workflows." -ExpectedSpecToken "Use this directory for long-lived work packages"
        $autoWriteEvidence += Test-ProjectLanguageBootstrap -Language "zh-CN" -ExpectedMarker "项目记忆语言：简体中文。" -ExpectedContextToken "此目录是长期项目记忆入口。" -ExpectedCommandToken "此目录用于沉淀高频、可复用的项目工作流命令。" -ExpectedSpecToken "此目录用于保存需要跨会话延续的长期工作包。"
        $fallbackEvidence += Test-ProjectLanguageTemplateFallback -RuntimeDir $script:recommendedCopyRuntime
    }

    $script:evidence.language_policy = [ordered]@{
        project_language_policy_present = [bool]$languagePolicyPresent
        bootstrap_hot_memory_present = [bool]$hotMemoryExists
        bootstrap_project_language_policy_present = [bool]$bootstrapLanguagePolicyPresent
        file_template_sources = @($fileTemplateEvidence)
        auto_language_write_behavior = if ($autoWriteEvidence.Count -gt 0) { "passed" } else { "not_checked" }
        auto_language_write_projects = @($autoWriteEvidence)
        missing_template_fallback = @($fallbackEvidence)
    }
    if ($languagePolicyPresent -and $hotMemoryExists -and $bootstrapLanguagePolicyPresent) {
        Add-Check "language policy templates" "PASS" "Project Language Policy is present in root guidance and bootstrap output; bootstrap hot memory files are generated in temporary projects." $evidence.language_policy
        Add-Check "file-based memory template sources" "PASS" "English and Simplified Chinese project memory templates exist as files for root, hot memory, context, commands, testing surfaces, and spec scaffolds." @($fileTemplateEvidence)
        Add-Check "first-session language auto-write behavior" "PASS" "Bootstrap can write English and Simplified Chinese project memory scaffolds when the agent/workflow supplies the first-session language." @($autoWriteEvidence)
        Add-Check "missing language template fallback" "PASS" "A missing Simplified Chinese template file falls back to the English template with fallback metadata." @($fallbackEvidence)
    }
    else {
        Add-Check "language policy templates" "FAIL" "Language policy guidance or bootstrap hot memory generation check failed." $evidence.language_policy
    }
}
catch {
    Add-Check "language policy templates" "FAIL" $_.Exception.Message
}

}
