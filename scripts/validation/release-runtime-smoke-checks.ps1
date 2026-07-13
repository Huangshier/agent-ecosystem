function Invoke-InstallerProfile {
    param(
        [Parameter(Mandatory = $true)][string]$Profile,
        [Parameter(Mandatory = $true)][string]$Mode
    )

    $targetDir = Join-PathParts $scratchRootFull ("runtime-{0}-{1}" -f $Profile, $Mode)
    Assert-NotLiveRuntime -Path $targetDir
    Assert-PathInsideRoot -Path $targetDir -Root $scratchRootFull

    $installer = Join-PathParts $repoRoot "scripts" "install.ps1"
    $installParams = @{
        Profile = $Profile
        TargetDir = $targetDir
    }
    if ($Mode -eq "dev-link") {
        $installParams.DevLink = $true
    }

    & $installer @installParams | Out-Host

    $manifestPath = Join-PathParts $targetDir "install-manifest.json"
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw "Install manifest missing: $manifestPath"
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    return [ordered]@{
        profile = $Profile
        mode = $Mode
        target_dir = $targetDir
        manifest_path = $manifestPath
        manifest = $manifest
    }
}

function Test-Manifest {
    param(
        [Parameter(Mandatory = $true)][object]$InstallResult,
        [Parameter(Mandatory = $true)][object[]]$ExpectedSkills
    )

    $manifest = $InstallResult.manifest
    $targetDir = $InstallResult.target_dir
    $mode = $InstallResult.mode
    $errors = New-Object 'System.Collections.Generic.List[string]'

    if ([string]$manifest.profile -ne [string]$InstallResult.profile) {
        $errors.Add("profile field mismatch")
    }
    if (-not (Test-ExactArray -Actual @($manifest.skills) -Expected $ExpectedSkills)) {
        $errors.Add("skills field mismatch")
    }
    if ([int]$manifest.schema_version -ne 2) {
        $errors.Add("manifest schema_version should be 2")
    }
    if ([string]$manifest.target_dir -ne ".") {
        $errors.Add("manifest target_dir should be runtime-relative")
    }
    if ($mode -eq "copy" -and [string]$manifest.install_strategy -ne "copy") {
        $errors.Add("copy mode did not record copy strategy")
    }
    if ($mode -eq "dev-link" -and [string]$manifest.install_strategy -ne "dev-link") {
        $errors.Add("dev-link mode did not record dev-link strategy")
    }

    $items = @($manifest.items)
    if ($items.Count -ne (1 + $ExpectedSkills.Count)) {
        $errors.Add(("item count mismatch: expected {0}, got {1}" -f (1 + $ExpectedSkills.Count), $items.Count))
    }

    foreach ($item in $items) {
        foreach ($field in @("name", "source", "destination", "mode", "source_hash", "installed_hash")) {
            if ([string]::IsNullOrWhiteSpace([string]$item.$field)) {
                $errors.Add("manifest item missing field: $field")
            }
        }
        if ([System.IO.Path]::IsPathRooted([string]$item.source) -or [System.IO.Path]::IsPathRooted([string]$item.destination)) {
            $errors.Add("manifest item paths should be relative")
        }
        if ($mode -eq "copy" -and [string]$item.mode -ne "copy") {
            $errors.Add(("copy install item used mode {0}" -f $item.mode))
        }
        if ($mode -eq "dev-link" -and [string]$item.mode -notin @("junction", "symboliclink")) {
            $errors.Add(("dev-link install item used unexpected mode {0}" -f $item.mode))
        }
        foreach ($file in @($item.files)) {
            if ([string]::IsNullOrWhiteSpace([string]$file.path) -or [string]::IsNullOrWhiteSpace([string]$file.installed_sha256)) {
                $errors.Add("manifest managed file record is incomplete")
            }
        }
    }

    return @($errors.ToArray())
}

# Invoke-ReleaseValidationInstallerRuntimeChecks: No parameters; runs installer matrix, runtime smoke, and temporary project support checks in the original order.
function Invoke-ReleaseValidationInstallerRuntimeChecks {

$script:profileExpectations = [ordered]@{
    minimal = @("project-bootstrap")
    recommended = @("project-bootstrap", "project-context-gate", "workflow-spec-lite", "memory-governance")
    full = @("project-bootstrap", "project-context-gate", "workflow-spec-lite", "memory-governance")
    dev = @("project-bootstrap", "project-context-gate", "workflow-spec-lite", "memory-governance")
}

$script:installModes = @("copy")
if (-not $SkipLinkMode.IsPresent) {
    $script:installModes += "dev-link"
}

$installFailures = New-Object 'System.Collections.Generic.List[string]'
$script:recommendedCopyRuntime = $null
$script:recommendedLinkRuntime = $null
foreach ($profile in $script:profileExpectations.Keys) {
    foreach ($mode in $script:installModes) {
        try {
            $result = Invoke-InstallerProfile -Profile $profile -Mode $mode
            $errors = @(Test-Manifest -InstallResult $result -ExpectedSkills $script:profileExpectations[$profile])
            $manifest = $result.manifest
            $itemModes = @($manifest.items | ForEach-Object { [string]$_.mode })
            $script:evidence.profile_matrix += [ordered]@{
                profile = $profile
                mode = $mode
                target_dir = $result.target_dir
                manifest_path = $result.manifest_path
                skills = @($manifest.skills)
                item_modes = @($itemModes)
            }
            if ($errors.Count -gt 0) {
                $installFailures.Add(("{0}/{1}: {2}" -f $profile, $mode, ($errors -join "; ")))
            }
            if ($profile -eq "recommended" -and $mode -eq "copy") {
                $script:recommendedCopyRuntime = $result.target_dir
            }
            if ($profile -eq "recommended" -and $mode -eq "dev-link") {
                $script:recommendedLinkRuntime = $result.target_dir
            }
        }
        catch {
            $installFailures.Add(("{0}/{1}: {2}" -f $profile, $mode, $_.Exception.Message))
        }
    }
}

try {
    $script:evidence.installer_contract = Invoke-InstallerContractFixtureChecks `
        -RepositoryRoot $repoRoot `
        -ScratchRoot $scratchRootFull `
        -SkipDevLink:$SkipLinkMode.IsPresent
    Add-Check "installer contract fixtures" "PASS" "Copy-first, incremental rerun, conflict, replacement, report, legacy manifest, and explicit development-link scenarios passed." $evidence.installer_contract
}
catch {
    Add-Check "installer contract fixtures" "FAIL" $_.Exception.Message
}
try {
    $script:evidence.runtime_status = Invoke-RuntimeStatusFixtureChecks `
        -RepositoryRoot $repoRoot `
        -ScratchRoot $scratchRootFull
    Add-Check "runtime status fixtures" "PASS" "Read-only runtime manifest status payload fixtures passed." $evidence.runtime_status
}
catch {
    Add-Check "runtime status fixtures" "FAIL" $_.Exception.Message
}
try {
    $script:evidence.agent_skill_bridge = Invoke-AgentSkillBridgeFixtureChecks `
        -RepositoryRoot $repoRoot `
        -ScratchRoot $scratchRootFull
    Add-Check "agent skill bridge fixtures" "PASS" "Explicit opt-in, exact canonical ownership, physical ancestor alias resolution, platform path semantics, runtime/source containment, full preflight, idempotence, transaction rollback, local bridge metadata, and conflict isolation scenarios passed." $evidence.agent_skill_bridge
}
catch {
    Add-Check "agent skill bridge fixtures" "FAIL" $_.Exception.Message
}
if ($installFailures.Count -eq 0) {
    Add-Check "installer profile matrix" "PASS" "All requested profiles and install modes produced valid manifests." $evidence.profile_matrix
}
else {
    Add-Check "installer profile matrix" "FAIL" "Profile or install mode validation failed." @($installFailures.ToArray())
}

function Invoke-RuntimeSmoke {
    param(
        [Parameter(Mandatory = $true)][string]$RuntimeDir,
        [Parameter(Mandatory = $true)][string]$Name,
        [switch]$CheckHubLock
    )

    $projectDir = Join-PathParts $scratchRootFull ("runtime-smoke-project-{0}" -f $Name)
    New-Item -ItemType Directory -Force -Path $projectDir | Out-Null
    Assert-PathInsideRoot -Path $projectDir -Root $scratchRootFull

    $hubDir = Join-PathParts $RuntimeDir "knowledge-hub"
    $bootstrapScript = Join-PathParts $RuntimeDir "skills" "project-bootstrap" "scripts" "bootstrap_project.ps1"
    & $bootstrapScript -ProjectDir $projectDir -HubDir $hubDir -SkipMemoryUpgradeAnalysis | Out-Host

    $contextGateScript = Join-PathParts $RuntimeDir "skills" "project-context-gate" "scripts" "context_gate.ps1"
    $contextJsonText = & $contextGateScript -ProjectRoot $projectDir -Json
    $contextJson = $contextJsonText | ConvertFrom-Json
    $hotPaths = @($contextJson.hot_files | ForEach-Object { [string]$_.path })
    $expectedHotNames = @("AGENTS.md", ".agents/AGENTS.md", ".agents/process.txt", ".agents/plan.md")
    foreach ($expectedName in $expectedHotNames) {
        $expectedPath = (Resolve-Path -LiteralPath (Join-PathParts $projectDir $expectedName)).Path
        if ($expectedPath -notin $hotPaths) {
            throw "Context gate hot files did not include $expectedName"
        }
    }

    # Verify CLAUDE.md shim was generated
    $claudeMdPath = Join-PathParts $projectDir "CLAUDE.md"
    if (-not (Test-Path -LiteralPath $claudeMdPath)) {
        throw "Bootstrap did not generate CLAUDE.md shim at project root."
    }
    $claudeMdText = Get-Content -LiteralPath $claudeMdPath -Raw
    $expectedClaudeImports = @("@AGENTS.md", "@.agents/AGENTS.md", "@.agents/process.txt", "@.agents/plan.md", "@.agents/context/README.md", "@.agents/commands/README.md")
    foreach ($import in $expectedClaudeImports) {
        if ($claudeMdText -notlike "*$import*") {
            throw "CLAUDE.md shim is missing expected import: $import"
        }
    }

    $contextBriefText = (& $contextGateScript -ProjectRoot $projectDir -Brief) -join [Environment]::NewLine
    $expectedBriefMarkers = @(
        "Project Context Gate Brief",
        "Gate: start",
        "Project root:",
        "Git:",
        "Hot files (load now):",
        "Active work package files:",
        "Cold discovery-only files:",
        "Warnings / boundary notes:",
        "Next action:"
    )
    foreach ($marker in $expectedBriefMarkers) {
        if ($contextBriefText -notmatch [regex]::Escape($marker)) {
            throw "Context gate brief output did not include marker: $marker"
        }
    }

    $specDir = Join-PathParts $projectDir "docs" "specs" ("validation-smoke-{0}" -f $Name)
    New-Item -ItemType Directory -Force -Path $specDir | Out-Null
    $specSource = Join-PathParts $RuntimeDir "skills" "workflow-spec-lite" "references" "spec-template.md"
    $tasksSource = Join-PathParts $RuntimeDir "skills" "workflow-spec-lite" "references" "tasks-template.md"
    $specTarget = Join-PathParts $specDir "spec.md"
    $tasksTarget = Join-PathParts $specDir "tasks.md"
    $specText = Get-Content -LiteralPath $specSource -Raw
    $tasksText = Get-Content -LiteralPath $tasksSource -Raw
    $specText = $specText -replace '- \*\*Title\*\*:', ("- **Title**: Validation smoke {0}" -f $Name)
    $specText = $specText -replace '- \*\*Slug\*\*:', ("- **Slug**: validation-smoke-{0}" -f $Name)
    $specText = $specText -replace '- \*\*Status\*\*: Draft / Active / Done / Archived', '- **Status**: Active'
    $specText = $specText -replace '- \*\*Owner\*\*:', '- **Owner**: release validation'
    $specText = $specText -replace '- \*\*Updated\*\*:', ("- **Updated**: {0}" -f (Get-Date).ToString("yyyy-MM-dd"))
    $tasksText = $tasksText -replace '- \*\*Spec\*\*:', ("- **Spec**: docs/specs/validation-smoke-{0}/spec.md" -f $Name)
    $tasksText = $tasksText -replace '- \*\*Status\*\*: Draft / Active / Done', '- **Status**: Active'
    $tasksText = $tasksText -replace '- \*\*Updated\*\*:', ("- **Updated**: {0}" -f (Get-Date).ToString("yyyy-MM-dd"))
    Set-Content -LiteralPath $specTarget -Value $specText -Encoding UTF8
    Set-Content -LiteralPath $tasksTarget -Value $tasksText -Encoding UTF8

    if (-not (Test-Path -LiteralPath $specTarget) -or -not (Test-Path -LiteralPath $tasksTarget)) {
        throw "workflow-spec-lite smoke spec/tasks were not created."
    }

    $memoryDiagnoseScript = Join-PathParts $RuntimeDir "skills" "memory-governance" "scripts" "memory_diagnose.ps1"
    $memoryJsonText = & $memoryDiagnoseScript -ProjectRoot $projectDir -Json
    $memoryJson = $memoryJsonText | ConvertFrom-Json
    $findingCount = [int]$memoryJson.summary.finding_count
    if ($findingCount -ne 0) {
        throw "memory-governance diagnose returned $findingCount findings."
    }

    $hubLockStatus = "not_checked"
    if ($CheckHubLock.IsPresent) {
        $checkHubLockScript = Join-PathParts $RuntimeDir "skills" "project-bootstrap" "scripts" "check_hub_lock.ps1"
        $hubLockOutput = @(& $checkHubLockScript -ProjectDir $projectDir -HubDir $hubDir)
        $hubLockStatusLine = @($hubLockOutput | Where-Object { $_ -match '^Status:\s+' } | Select-Object -Last 1)
        if ($hubLockStatusLine.Count -lt 1 -or $hubLockStatusLine[0] -notmatch 'Status:\s+in_sync') {
            throw ("hub.lock drift check did not report in_sync. Output: {0}" -f ($hubLockOutput -join " | "))
        }
        $hubLockStatus = "in_sync"
    }

    return [ordered]@{
        name = $Name
        runtime = $RuntimeDir
        project = $projectDir
        bootstrap = "passed"
        context_gate_hot_file_count = @($contextJson.hot_files).Count
        context_gate_brief = "passed"
        spec = $specTarget
        tasks = $tasksTarget
        memory_diagnose_findings = $findingCount
        hub_lock_status = $hubLockStatus
    }
}

try {
    if ([string]::IsNullOrWhiteSpace($script:recommendedCopyRuntime)) {
        throw "Recommended copy runtime was not created."
    }

    $runtimeSmokeResults = New-Object 'System.Collections.Generic.List[object]'
    $runtimeSmokeResults.Add((Invoke-RuntimeSmoke -RuntimeDir $script:recommendedCopyRuntime -Name "copy"))

    if (-not $SkipLinkMode.IsPresent) {
        if ([string]::IsNullOrWhiteSpace($script:recommendedLinkRuntime)) {
            throw "Recommended link runtime was not created."
        }
        $runtimeSmokeResults.Add((Invoke-RuntimeSmoke -RuntimeDir $script:recommendedLinkRuntime -Name "dev-link"))
    }

    $script:evidence.runtime_smoke = @($runtimeSmokeResults.ToArray())
    Add-Check "runtime smoke" "PASS" "Bootstrap, context gate, workflow-spec-lite, and memory-governance smoke checks passed for recommended runtime installs." $evidence.runtime_smoke
}
catch {
    Add-Check "runtime smoke" "FAIL" $_.Exception.Message
}

try {
    $contextGateSuite = Join-PathParts $repoRoot "scripts" "validation" "project-context-gate-checks.ps1"
    $contextGateJson = @(
        & $contextGateSuite `
            -RepositoryRoot $repoRoot `
            -ScratchRoot (Join-PathParts $scratchRootFull "project-context-gate-targeted") `
            -Json
    ) -join [Environment]::NewLine
    $contextGateEvidence = $contextGateJson | ConvertFrom-Json
    if ([string]$contextGateEvidence.status -ne "PASS" -or
        [int]$contextGateEvidence.scenario_count -lt 2 -or
        -not [bool]$contextGateEvidence.project_read_only) {
        throw "Project context gate targeted suite returned incomplete evidence."
    }
    $script:evidence.project_context_gate = $contextGateEvidence
    Add-Check "project context gate targeted suite" "PASS" "Source and copy-install layouts preserve text, JSON, brief, inventory, git-state, and read-only behavior." $contextGateEvidence
}
catch {
    Add-Check "project context gate targeted suite" "FAIL" $_.Exception.Message
}

try {
    if ([string]::IsNullOrWhiteSpace($script:recommendedCopyRuntime)) {
        throw "Recommended copy runtime was not created."
    }

    # Test 1: Existing CLAUDE.md is preserved during re-bootstrap
    $preserveProject = Join-PathParts $scratchRootFull "claude-md-preserve-test"
    New-Item -ItemType Directory -Force -Path $preserveProject | Out-Null
    Assert-PathInsideRoot -Path $preserveProject -Root $scratchRootFull

    $hubDir = Join-PathParts $script:recommendedCopyRuntime "knowledge-hub"
    $bootstrapScript = Join-PathParts $script:recommendedCopyRuntime "skills" "project-bootstrap" "scripts" "bootstrap_project.ps1"

    # Initial bootstrap to create scaffold
    & $bootstrapScript -ProjectDir $preserveProject -HubDir $hubDir -SkipMemoryUpgradeAnalysis | Out-Null

    # Overwrite CLAUDE.md with custom content
    $customClaudeContent = "# Custom CLAUDE.md`n`n@AGENTS.md`n"
    Set-Content -LiteralPath (Join-Path $preserveProject "CLAUDE.md") -Value $customClaudeContent -Encoding UTF8
    $customHash = (Get-FileHash -LiteralPath (Join-Path $preserveProject "CLAUDE.md") -Algorithm SHA256).Hash

    # Re-bootstrap (default mode should not overwrite existing files)
    & $bootstrapScript -ProjectDir $preserveProject -HubDir $hubDir -SkipMemoryUpgradeAnalysis | Out-Null

    $postHash = (Get-FileHash -LiteralPath (Join-Path $preserveProject "CLAUDE.md") -Algorithm SHA256).Hash
    if ($customHash -ne $postHash) {
        throw "Bootstrap overwrote existing CLAUDE.md in default refresh mode."
    }

    # Test 2: Memory upgrade analyze reports missing CLAUDE.md as advisory
    $noShimProject = Join-PathParts $scratchRootFull "claude-md-advisory-test"
    New-Item -ItemType Directory -Force -Path $noShimProject | Out-Null
    Assert-PathInsideRoot -Path $noShimProject -Root $scratchRootFull

    # Bootstrap, then remove CLAUDE.md to simulate pre-shim project
    & $bootstrapScript -ProjectDir $noShimProject -HubDir $hubDir -SkipMemoryUpgradeAnalysis | Out-Null
    Remove-Item -LiteralPath (Join-Path $noShimProject "CLAUDE.md") -Force

    $memoryUpgradeScript = Join-PathParts $script:recommendedCopyRuntime "skills" "project-bootstrap" "scripts" "memory_upgrade.ps1"
    $analyzeJsonText = & $memoryUpgradeScript -ProjectDir $noShimProject -Mode Analyze -Json
    $analyzeJson = $analyzeJsonText | ConvertFrom-Json
    $hasShimAdvisory = @($analyzeJson.findings | Where-Object { $_.code -eq "missing_claude_shim" }).Count -gt 0
    if (-not $hasShimAdvisory) {
        throw "Memory upgrade analyze did not report missing_claude_shim advisory for project without CLAUDE.md."
    }

    # Test 3: Memory upgrade analyze reports incomplete CLAUDE.md as advisory
    $incompleteProject = Join-PathParts $scratchRootFull "claude-md-incomplete-test"
    New-Item -ItemType Directory -Force -Path $incompleteProject | Out-Null
    Assert-PathInsideRoot -Path $incompleteProject -Root $scratchRootFull

    & $bootstrapScript -ProjectDir $incompleteProject -HubDir $hubDir -SkipMemoryUpgradeAnalysis | Out-Null
    Set-Content -LiteralPath (Join-Path $incompleteProject "CLAUDE.md") -Value "# CLAUDE.md`n`n@AGENTS.md`n" -Encoding UTF8

    $incompleteJsonText = & $memoryUpgradeScript -ProjectDir $incompleteProject -Mode Analyze -Json
    $incompleteJson = $incompleteJsonText | ConvertFrom-Json
    $hasIncompleteAdvisory = @($incompleteJson.findings | Where-Object { $_.code -eq "incomplete_claude_shim" }).Count -gt 0
    if (-not $hasIncompleteAdvisory) {
        throw "Memory upgrade analyze did not report incomplete_claude_shim advisory for project with partial CLAUDE.md imports."
    }

    Add-Check "CLAUDE.md shim adoption" "PASS" "Bootstrap preserves existing CLAUDE.md; memory upgrade analyze reports missing_claude_shim and incomplete_claude_shim advisories." ([ordered]@{
        preserve_hash_match = ($customHash -eq $postHash)
        missing_advisory_detected = $hasShimAdvisory
        incomplete_advisory_detected = $hasIncompleteAdvisory
    })
}
catch {
    Add-Check "CLAUDE.md shim adoption" "FAIL" $_.Exception.Message
}

try {
    if ([string]::IsNullOrWhiteSpace($script:recommendedCopyRuntime)) {
        throw "Recommended copy runtime was not created."
    }

    $localizedProject = Join-PathParts $scratchRootFull "localized-context-discovery"
    New-Item -ItemType Directory -Force -Path $localizedProject | Out-Null
    Assert-PathInsideRoot -Path $localizedProject -Root $scratchRootFull

    $hubDir = Join-PathParts $script:recommendedCopyRuntime "knowledge-hub"
    $bootstrapScript = Join-PathParts $script:recommendedCopyRuntime "skills" "project-bootstrap" "scripts" "bootstrap_project.ps1"
    & $bootstrapScript -ProjectDir $localizedProject -HubDir $hubDir -ProjectLanguage "zh-CN" -SkipMemoryUpgradeAnalysis | Out-Host

    $summaryHeading = -join @([char]0x6458, [char]0x8981)
    $keywordsHeading = -join @([char]0x5173, [char]0x952E, [char]0x8BCD)
    $localizedContextPath = Join-PathParts $localizedProject ".agents" "context" "experience" "localized-discovery.md"
    $localizedContextText = @(
        "# Localized Discovery Fixture",
        "",
        "## $summaryHeading",
        "Temporary context entry used by release validation.",
        "",
        "## $keywordsHeading",
        "localized discovery metadata, memory diagnosis, memory upgrade",
        "",
        "## Notes",
        "Both memory diagnostics should recognize the localized discovery headings."
    )
    Set-Content -LiteralPath $localizedContextPath -Value $localizedContextText -Encoding UTF8

    $memoryDiagnoseScript = Join-PathParts $script:recommendedCopyRuntime "skills" "memory-governance" "scripts" "memory_diagnose.ps1"
    $diagnose = & $memoryDiagnoseScript -ProjectRoot $localizedProject -Json | ConvertFrom-Json
    $diagnoseMetadataFindings = @($diagnose.findings | Where-Object { [string]$_.code -eq "context_missing_discovery_metadata" })

    $memoryUpgradeScript = Join-PathParts $script:recommendedCopyRuntime "skills" "project-bootstrap" "scripts" "memory_upgrade.ps1"
    $upgrade = & $memoryUpgradeScript -ProjectDir $localizedProject -Mode Analyze -Json | ConvertFrom-Json
    $upgradeMetadataFindings = @($upgrade.findings | Where-Object { [string]$_.code -eq "context_metadata_missing" })

    $script:evidence.memory_metadata = [ordered]@{
        project = $localizedProject
        context_file = $localizedContextPath
        memory_diagnose_findings = @($diagnose.findings).Count
        memory_upgrade_findings = @($upgrade.findings).Count
        diagnose_metadata_findings = $diagnoseMetadataFindings.Count
        upgrade_metadata_findings = $upgradeMetadataFindings.Count
    }

    if ($diagnoseMetadataFindings.Count -gt 0 -or $upgradeMetadataFindings.Count -gt 0) {
        Add-Check "localized context discovery metadata" "FAIL" "Localized discovery headings were reported as missing metadata." $evidence.memory_metadata
    }
    else {
        Add-Check "localized context discovery metadata" "PASS" "Memory diagnosis and upgrade analysis accept localized Summary/Keywords discovery headings." $evidence.memory_metadata
    }
}
catch {
    Add-Check "localized context discovery metadata" "FAIL" $_.Exception.Message
}

try {
    if ([string]::IsNullOrWhiteSpace($script:recommendedCopyRuntime)) {
        throw "Recommended copy runtime was not created."
    }

    $auditScript = Join-PathParts $script:recommendedCopyRuntime "skills" "project-bootstrap" "scripts" "audit_memory_language.ps1"
    if (-not (Test-Path -LiteralPath $auditScript)) {
        throw "audit_memory_language.ps1 was not installed into the recommended runtime."
    }

    $auditProject = Join-PathParts $scratchRootFull "body-level-memory-language-audit"
    New-Item -ItemType Directory -Force -Path $auditProject | Out-Null
    Assert-PathInsideRoot -Path $auditProject -Root $scratchRootFull

    $contextDir = Join-PathParts $auditProject ".agents" "context" "experience"
    $commandsDir = Join-PathParts $auditProject ".agents" "commands"
    $specDir = Join-PathParts $auditProject "docs" "specs" "body-mixed"
    New-Item -ItemType Directory -Force -Path $contextDir | Out-Null
    New-Item -ItemType Directory -Force -Path $commandsDir | Out-Null
    New-Item -ItemType Directory -Force -Path $specDir | Out-Null

    $zhSummary = [regex]::Unescape('\u8fd9\u662f\u4e2d\u6587\u6458\u8981\u3002')
    $zhKeywords = [regex]::Unescape('\u8bed\u8a00, \u5ba1\u8ba1')
    $zhBody = [regex]::Unescape('\u8fd9\u4e2a\u9879\u76ee\u7684\u6b63\u6587\u5df2\u7ecf\u662f\u4e2d\u6587\u3002\u540e\u7eed\u5ba1\u8ba1\u5e94\u8be5\u6309\u7167\u6b63\u6587\u8bed\u8a00\u5224\u65ad\uff0c\u800c\u4e0d\u662f\u6309\u7167\u5143\u6570\u636e\u5224\u65ad\u3002')
    $zhCode = [regex]::Unescape('\u4ee3\u7801\u5757')
    $zhSpecPrefix = [regex]::Unescape('\u8fd9\u4e2a\u89c4\u683c\u4fdd\u7559\u4e2d\u6587\u53d9\u8ff0\uff0c\u540c\u65f6')
    $zhMixedSuffix = [regex]::Unescape('\u5e94\u8be5\u4f5c\u4e3a\u6df7\u5408\u8bed\u8a00\u8bc1\u636e\u88ab\u62a5\u544a\u3002')
    $zhCommandHeading = [regex]::Unescape('\u8fd0\u884c\u547d\u4ee4')
    $zhProtectedBody = [regex]::Unescape('\u8fd9\u91cc\u4ec5\u5305\u542b\u547d\u4ee4\u3001\u8def\u5f84\u3001API\u3001\u6587\u4ef6\u540d\u548c\u539f\u59cb\u9519\u8bef\u6587\u672c\uff0c\u4e0d\u5e94\u89e6\u53d1\u6b63\u6587\u8bed\u8a00\u53d1\u73b0\u3002')

    $metadataZhBodyEnPath = Join-PathParts $contextDir "metadata-zh-body-en.md"
    Set-Content -LiteralPath $metadataZhBodyEnPath -Value @(
        "## Summary",
        $zhSummary,
        "",
        "## Keywords",
        $zhKeywords,
        "",
        "## Notes",
        "The rollout remains paused until review. The project should preserve this operational lesson for future migrations."
    ) -Encoding UTF8

    $metadataEnBodyZhPath = Join-PathParts $contextDir "metadata-en-body-zh.md"
    Set-Content -LiteralPath $metadataEnBodyZhPath -Value @(
        "## Summary",
        "English metadata summary.",
        "",
        "## Keywords",
        "language, audit",
        "",
        "## Notes",
        $zhBody
    ) -Encoding UTF8

    $fencedCodePath = Join-PathParts $contextDir "fenced-code-only.md"
    Set-Content -LiteralPath $fencedCodePath -Value @(
        "## Summary",
        $zhSummary,
        "",
        "## Keywords",
        $zhCode,
        "",
        '```text',
        "This English text is inside a fenced code block and should not count.",
        "The command git status and path src/app.py should stay ignored here.",
        '```'
    ) -Encoding UTF8

    $protectedLiteralsPath = Join-PathParts $commandsDir "protected-literals.md"
    Set-Content -LiteralPath $protectedLiteralsPath -Value @(
        "# $zhCommandHeading",
        "",
        $zhProtectedBody,
        "",
        "powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-release.ps1 -ScratchRoot C:\Temp\audit",
        "Keep `Get-FooBar`, `src/app.py`, `AGENTS.md`, `feat`, `ERROR_PATH_NOT_FOUND`, and `CustomThing` unchanged."
    ) -Encoding UTF8

    $mixedSpecPath = Join-PathParts $specDir "spec.md"
    Set-Content -LiteralPath $mixedSpecPath -Value @(
        "# Body Mixed Spec",
        "",
        ("{0} this English narrative remains in the body and should be flagged as mixed language evidence. {1}" -f $zhSpecPrefix, $zhMixedSuffix)
    ) -Encoding UTF8

    function Get-AuditFixtureHashes {
        param([string]$Root)

        $hashes = @{}
        foreach ($file in @(Get-ChildItem -LiteralPath $Root -Recurse -File)) {
            $relative = ConvertTo-DisplayPath -Path $file.FullName -Root $Root
            $hashes[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        }
        return $hashes
    }

    $hashesBefore = Get-AuditFixtureHashes -Root $auditProject
    $audit = & $auditScript -ProjectDir $auditProject -ExpectedLanguage "zh-CN" -IncludeSpecs -IncludeCommands -Json | ConvertFrom-Json
    $humanOutput = @(& $auditScript -ProjectDir $auditProject -ExpectedLanguage "zh-CN" -IncludeSpecs -IncludeCommands)
    $hashesAfter = Get-AuditFixtureHashes -Root $auditProject

    $changedFiles = New-Object 'System.Collections.Generic.List[string]'
    foreach ($key in @($hashesBefore.Keys)) {
        if (-not $hashesAfter.ContainsKey($key) -or $hashesBefore[$key] -ne $hashesAfter[$key]) {
            $changedFiles.Add($key)
        }
    }
    foreach ($key in @($hashesAfter.Keys)) {
        if (-not $hashesBefore.ContainsKey($key)) {
            $changedFiles.Add($key)
        }
    }
    if ($changedFiles.Count -gt 0) {
        throw ("Body-level audit helper changed project files: {0}" -f ($changedFiles.ToArray() -join "; "))
    }

    $findingPaths = @($audit.findings | ForEach-Object { [string]$_.path })
    $expectedFindingPaths = @(
        ".agents/context/experience/metadata-zh-body-en.md",
        "docs/specs/body-mixed/spec.md"
    )
    foreach ($expectedPath in $expectedFindingPaths) {
        if ($expectedPath -notin $findingPaths) {
            throw "Body-level audit helper missed expected finding: $expectedPath"
        }
    }
    foreach ($unexpectedPath in @(
        ".agents/context/experience/metadata-en-body-zh.md",
        ".agents/context/experience/fenced-code-only.md",
        ".agents/commands/protected-literals.md"
    )) {
        if ($unexpectedPath -in $findingPaths) {
            throw "Body-level audit helper reported an ignored fixture: $unexpectedPath"
        }
    }

    $metadataOnly = @($audit.findings | Where-Object { [string]$_.path -eq ".agents/context/experience/metadata-zh-body-en.md" -and [string]$_.code -eq "metadata_only_localization" })
    $mixedBody = @($audit.findings | Where-Object { [string]$_.path -eq "docs/specs/body-mixed/spec.md" -and [string]$_.code -eq "mixed_language_body" })
    if ($metadataOnly.Count -ne 1 -or $mixedBody.Count -ne 1) {
        throw "Body-level audit helper reported unexpected finding codes."
    }
    if ([int]$audit.summary.finding_count -ne 2) {
        throw ("Body-level audit helper returned unexpected finding count: {0}" -f $audit.summary.finding_count)
    }
    if (@($humanOutput | Where-Object { $_ -like "WARN .agents/context/experience/metadata-zh-body-en.md:*" }).Count -ne 1) {
        throw "Body-level audit helper human output did not include the metadata/body warning."
    }

    $script:evidence.memory_language_audit = [ordered]@{
        project = $auditProject
        scanned_files = [int]$audit.scanned_files
        findings = @($audit.findings | ForEach-Object { [ordered]@{ path = [string]$_.path; code = [string]$_.code; reason = [string]$_.reason } })
        non_findings = @(
            ".agents/context/experience/metadata-en-body-zh.md",
            ".agents/context/experience/fenced-code-only.md",
            ".agents/commands/protected-literals.md"
        )
        read_only_hash_check = "passed"
    }

    Add-Check "body-level memory language audit" "PASS" "Read-only audit helper detects metadata-only localization and mixed narrative body language while ignoring metadata, fenced code, commands, paths, APIs, filenames, raw errors, and code identifiers." $evidence.memory_language_audit
}
catch {
    Add-Check "body-level memory language audit" "FAIL" $_.Exception.Message
}

try {
    $benchmarkScript = Join-PathParts $repoRoot "scripts" "benchmark-context-gate.ps1"
    $benchmarkScratch = Join-PathParts $scratchRootFull "context-gate-benchmark"
    Assert-PathInsideRoot -Path $benchmarkScratch -Root $scratchRootFull
    $benchmarkJsonText = & $benchmarkScript -ScratchRoot $benchmarkScratch -ContextFileCount 500 -MaxSeconds 30 -Json
    $benchmark = $benchmarkJsonText | ConvertFrom-Json
    if (-not [bool]$benchmark.passed) {
        throw ("Benchmark did not pass. Elapsed={0}s, threshold={1}s, included={2}" -f $benchmark.elapsed_seconds, $benchmark.max_seconds, $benchmark.included_context_files)
    }
    Add-Check "context gate large context benchmark" "PASS" ("Context gate JSON handled {0} context files in {1}s." -f $benchmark.included_context_files, $benchmark.elapsed_seconds) $benchmark
}
catch {
    Add-Check "context gate large context benchmark" "FAIL" $_.Exception.Message
}

try {
    $pruneScript = Join-PathParts $repoRoot "scripts" "prune-validation-scratch.ps1"
    $pruneFixture = Join-PathParts $scratchRootFull "validation-scratch-retention"
    New-Item -ItemType Directory -Force -Path $pruneFixture | Out-Null
    Assert-PathInsideRoot -Path $pruneFixture -Root $scratchRootFull

    foreach ($index in 1..4) {
        $runDir = Join-PathParts $pruneFixture ("run-{0}" -f $index)
        New-Item -ItemType Directory -Force -Path $runDir | Out-Null
        Assert-PathInsideRoot -Path $runDir -Root $pruneFixture
        [ordered]@{
            run = $index
            status = "fixture"
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-PathParts $runDir "validation-result.json") -Encoding UTF8
        (Get-Item -LiteralPath $runDir).LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddMinutes($index)
    }

    $dryRunJson = & $pruneScript -ScratchRoot $pruneFixture -RetainLatest 2 -Json
    $dryRun = $dryRunJson | ConvertFrom-Json
    if ([bool]$dryRun.apply) {
        throw "Dry run reported apply=true."
    }
    if ([int]$dryRun.summary.candidate_count -ne 4 -or
        [int]$dryRun.summary.retained_count -ne 2 -or
        [int]$dryRun.summary.prunable_count -ne 2) {
        throw "Dry run retention counts were incorrect."
    }
    foreach ($index in 1..4) {
        if (-not (Test-Path -LiteralPath (Join-PathParts $pruneFixture ("run-{0}" -f $index)))) {
            throw "Dry run removed run-$index."
        }
    }

    $applyJson = & $pruneScript -ScratchRoot $pruneFixture -RetainLatest 2 -Apply -Json
    $apply = $applyJson | ConvertFrom-Json
    if (-not [bool]$apply.apply) {
        throw "Apply run reported apply=false."
    }
    foreach ($index in 1..2) {
        if (Test-Path -LiteralPath (Join-PathParts $pruneFixture ("run-{0}" -f $index))) {
            throw "Apply run did not prune run-$index."
        }
    }
    foreach ($index in 3..4) {
        if (-not (Test-Path -LiteralPath (Join-PathParts $pruneFixture ("run-{0}" -f $index)))) {
            throw "Apply run pruned retained run-$index."
        }
    }

    $script:evidence.scratch_retention = [ordered]@{
        fixture_root = $pruneFixture
        dry_run = $dryRun
        apply = $apply
    }
    Add-Check "validation scratch retention pruning" "PASS" "Scratch pruning helper is dry-run by default and prunes only older evidence-marked run directories when -Apply is supplied." $evidence.scratch_retention
}
catch {
    Add-Check "validation scratch retention pruning" "FAIL" $_.Exception.Message
}

}
