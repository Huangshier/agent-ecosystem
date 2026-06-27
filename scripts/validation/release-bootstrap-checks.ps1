# Invoke-ReleaseValidationRuntimeAndKnowledgeHubChecks: No parameters; runs runtime behavior, upgrade/migration flow checks in the original order.
# Knowledge hub checks (catalog, experience search, promote closure, duplicate helper hash) were extracted to
# release-knowledge-hub-checks.ps1 (Phase 3) and are now invoked via Invoke-ReleaseKnowledgeHubChecks.
function Invoke-ReleaseValidationRuntimeAndKnowledgeHubChecks {

try {
    $hubFixture = Join-PathParts $scratchRootFull "hub-lock-fixture-hub"
    $projectFixture = Join-PathParts $scratchRootFull "hub-lock-fixture-project"
    $batchProjectFixture = Join-PathParts $scratchRootFull "hub-lock-fixture-project-batch"
    $missingLockProject = Join-PathParts $scratchRootFull "hub-lock-missing-project"
    $invalidHubDir = Join-PathParts $scratchRootFull "hub-lock-missing-hub"
    Assert-PathInsideRoot -Path $hubFixture -Root $scratchRootFull
    Assert-PathInsideRoot -Path $projectFixture -Root $scratchRootFull
    Assert-PathInsideRoot -Path $batchProjectFixture -Root $scratchRootFull
    Assert-PathInsideRoot -Path $missingLockProject -Root $scratchRootFull
    Assert-PathInsideRoot -Path $invalidHubDir -Root $scratchRootFull
    foreach ($fixturePath in @($hubFixture, $projectFixture, $batchProjectFixture, $missingLockProject, $invalidHubDir)) {
        if (Test-Path -LiteralPath $fixturePath) {
            Remove-Item -LiteralPath $fixturePath -Recurse -Force
        }
    }
    Copy-Item -LiteralPath (Join-PathParts $repoRoot "knowledge-hub") -Destination $hubFixture -Recurse -Force
    New-Item -ItemType Directory -Force -Path $projectFixture | Out-Null
    New-Item -ItemType Directory -Force -Path $batchProjectFixture | Out-Null
    New-Item -ItemType Directory -Force -Path $missingLockProject | Out-Null

    & git -C $hubFixture init | Out-Null
    & git -C $hubFixture config user.email "release-validation@example.invalid" | Out-Null
    & git -C $hubFixture config user.name "Release Validation" | Out-Null
    & git -C $hubFixture config core.autocrlf false | Out-Null
    & git -C $hubFixture config core.safecrlf false | Out-Null
    & git -C $hubFixture add . | Out-Null
    & git -C $hubFixture commit -m "Initialize validation hub fixture" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to commit hub lock fixture."
    }

    $bootstrapScript = Join-PathParts $script:recommendedCopyRuntime "skills" "project-bootstrap" "scripts" "bootstrap_project.ps1"
    & $bootstrapScript -ProjectDir $projectFixture -HubDir $hubFixture -SkipMemoryUpgradeAnalysis | Out-Host
    & $bootstrapScript -ProjectDir $batchProjectFixture -HubDir $hubFixture -SkipMemoryUpgradeAnalysis | Out-Host
    $checkHubLockScript = Join-PathParts $script:recommendedCopyRuntime "skills" "project-bootstrap" "scripts" "check_hub_lock.ps1"
    $hubLockOutput = @(& $checkHubLockScript -ProjectDir $projectFixture -HubDir $hubFixture)
    $hubLockStatusLine = @($hubLockOutput | Where-Object { $_ -match '^Status:\s+' } | Select-Object -Last 1)
    if ($hubLockStatusLine.Count -lt 1 -or $hubLockStatusLine[0] -notmatch 'Status:\s+in_sync') {
        throw ("hub.lock drift check did not report in_sync. Output: {0}" -f ($hubLockOutput -join " | "))
    }

    $batchHubLockOutput = @(& $checkHubLockScript -ProjectDir $projectFixture,$batchProjectFixture -HubDir $hubFixture)
    $batchInSyncCount = @($batchHubLockOutput | Where-Object { $_ -match '^Status:\s+in_sync' }).Count
    if ($batchInSyncCount -ne 2) {
        throw ("hub.lock batch check did not report two in_sync projects. Output: {0}" -f ($batchHubLockOutput -join " | "))
    }

    function Assert-HubLockNegativeCase {
        param(
            [Parameter(Mandatory = $true)][string]$Name,
            [Parameter(Mandatory = $true)][string[]]$Arguments,
            [Parameter(Mandatory = $true)][string]$ExpectedStatus
        )

        $result = Invoke-IsolatedPowerShellScript -ScriptPath $checkHubLockScript -Arguments $Arguments
        $statusMatched = @($result.output | Where-Object { $_ -match ("^Status:\s+{0}$" -f [regex]::Escape($ExpectedStatus)) }).Count -gt 0
        if ($result.exit_code -eq 0 -or -not $statusMatched) {
            throw ("hub.lock negative case {0} failed. Exit={1}; expected status={2}; output={3}" -f $Name, $result.exit_code, $ExpectedStatus, ($result.output -join " | "))
        }
        return [ordered]@{
            name = $Name
            expected_status = $ExpectedStatus
            exit_code = $result.exit_code
        }
    }

    $negativeEvidence = New-Object 'System.Collections.Generic.List[object]'
    $negativeEvidence.Add((Assert-HubLockNegativeCase -Name "missing-lock" -Arguments @("-ProjectDir", $missingLockProject, "-HubDir", $hubFixture) -ExpectedStatus "missing_lock"))
    $negativeEvidence.Add((Assert-HubLockNegativeCase -Name "invalid-hub-dir" -Arguments @("-ProjectDir", $projectFixture, "-HubDir", $invalidHubDir) -ExpectedStatus "invalid_hub_dir"))

    Add-Content -LiteralPath (Join-PathParts $hubFixture "templates" "languages" "en" "project-root" "AGENTS.md") -Value "`nrelease validation drift marker"
    $negativeEvidence.Add((Assert-HubLockNegativeCase -Name "dirty-hub-drift" -Arguments @("-ProjectDir", $projectFixture, "-HubDir", $hubFixture) -ExpectedStatus "drift"))

    Add-Check "hub.lock drift check" "PASS" "Git-backed temporary hub lock check reported in_sync." ([ordered]@{
        temp_hub = $hubFixture
        temp_project = $projectFixture
        batch_project = $batchProjectFixture
        status = "in_sync"
        batch_status_count = $batchInSyncCount
        negative_cases = @($negativeEvidence.ToArray())
    })
}
catch {
    Add-Check "hub.lock drift check" "FAIL" $_.Exception.Message
}

try {
    $installer = Join-PathParts $repoRoot "scripts" "install.ps1"
    $targetDir = Join-PathParts $scratchRootFull "install-behavior-runtime"
    Assert-PathInsideRoot -Path $targetDir -Root $scratchRootFull

    & $installer -Profile minimal -TargetDir $targetDir -Copy -Force | Out-Host
    $firstManifestPath = Join-PathParts $targetDir "install-manifest.json"
    if (-not (Test-Path -LiteralPath $firstManifestPath)) {
        throw "Initial install manifest missing."
    }

    $conflictFailedAsExpected = $false
    try {
        & $installer -Profile minimal -TargetDir $targetDir -Copy | Out-Null
    }
    catch {
        if ($_.Exception.Message -match 'Destination already exists') {
            $conflictFailedAsExpected = $true
        }
        else {
            throw
        }
    }
    if (-not $conflictFailedAsExpected) {
        throw "Installer allowed overwriting an existing target without -Force."
    }

    & $installer -Profile recommended -TargetDir $targetDir -Copy -Force | Out-Host
    $secondManifest = Get-Content -LiteralPath $firstManifestPath -Raw | ConvertFrom-Json
    if ([string]$secondManifest.profile -ne "recommended") {
        throw "Forced reinstall did not update manifest profile to recommended."
    }
    if (-not (Test-ExactArray -Actual @($secondManifest.skills) -Expected $script:profileExpectations.recommended)) {
        throw "Forced reinstall manifest did not include recommended skills."
    }

    Add-Check "installer behavior" "PASS" "No-Force conflict and forced reinstall behavior are validated." ([ordered]@{
        target_dir = $targetDir
        no_force_conflict = "failed_as_expected"
        force_reinstall_profile = [string]$secondManifest.profile
        force_reinstall_skills = @($secondManifest.skills)
    })
}
catch {
    Add-Check "installer behavior" "FAIL" $_.Exception.Message
}

try {
    $installer = Join-PathParts $repoRoot "scripts" "install.ps1"
    $uninstaller = Join-PathParts $repoRoot "scripts" "uninstall.ps1"
    $targetDir = Join-PathParts $scratchRootFull "uninstall-behavior-runtime"
    Assert-PathInsideRoot -Path $targetDir -Root $scratchRootFull

    & $installer -Profile recommended -TargetDir $targetDir -Copy -Force | Out-Host
    $manifestPath = Join-PathParts $targetDir "install-manifest.json"
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw "Install manifest missing before uninstall validation."
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $manifestDestinations = @($manifest.items | ForEach-Object { [string]$_.destination })

    $extraFile = Join-PathParts $targetDir "user-extra.txt"
    $extraNested = Join-PathParts $targetDir "skills" "user-skill" "README.md"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $extraNested) | Out-Null
    Set-Content -LiteralPath $extraFile -Value "preserve me" -Encoding UTF8
    Set-Content -LiteralPath $extraNested -Value "preserve nested user content" -Encoding UTF8

    $uninstallJsonText = & $uninstaller -TargetDir $targetDir -Json
    $uninstallResult = $uninstallJsonText | ConvertFrom-Json
    if ([string]$uninstallResult.status -ne "uninstalled") {
        throw "Uninstaller did not report uninstalled status."
    }
    foreach ($destination in $manifestDestinations) {
        if (Test-Path -LiteralPath $destination) {
            throw "Manifest destination still exists after uninstall: $destination"
        }
    }
    if (Test-Path -LiteralPath $manifestPath) {
        throw "Install manifest still exists after uninstall."
    }
    if (-not (Test-Path -LiteralPath $extraFile) -or -not (Test-Path -LiteralPath $extraNested)) {
        throw "Unknown runtime files were not preserved by uninstall."
    }

    $missingManifestDir = Join-PathParts $scratchRootFull "uninstall-missing-manifest-runtime"
    New-Item -ItemType Directory -Force -Path $missingManifestDir | Out-Null
    Set-Content -LiteralPath (Join-PathParts $missingManifestDir "user-extra.txt") -Value "preserve me" -Encoding UTF8
    $missingManifestJsonText = & $uninstaller -TargetDir $missingManifestDir -Json
    $missingManifestResult = $missingManifestJsonText | ConvertFrom-Json
    if ([string]$missingManifestResult.status -ne "missing_manifest") {
        throw "Missing-manifest uninstall did not report missing_manifest status."
    }
    if (-not (Test-Path -LiteralPath (Join-PathParts $missingManifestDir "user-extra.txt"))) {
        throw "Missing-manifest uninstall removed unknown content."
    }

    Add-Check "uninstall behavior" "PASS" "Manifest-based uninstall removes installed items while preserving unknown runtime files." ([ordered]@{
        target_dir = $targetDir
        removed = @($uninstallResult.removed)
        missing_manifest_status = [string]$missingManifestResult.status
        preserved_unknown = [bool]$uninstallResult.preserved_unknown
    })
}
catch {
    Add-Check "uninstall behavior" "FAIL" $_.Exception.Message
}

try {
    if ([string]::IsNullOrWhiteSpace($script:recommendedCopyRuntime)) {
        throw "Recommended copy runtime was not created."
    }

    $memoryUpgradeProject = Join-PathParts $scratchRootFull "memory-upgrade-flow-project"
    New-Item -ItemType Directory -Force -Path $memoryUpgradeProject | Out-Null
    Assert-PathInsideRoot -Path $memoryUpgradeProject -Root $scratchRootFull

    $hubDir = Join-PathParts $script:recommendedCopyRuntime "knowledge-hub"
    $bootstrapScript = Join-PathParts $script:recommendedCopyRuntime "skills" "project-bootstrap" "scripts" "bootstrap_project.ps1"
    & $bootstrapScript -ProjectDir $memoryUpgradeProject -HubDir $hubDir -SkipMemoryUpgradeAnalysis | Out-Host

    $processPath = Join-PathParts $memoryUpgradeProject ".agents" "process.txt"
    $planPath = Join-PathParts $memoryUpgradeProject ".agents" "plan.md"
    $notesPath = Join-PathParts $memoryUpgradeProject ".agents" "notes.md"
    $exampleSpecRef = "docs/specs/example-work/spec.md"
    Add-Content -LiteralPath $processPath -Value "`nPrevious session timeline entry used by validation."
    Add-Content -LiteralPath $processPath -Value "`nActive spec: $exampleSpecRef"
    Add-Content -LiteralPath $planPath -Value "`n- [ ] T99: Durable task that should be normalized."
    Add-Content -LiteralPath $planPath -Value "`nSpec: $exampleSpecRef"
    Add-Content -LiteralPath $notesPath -Value "`nTODO: temporary session state used by validation."

    $memoryUpgradeScript = Join-PathParts $script:recommendedCopyRuntime "skills" "project-bootstrap" "scripts" "memory_upgrade.ps1"
    $analyze = & $memoryUpgradeScript -ProjectDir $memoryUpgradeProject -Mode Analyze -Json | ConvertFrom-Json
    if (@($analyze.findings).Count -lt 1) {
        throw "Memory upgrade Analyze did not report validation findings."
    }

    $plan = & $memoryUpgradeScript -ProjectDir $memoryUpgradeProject -Mode Plan -Json | ConvertFrom-Json
    $proposalPath = [string]$plan.proposal
    if ([string]::IsNullOrWhiteSpace($proposalPath) -or -not (Test-Path -LiteralPath $proposalPath)) {
        throw "Memory upgrade Plan did not create a proposal."
    }

    $apply = & $memoryUpgradeScript -ProjectDir $memoryUpgradeProject -Mode Apply -UpgradePlan $proposalPath -Json | ConvertFrom-Json
    $backupDir = [string]$apply.apply_result.backup_dir
    $resultPath = [string]$apply.apply_result.result
    if ([string]::IsNullOrWhiteSpace($backupDir) -or -not (Test-Path -LiteralPath $backupDir)) {
        throw "Memory upgrade Apply did not create a backup."
    }
    if ([string]::IsNullOrWhiteSpace($resultPath) -or -not (Test-Path -LiteralPath $resultPath)) {
        throw "Memory upgrade Apply did not create a result file."
    }
    if ((Get-Content -LiteralPath $processPath -Raw) -notmatch "Memory upgraded") {
        throw "Memory upgrade Apply did not normalize process.txt."
    }
    if ((Get-Content -LiteralPath $processPath -Raw) -notlike ("*{0}*" -f $exampleSpecRef)) {
        throw "Memory upgrade Apply did not preserve the active spec reference."
    }

    $zhMemoryUpgradeProject = Join-PathParts $scratchRootFull "memory-upgrade-zh-cn-project"
    New-Item -ItemType Directory -Force -Path $zhMemoryUpgradeProject | Out-Null
    Assert-PathInsideRoot -Path $zhMemoryUpgradeProject -Root $scratchRootFull
    & $bootstrapScript -ProjectDir $zhMemoryUpgradeProject -HubDir $hubDir -ProjectLanguage "zh-CN" -SkipMemoryUpgradeAnalysis | Out-Host

    $zhProcessPath = Join-PathParts $zhMemoryUpgradeProject ".agents" "process.txt"
    $zhPlanPath = Join-PathParts $zhMemoryUpgradeProject ".agents" "plan.md"
    $zhNotesPath = Join-PathParts $zhMemoryUpgradeProject ".agents" "notes.md"
    $zhSpecRef = "docs/specs/zh-memory-work/spec.md"
    Add-Content -LiteralPath $zhProcessPath -Value "`n历史时间线条目用于验证。"
    Add-Content -LiteralPath $zhProcessPath -Value "`n当前 Spec: $zhSpecRef"
    Add-Content -LiteralPath $zhPlanPath -Value "`n- [ ] T99: 应被规范化的长期任务。"
    Add-Content -LiteralPath $zhPlanPath -Value "`nSpec: $zhSpecRef"
    Add-Content -LiteralPath $zhNotesPath -Value "`nTODO: 用于验证的临时会话状态。"

    $zhPlan = & $memoryUpgradeScript -ProjectDir $zhMemoryUpgradeProject -Mode Plan -Json | ConvertFrom-Json
    $zhProposalPath = [string]$zhPlan.proposal
    if ([string]::IsNullOrWhiteSpace($zhProposalPath) -or -not (Test-Path -LiteralPath $zhProposalPath)) {
        throw "zh-CN memory upgrade Plan did not create a proposal."
    }

    $zhApply = & $memoryUpgradeScript -ProjectDir $zhMemoryUpgradeProject -Mode Apply -UpgradePlan $zhProposalPath -Json | ConvertFrom-Json
    if ([string]$zhApply.apply_result.project_language -ne "zh-CN") {
        throw "zh-CN memory upgrade Apply did not report zh-CN project language."
    }
    if ((Get-Content -LiteralPath $zhProcessPath -Raw) -notlike "*当前状态*") {
        throw "zh-CN memory upgrade Apply did not normalize process.txt with Chinese headings."
    }
    if ((Get-Content -LiteralPath $zhPlanPath -Raw) -notlike "*# 当前计划*") {
        throw "zh-CN memory upgrade Apply did not normalize plan.md with Chinese headings."
    }
    if ((Get-Content -LiteralPath $zhNotesPath -Raw) -notlike "*# 已确认记录*") {
        throw "zh-CN memory upgrade Apply did not normalize notes.md with Chinese headings."
    }
    if ((Get-Content -LiteralPath $zhProcessPath -Raw) -notlike ("*{0}*" -f $zhSpecRef)) {
        throw "zh-CN memory upgrade Apply did not preserve the active spec reference."
    }

    $fallbackProject = Join-PathParts $scratchRootFull "memory-upgrade-unsupported-language-project"
    New-Item -ItemType Directory -Force -Path $fallbackProject | Out-Null
    Assert-PathInsideRoot -Path $fallbackProject -Root $scratchRootFull
    & $bootstrapScript -ProjectDir $fallbackProject -HubDir $hubDir -SkipMemoryUpgradeAnalysis | Out-Host

    $fallbackLockPath = Join-PathParts $fallbackProject ".agents" "hub.lock.json"
    $fallbackLock = Get-Content -LiteralPath $fallbackLockPath -Raw | ConvertFrom-Json
    $fallbackLock.project_language = "fr-FR"
    $fallbackLock | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $fallbackLockPath -Encoding UTF8
    $fallbackProcessPath = Join-PathParts $fallbackProject ".agents" "process.txt"
    Add-Content -LiteralPath $fallbackProcessPath -Value "`nPrevious session timeline entry for unsupported language validation."

    $fallbackPlan = & $memoryUpgradeScript -ProjectDir $fallbackProject -Mode Plan -Json | ConvertFrom-Json
    $fallbackProposalPath = [string]$fallbackPlan.proposal
    if ([string]::IsNullOrWhiteSpace($fallbackProposalPath) -or -not (Test-Path -LiteralPath $fallbackProposalPath)) {
        throw "Unsupported-language memory upgrade Plan did not create a proposal."
    }
    $fallbackApply = & $memoryUpgradeScript -ProjectDir $fallbackProject -Mode Apply -UpgradePlan $fallbackProposalPath -Json | ConvertFrom-Json
    if ([string]$fallbackApply.apply_result.project_language -ne "en") {
        throw "Unsupported-language memory upgrade Apply did not fall back to English."
    }
    if ([string]$fallbackApply.apply_result.language_warning -notlike "*Unsupported project_language*") {
        throw "Unsupported-language memory upgrade Apply did not report an explicit fallback warning."
    }
    if ((Get-Content -LiteralPath $fallbackProcessPath -Raw) -notlike "*Current State*") {
        throw "Unsupported-language memory upgrade Apply did not write English fallback headings."
    }

    $autoUpgradeProject = Join-PathParts $scratchRootFull "memory-auto-upgrade-project"
    New-Item -ItemType Directory -Force -Path $autoUpgradeProject | Out-Null
    Assert-PathInsideRoot -Path $autoUpgradeProject -Root $scratchRootFull
    & $bootstrapScript -ProjectDir $autoUpgradeProject -HubDir $hubDir -SkipMemoryUpgradeAnalysis | Out-Host

    $autoProcessPath = Join-PathParts $autoUpgradeProject ".agents" "process.txt"
    $autoPlanPath = Join-PathParts $autoUpgradeProject ".agents" "plan.md"
    $autoNotesPath = Join-PathParts $autoUpgradeProject ".agents" "notes.md"
    Add-Content -LiteralPath $autoProcessPath -Value "`nPrevious session timeline entry used by auto-upgrade validation."
    Add-Content -LiteralPath $autoPlanPath -Value "`n- [ ] T99: Durable task that auto-upgrade should normalize."
    Add-Content -LiteralPath $autoNotesPath -Value "`nTODO: temporary session state used by auto-upgrade validation."

    $autoOutput = @(& $bootstrapScript -ProjectDir $autoUpgradeProject -HubDir $hubDir -AutoUpgrade)
    $autoProposal = @(Get-ChildItem -LiteralPath (Join-PathParts $autoUpgradeProject ".agents" "upgrade") -Recurse -File -Filter "proposal.md" | Select-Object -First 1)
    $autoResult = @(Get-ChildItem -LiteralPath (Join-PathParts $autoUpgradeProject ".agents" "upgrade") -Recurse -File -Filter "result.md" | Select-Object -First 1)
    $autoBackup = @(Get-ChildItem -LiteralPath (Join-PathParts $autoUpgradeProject ".agents" "_backup") -Directory | Select-Object -First 1)
    if ($autoProposal.Count -lt 1) {
        throw "Bootstrap -AutoUpgrade did not create a proposal."
    }
    if ($autoResult.Count -lt 1) {
        throw "Bootstrap -AutoUpgrade did not create a result file."
    }
    if ($autoBackup.Count -lt 1) {
        throw "Bootstrap -AutoUpgrade did not create a backup."
    }
    if ((Get-Content -LiteralPath $autoProcessPath -Raw) -notmatch "Memory upgraded") {
        throw "Bootstrap -AutoUpgrade did not normalize process.txt."
    }
    if (@($autoOutput | Where-Object { $_ -match '^Memory upgrade auto: candidates detected:' }).Count -lt 1) {
        throw "Bootstrap -AutoUpgrade did not report detected candidates."
    }

    Add-Check "memory upgrade flow" "PASS" "Memory upgrade manual, language-aware, fallback, and bootstrap -AutoUpgrade flows passed against temporary projects." ([ordered]@{
        project = $memoryUpgradeProject
        findings = @($analyze.findings).Count
        proposal = $proposalPath
        backup = $backupDir
        result = $resultPath
        zh_cn_project = $zhMemoryUpgradeProject
        zh_cn_language = [string]$zhApply.apply_result.project_language
        fallback_project = $fallbackProject
        fallback_warning = [string]$fallbackApply.apply_result.language_warning
        auto_project = $autoUpgradeProject
        auto_proposal = $autoProposal[0].FullName
        auto_backup = $autoBackup[0].FullName
        auto_result = $autoResult[0].FullName
    })
}
catch {
    Add-Check "memory upgrade flow" "FAIL" $_.Exception.Message
}

try {
    if ([string]::IsNullOrWhiteSpace($script:recommendedCopyRuntime)) {
        throw "Recommended copy runtime was not created."
    }

    $fixtureRoot = Join-PathParts $repoRoot "scripts" "validation" "memory-upgrade-stable-notes-fixtures"
    $fixtureReadme = Get-FileText -RelativePath "scripts/validation/memory-upgrade-stable-notes-fixtures/README.md"
    foreach ($token in @("positive-stable-section", "negative-volatile-only", "stable-section preservation")) {
        if (-not $fixtureReadme.Contains($token)) {
            throw "Memory upgrade stable notes fixture README is missing token: $token"
        }
    }

    $hubDir = Join-PathParts $script:recommendedCopyRuntime "knowledge-hub"
    $bootstrapScript = Join-PathParts $script:recommendedCopyRuntime "skills" "project-bootstrap" "scripts" "bootstrap_project.ps1"
    $memoryUpgradeScript = Join-PathParts $script:recommendedCopyRuntime "skills" "project-bootstrap" "scripts" "memory_upgrade.ps1"
    $fixtureCases = @(
        [ordered]@{ name = "positive-stable-section"; role = "positive" },
        [ordered]@{ name = "negative-volatile-only"; role = "negative" }
    )
    $fixtureEvidence = New-Object 'System.Collections.Generic.List[object]'

    foreach ($fixtureCase in $fixtureCases) {
        $fixtureName = [string]$fixtureCase.name
        $fixtureRole = [string]$fixtureCase.role
        $fixtureDir = Join-PathParts $fixtureRoot $fixtureName
        $fixtureNotesPath = Join-PathParts $fixtureDir "notes.md"
        $expectedPath = Join-PathParts $fixtureDir "expected.json"
        $expected = Get-Content -LiteralPath $expectedPath -Raw | ConvertFrom-Json
        if ([string]$expected.fixture -ne $fixtureName) {
            throw "Stable notes fixture expected.json name mismatch for $fixtureName."
        }
        if ([string]$expected.role -ne $fixtureRole) {
            throw "Stable notes fixture role mismatch for $fixtureName."
        }

        $expectedTokens = @()
        if ($null -ne $expected.expected_preserved_tokens) {
            $expectedTokens = @($expected.expected_preserved_tokens | ForEach-Object { [string]$_ })
        }
        $forbiddenTokens = @()
        if ($null -ne $expected.forbidden_after_apply) {
            $forbiddenTokens = @($expected.forbidden_after_apply | ForEach-Object { [string]$_ })
        }

        $projectDir = Join-PathParts $scratchRootFull ("memory-upgrade-stable-notes-{0}" -f $fixtureName)
        New-Item -ItemType Directory -Force -Path $projectDir | Out-Null
        Assert-PathInsideRoot -Path $projectDir -Root $scratchRootFull
        & $bootstrapScript -ProjectDir $projectDir -HubDir $hubDir -SkipMemoryUpgradeAnalysis | Out-Host

        $notesPath = Join-PathParts $projectDir ".agents" "notes.md"
        Copy-Item -LiteralPath $fixtureNotesPath -Destination $notesPath -Force

        $analyzeBefore = & $memoryUpgradeScript -ProjectDir $projectDir -Mode Analyze -Json | ConvertFrom-Json
        $codesBefore = @($analyzeBefore.findings | ForEach-Object { [string]$_.code })
        if ("notes_contains_session_state" -notin $codesBefore) {
            throw "Stable notes fixture $fixtureName did not trigger notes_contains_session_state before Apply."
        }

        $plan = & $memoryUpgradeScript -ProjectDir $projectDir -Mode Plan -Json | ConvertFrom-Json
        $proposalPath = [string]$plan.proposal
        if ([string]::IsNullOrWhiteSpace($proposalPath) -or -not (Test-Path -LiteralPath $proposalPath)) {
            throw "Stable notes fixture $fixtureName did not create a proposal."
        }

        $apply = & $memoryUpgradeScript -ProjectDir $projectDir -Mode Apply -UpgradePlan $proposalPath -Json | ConvertFrom-Json
        $preservedCount = [int]$apply.apply_result.stable_notes_preserved_count
        if ($preservedCount -ne [int]$expected.expected_preserved_count) {
            throw "Stable notes fixture $fixtureName preserved $preservedCount facts; expected $($expected.expected_preserved_count)."
        }

        $backupDir = [string]$apply.apply_result.backup_dir
        $backupNotesPath = Join-PathParts $backupDir "notes.md"
        if ([string]::IsNullOrWhiteSpace($backupDir) -or -not (Test-Path -LiteralPath $backupNotesPath)) {
            throw "Stable notes fixture $fixtureName did not create a notes.md backup."
        }
        $backupNotes = Get-Content -LiteralPath $backupNotesPath -Raw
        if ($backupNotes -notlike "*TODO*" -and $backupNotes -notlike "*I tried*") {
            throw "Stable notes fixture $fixtureName backup did not preserve original volatile notes."
        }

        $notesText = Get-Content -LiteralPath $notesPath -Raw
        if ($fixtureRole -eq "negative" -and $notesText -like "*## Stable Facts*") {
            throw "Negative stable notes fixture unexpectedly wrote a Stable Facts section."
        }
        foreach ($token in $expectedTokens) {
            if ($notesText.IndexOf($token, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
                throw "Stable notes fixture $fixtureName missing preserved token: $token"
            }
        }
        foreach ($token in $forbiddenTokens) {
            if ($notesText.IndexOf($token, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                throw "Stable notes fixture $fixtureName retained volatile token after Apply: $token"
            }
        }
        $analyzeAfter = & $memoryUpgradeScript -ProjectDir $projectDir -Mode Analyze -Json | ConvertFrom-Json
        $codesAfter = @($analyzeAfter.findings | ForEach-Object { [string]$_.code })
        if ("notes_contains_session_state" -in $codesAfter) {
            throw "Stable notes fixture $fixtureName still reports notes_contains_session_state after Apply."
        }

        $fixtureEvidence.Add([ordered]@{
            fixture = $fixtureName
            role = $fixtureRole
            preserved_count = $preservedCount
            preserved_tokens = @($expectedTokens)
            before_codes = @($codesBefore)
            after_codes = @($codesAfter)
            backup_created = (Test-Path -LiteralPath $backupNotesPath)
        })
    }

    Add-Check "memory upgrade stable notes preservation" "PASS" "Memory upgrade Apply preserves compact stable-section facts, removes volatile notes, and keeps backup-first behavior for positive and negative fixtures." ([ordered]@{
        fixtures = @($fixtureEvidence.ToArray())
    })
}
catch {
    Add-Check "memory upgrade stable notes preservation" "FAIL" $_.Exception.Message
}

try {
    if ([string]::IsNullOrWhiteSpace($script:recommendedCopyRuntime)) {
        throw "Recommended copy runtime was not created."
    }

    $hubDir = Join-PathParts $script:recommendedCopyRuntime "knowledge-hub"
    $bootstrapScript = Join-PathParts $script:recommendedCopyRuntime "skills" "project-bootstrap" "scripts" "bootstrap_project.ps1"
    $languageMigrationScript = Join-PathParts $script:recommendedCopyRuntime "skills" "project-bootstrap" "scripts" "language_migration.ps1"
    if (-not (Test-Path -LiteralPath $languageMigrationScript)) {
        throw "language_migration.ps1 was not installed into the recommended runtime."
    }

    function Assert-ApplyFails {
        param(
            [Parameter(Mandatory = $true)][scriptblock]$Command,
            [Parameter(Mandatory = $true)][string]$ExpectedToken
        )

        $failed = $false
        try {
            & $Command | Out-Null
        }
        catch {
            $failed = $true
            if ($_.Exception.Message -notlike ("*{0}*" -f $ExpectedToken)) {
                throw ("Expected failure containing '{0}', got: {1}" -f $ExpectedToken, $_.Exception.Message)
            }
        }

        if (-not $failed) {
            throw ("Expected language migration apply to fail: {0}" -f $ExpectedToken)
        }
    }

    function Invoke-LanguageMigrationFixture {
        param(
            [Parameter(Mandatory = $true)][string]$Name,
            [Parameter(Mandatory = $true)][string]$SourceLanguage,
            [Parameter(Mandatory = $true)][string]$TargetLanguage,
            [Parameter(Mandatory = $true)][string]$ExpectedTargetMarker,
            [switch]$ExerciseMissingBackupFailure
        )

        $projectDir = Join-PathParts $scratchRootFull $Name
        New-Item -ItemType Directory -Force -Path $projectDir | Out-Null
        Assert-PathInsideRoot -Path $projectDir -Root $scratchRootFull
        & $bootstrapScript -ProjectDir $projectDir -HubDir $hubDir -ProjectLanguage $SourceLanguage -SkipMemoryUpgradeAnalysis | Out-Host

        $agentGuidePath = Join-PathParts $projectDir ".agents" "AGENTS.md"
        $planPath = Join-PathParts $projectDir ".agents" "plan.md"
        $processPath = Join-PathParts $projectDir ".agents" "process.txt"
        $notesPath = Join-PathParts $projectDir ".agents" "notes.md"
        $contextPath = Join-PathParts $projectDir ".agents" "context" "experience" "migration-mixed.md"
        $specDir = Join-PathParts $projectDir "docs" "specs" "migration-custom-work"
        $specPath = Join-PathParts $specDir "spec.md"
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $contextPath) | Out-Null
        New-Item -ItemType Directory -Force -Path $specDir | Out-Null

        $tokenLine = "Keep command git status, path src/app.py, API Get-FooBar, filename AGENTS.md, commit type feat, raw error ERROR_PATH_NOT_FOUND, and code symbol CustomThing unchanged."
        Add-Content -LiteralPath $agentGuidePath -Value ("`n## Custom API Notes`n- {0}" -f $tokenLine)
        Add-Content -LiteralPath $planPath -Value ("`n## Active Plan`n- The active rollout is paused until review.`n- Hot memory source token: {0}" -f $tokenLine)
        Add-Content -LiteralPath $processPath -Value ("`n## Process State`n- Record the validated deployment fact.`n- Hot memory process token: {0}" -f $tokenLine)
        Add-Content -LiteralPath $notesPath -Value ("`n## Stable Facts`n- Project uses feature flags.`n- Hot memory notes token: {0}" -f $tokenLine)
        Set-Content -LiteralPath $contextPath -Value @(
            "## Summary",
            "- Mixed language validation entry.",
            "",
            "## Keywords",
            "- language migration, mixed memory",
            "",
            "- Keep this lesson for future migrations.",
            "- 中文 mixed memory marker with ERROR_PATH_NOT_FOUND and src/app.py.",
            "- $tokenLine"
        ) -Encoding UTF8
        Set-Content -LiteralPath $specPath -Value @(
            "# Custom Migration Work",
            "",
            "- The durable spec remains active.",
            "- Project-specific durable spec content must remain available.",
            "- $tokenLine"
        ) -Encoding UTF8

        $lockPath = Join-PathParts $projectDir ".agents" "hub.lock.json"
        $lockHashBeforeAnalyze = (Get-FileHash -LiteralPath $lockPath -Algorithm SHA256).Hash
        $bootstrapAnalyzeOutput = @(& $bootstrapScript -ProjectDir $projectDir -HubDir $hubDir -AnalyzeLanguageMigration -SourceLanguage $SourceLanguage -TargetLanguage $TargetLanguage 3>&1)
        if (@($bootstrapAnalyzeOutput | Where-Object { $_ -match '^Language migration analyze:' }).Count -lt 1) {
            throw "Bootstrap language migration analyze routing did not call the helper."
        }
        if (@($bootstrapAnalyzeOutput | Where-Object { $_ -match '^Project bootstrap complete\.' }).Count -gt 0) {
            throw "Bootstrap language migration analyze ran the normal bootstrap write path."
        }
        $lockHashAfterAnalyze = (Get-FileHash -LiteralPath $lockPath -Algorithm SHA256).Hash
        if ($lockHashBeforeAnalyze -ne $lockHashAfterAnalyze) {
            throw "Bootstrap language migration analyze modified .agents/hub.lock.json."
        }

        $analysis = & $languageMigrationScript -ProjectDir $projectDir -Mode Analyze -SourceLanguage $SourceLanguage -TargetLanguage $TargetLanguage -Json | ConvertFrom-Json
        if ([int]$analysis.summary.total -lt 1) {
            throw "Language migration Analyze did not inspect project memory."
        }
        if ([int]$analysis.summary.mixed_language -lt 1) {
            throw "Language migration Analyze did not report mixed-language fixture content."
        }

        Assert-ApplyFails -ExpectedToken "Migration plan is required" -Command {
            & $languageMigrationScript -ProjectDir $projectDir -Mode Apply -MigrationPlan (Join-PathParts $projectDir "missing-proposal.json") -Json
        }

        $plan = & $languageMigrationScript -ProjectDir $projectDir -Mode Plan -SourceLanguage $SourceLanguage -TargetLanguage $TargetLanguage -Json | ConvertFrom-Json
        $proposalPath = [string]$plan.proposal
        $backupDir = [string]$plan.backup_dir
        if ([string]::IsNullOrWhiteSpace($proposalPath) -or -not (Test-Path -LiteralPath $proposalPath)) {
            throw "Language migration Plan did not create proposal.json."
        }
        if ([string]::IsNullOrWhiteSpace($backupDir) -or -not (Test-Path -LiteralPath $backupDir)) {
            throw "Language migration Plan did not create the backup required before apply."
        }
        if ([int]$plan.summary.manual_review -lt 2) {
            throw "Language migration Plan did not route customized content to manual review."
        }
        if ([int]$plan.summary.template_replacements -lt 1) {
            throw "Language migration Plan did not identify source template replacements."
        }
        if ([int]$plan.summary.hot_memory_routes -lt 3) {
            throw "Language migration Plan did not route customized hot memory to manual-review artifacts."
        }

        $otherProjectDir = Join-PathParts $scratchRootFull ("{0}-wrong-project" -f $Name)
        New-Item -ItemType Directory -Force -Path $otherProjectDir | Out-Null
        Assert-ApplyFails -ExpectedToken "project mismatch" -Command {
            & $languageMigrationScript -ProjectDir $otherProjectDir -Mode Apply -MigrationPlan $proposalPath -Json
        }
        Assert-ApplyFails -ExpectedToken "project mismatch" -Command {
            & $languageMigrationScript -ProjectDir $otherProjectDir -Mode Validate -MigrationPlan $proposalPath -Json
        }

        if ($ExerciseMissingBackupFailure.IsPresent) {
            Assert-PathInsideRoot -Path $backupDir -Root $scratchRootFull
            Remove-Item -LiteralPath $backupDir -Recurse -Force
            Assert-ApplyFails -ExpectedToken "existing backup directory" -Command {
                & $languageMigrationScript -ProjectDir $projectDir -Mode Apply -MigrationPlan $proposalPath -Json
            }
            $plan = & $languageMigrationScript -ProjectDir $projectDir -Mode Plan -SourceLanguage $SourceLanguage -TargetLanguage $TargetLanguage -Json | ConvertFrom-Json
            $proposalPath = [string]$plan.proposal
            $backupDir = [string]$plan.backup_dir
        }

        $apply = & $languageMigrationScript -ProjectDir $projectDir -Mode Apply -MigrationPlan $proposalPath -Json | ConvertFrom-Json
        if ([int]$apply.apply_result.files_written -lt 1) {
            throw "Language migration Apply did not write any files."
        }
        $validate = & $languageMigrationScript -ProjectDir $projectDir -Mode Validate -MigrationPlan $proposalPath -Json | ConvertFrom-Json
        if (-not [bool]$validate.validation.valid) {
            throw "Language migration Validate did not report a valid result."
        }
        if ($validate.validation.PSObject.Properties.Name -notcontains "body_language_audit") {
            throw "Language migration Validate did not include body-level audit evidence."
        }
        if ($SourceLanguage -eq "en" -and $TargetLanguage -eq "zh-CN" -and [bool]$validate.validation.completion_ready) {
            throw "Phase 1 language migration validation claimed completion before reviewed narrative migration."
        }

        $lockPath = Join-PathParts $projectDir ".agents" "hub.lock.json"
        $lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
        if ([string]$lock.project_language -ne $TargetLanguage) {
            throw "Language migration did not update project_language to target language."
        }
        if ($lock.PSObject.Properties.Name -notcontains "language_migration") {
            throw "Language migration did not record lock metadata."
        }

        $agentGuide = Get-Content -LiteralPath $agentGuidePath -Raw
        foreach ($token in @($ExpectedTargetMarker, "language-migration:manual-review-source begin", "git status", "src/app.py", "Get-FooBar", "AGENTS.md", "feat", "ERROR_PATH_NOT_FOUND", "CustomThing")) {
            if ($agentGuide -notlike ("*{0}*" -f $token)) {
                throw "Language migration did not preserve expected token in .agents/AGENTS.md: $token"
            }
        }

        foreach ($hotPath in @($planPath, $processPath, $notesPath)) {
            $hotText = Get-Content -LiteralPath $hotPath -Raw
            if ($hotText -notlike ("*{0}*" -f $ExpectedTargetMarker)) {
                throw "Language migration did not write target marker to hot memory file: $hotPath"
            }
            if ($hotText -like "*language-migration:manual-review-source begin*" -or $hotText -like "*Hot memory source token*" -or $hotText -like "*Hot memory process token*" -or $hotText -like "*Hot memory notes token*") {
                throw "Language migration inflated hot memory instead of routing source content to an artifact: $hotPath"
            }
        }

        $hotArtifacts = @($apply.apply_result.actions | Where-Object { [string]$_.action -eq "route-hot-memory-manual-review" })
        if ($hotArtifacts.Count -lt 3) {
            throw "Language migration Apply did not record hot memory manual-review artifacts."
        }
        foreach ($hotArtifact in $hotArtifacts) {
            $artifactPath = [string]$hotArtifact.manual_review_artifact
            if ([string]::IsNullOrWhiteSpace($artifactPath) -or -not (Test-Path -LiteralPath $artifactPath)) {
                throw "Language migration hot memory manual-review artifact is missing."
            }
            $artifactText = Get-Content -LiteralPath $artifactPath -Raw
            if ($artifactText -notlike "*language-migration:manual-review-source begin*" -or $artifactText -notlike "*ERROR_PATH_NOT_FOUND*" -or $artifactText -notlike "*source_hash_sha256:*") {
                throw "Language migration hot memory artifact did not preserve source review evidence."
            }
        }

        $contextText = Get-Content -LiteralPath $contextPath -Raw
        foreach ($token in @("中文 mixed memory marker", "ERROR_PATH_NOT_FOUND", "src/app.py", "Get-FooBar", "CustomThing")) {
            if ($contextText -notlike ("*{0}*" -f $token)) {
                throw "Language migration changed or dropped custom context token: $token"
            }
        }

        $templateSpecPath = Join-PathParts $projectDir "docs" "specs" "_templates" "spec-lite.md"
        $templateSpecText = Get-Content -LiteralPath $templateSpecPath -Raw
        if ($templateSpecText -notlike ("*{0}*" -f $ExpectedTargetMarker)) {
            throw "Language migration did not replace exact source spec template with the target language template."
        }

        $narrativePlan = & $languageMigrationScript -ProjectDir $projectDir -Mode PlanNarrative -MigrationPlan $proposalPath -Json | ConvertFrom-Json
        $narrativeProposalPath = [string]$narrativePlan.proposal
        if ([string]::IsNullOrWhiteSpace($narrativeProposalPath) -or -not (Test-Path -LiteralPath $narrativeProposalPath)) {
            throw "Narrative language migration did not create narrative-proposal.json."
        }
        foreach ($category in @("stable_facts", "active_plan", "process_state", "reusable_lessons", "durable_specs")) {
            if (@($narrativePlan.actions | Where-Object { [string]$_.category -eq $category }).Count -lt 1) {
                throw "Narrative language migration did not route category: $category"
            }
        }
        $narrativeProposal = Get-Content -LiteralPath $narrativeProposalPath -Raw | ConvertFrom-Json
        foreach ($action in @($narrativeProposal.actions)) {
            $action.approved = $true
        }
        $narrativeProposal | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $narrativeProposalPath -Encoding UTF8

        $narrativeApply = & $languageMigrationScript -ProjectDir $projectDir -Mode ApplyNarrative -MigrationPlan $narrativeProposalPath -Json | ConvertFrom-Json
        if ([int]$narrativeApply.apply_result.files_written -lt 5) {
            throw "Narrative language migration did not apply routed narrative actions."
        }
        $narrativeValidate = & $languageMigrationScript -ProjectDir $projectDir -Mode ValidateNarrative -MigrationPlan $narrativeProposalPath -Json | ConvertFrom-Json
        if (-not [bool]$narrativeValidate.validation.valid) {
            throw "Narrative language migration did not validate."
        }
        if ($narrativeValidate.validation.PSObject.Properties.Name -notcontains "body_language_audit") {
            throw "Narrative language migration validation did not include body-level audit evidence."
        }
        if (@($narrativeValidate.validation.findings | Where-Object { [string]$_.severity -eq "error" }).Count -gt 0) {
            throw "Narrative language migration validation reported blocking errors after reviewed narrative apply."
        }

        $stableFactsPath = Join-PathParts $projectDir ".agents" "context" "tech" "language-migration-stable-facts.md"
        $stableFactsText = Get-Content -LiteralPath $stableFactsPath -Raw
        $planNarrativeText = Get-Content -LiteralPath $planPath -Raw
        $processNarrativeText = Get-Content -LiteralPath $processPath -Raw
        $contextNarrativeText = Get-Content -LiteralPath $contextPath -Raw
        $specNarrativeText = Get-Content -LiteralPath $specPath -Raw
        foreach ($textAndToken in @(
            @($stableFactsText, "language-migration:narrative begin"),
            @($planNarrativeText, "language-migration:narrative begin"),
            @($processNarrativeText, "language-migration:narrative begin"),
            @($contextNarrativeText, "language-migration:narrative begin"),
            @($specNarrativeText, "language-migration:narrative begin"),
            @($stableFactsText, "feature flags"),
            @($contextNarrativeText, "ERROR_PATH_NOT_FOUND"),
            @($specNarrativeText, "CustomThing")
        )) {
            if ([string]$textAndToken[0] -notlike ("*{0}*" -f [string]$textAndToken[1])) {
                throw "Narrative language migration missing expected token: $($textAndToken[1])"
            }
        }
        if ($TargetLanguage -eq "zh-CN" -and $stableFactsText -notlike "*项目使用 feature flags。*") {
            throw "Narrative language migration did not draft zh-CN stable facts text."
        }
        if ($TargetLanguage -eq "en" -and $stableFactsText -notlike "*Project uses feature flags.*") {
            throw "Narrative language migration did not draft English stable facts text."
        }

        if ($TargetLanguage -eq "zh-CN") {
            $originalSpecText = Get-Content -LiteralPath $specPath -Raw
            try {
                Add-Content -LiteralPath $specPath -Value "`nThis leftover source-language paragraph should fail body-level audit validation before completion because ordinary migration must not leave long English narrative source text in the reviewed target memory file."
                Assert-ApplyFails -ExpectedToken "narrative validation failed" -Command {
                    & $languageMigrationScript -ProjectDir $projectDir -Mode ValidateNarrative -MigrationPlan $narrativeProposalPath -Json
                }
            }
            finally {
                Set-Content -LiteralPath $specPath -Value $originalSpecText -Encoding UTF8
            }
        }

        return [ordered]@{
            project = $projectDir
            source_language = $SourceLanguage
            target_language = $TargetLanguage
            analyzed = [int]$analysis.summary.total
            writes = [int]$plan.summary.writes
            manual_review = [int]$plan.summary.manual_review
            mixed_language = [int]$analysis.summary.mixed_language
            proposal = $proposalPath
            backup = $backupDir
            result = [string]$apply.apply_result.result
            narrative_proposal = $narrativeProposalPath
            narrative_result = [string]$narrativeApply.apply_result.result
            body_language_audit_findings = [int]$narrativeValidate.validation.body_language_audit.summary.finding_count
            validated = [bool]$validate.validation.valid
            narrative_validated = [bool]$narrativeValidate.validation.valid
        }
    }

    $migrationEvidence = @()
    $migrationEvidence += Invoke-LanguageMigrationFixture -Name "language-migration-en-to-zh-cn" -SourceLanguage "en" -TargetLanguage "zh-CN" -ExpectedTargetMarker "项目记忆语言：简体中文。" -ExerciseMissingBackupFailure
    $migrationEvidence += Invoke-LanguageMigrationFixture -Name "language-migration-zh-cn-to-en" -SourceLanguage "zh-CN" -TargetLanguage "en" -ExpectedTargetMarker "Project memory language: English."

    $script:evidence.language_migration = [ordered]@{
        fixtures = @($migrationEvidence)
    }

    Add-Check "conservative language migration" "PASS" "Conservative en/zh-CN migration covers analyze, proposal, backup, apply, reviewed narrative migration, protected literal preservation, body-level audit validation, and source-language leftover rejection." $evidence.language_migration
}
catch {
    Add-Check "conservative language migration" "FAIL" $_.Exception.Message
}

try {
    if ([string]::IsNullOrWhiteSpace($script:recommendedCopyRuntime)) {
        throw "Recommended copy runtime was not created."
    }

    $preserveProject = Join-PathParts $scratchRootFull "bootstrap-memory-preservation-project"
    New-Item -ItemType Directory -Force -Path $preserveProject | Out-Null
    Assert-PathInsideRoot -Path $preserveProject -Root $scratchRootFull

    $hubDir = Join-PathParts $script:recommendedCopyRuntime "knowledge-hub"
    $bootstrapScript = Join-PathParts $script:recommendedCopyRuntime "skills" "project-bootstrap" "scripts" "bootstrap_project.ps1"
    & $bootstrapScript -ProjectDir $preserveProject -HubDir $hubDir -ProjectLanguage "en" -SkipMemoryUpgradeAnalysis | Out-Host

    $rootAgentsPath = Join-PathParts $preserveProject "AGENTS.md"
    $agentGuidePath = Join-PathParts $preserveProject ".agents" "AGENTS.md"
    $processPath = Join-PathParts $preserveProject ".agents" "process.txt"
    $replaceableTemplatePath = Join-PathParts $preserveProject "docs" "specs" "README.md"
    $rootSentinel = "CUSTOM ROOT MEMORY SENTINEL"
    $agentSentinel = "CUSTOM AGENT GUIDE SENTINEL"
    $processSentinel = "CUSTOM PROCESS MEMORY SENTINEL"
    $replaceableSentinel = "CUSTOM REPLACEABLE TEMPLATE SENTINEL"
    $rootCustomSections = @("Workspace Model", "Git Policy", "Governance Responsibilities")
    $agentCustomSections = @("Language Policy", "Session Load Order", "Recording Rules")
    Add-Content -LiteralPath $rootAgentsPath -Value "`n$rootSentinel"
    foreach ($section in $rootCustomSections) {
        Add-Content -LiteralPath $rootAgentsPath -Value ("`n## {0}`n- project-specific {1} rule" -f $section, $section)
    }
    Add-Content -LiteralPath $agentGuidePath -Value "`n$agentSentinel"
    foreach ($section in $agentCustomSections) {
        Add-Content -LiteralPath $agentGuidePath -Value ("`n## {0}`n- project-specific {1} rule" -f $section, $section)
    }
    Add-Content -LiteralPath $processPath -Value "`n$processSentinel"
    Add-Content -LiteralPath $replaceableTemplatePath -Value "`n$replaceableSentinel"

    $preserveOutput = @(& $bootstrapScript -ProjectDir $preserveProject -HubDir $hubDir -OverwriteTemplates -ProjectLanguage "zh-CN" -SkipMemoryUpgradeAnalysis 3>&1)

    if ((Get-Content -LiteralPath $rootAgentsPath -Raw) -notlike ("*{0}*" -f $rootSentinel)) {
        throw "Bootstrap refresh overwrote customized root AGENTS.md content."
    }
    if ((Get-Content -LiteralPath $agentGuidePath -Raw) -notlike ("*{0}*" -f $agentSentinel)) {
        throw "Bootstrap refresh overwrote customized .agents/AGENTS.md content."
    }
    if ((Get-Content -LiteralPath $processPath -Raw) -notlike ("*{0}*" -f $processSentinel)) {
        throw "Bootstrap refresh overwrote customized .agents/process.txt content."
    }
    if ((Get-Content -LiteralPath $replaceableTemplatePath -Raw) -notlike ("*{0}*" -f $replaceableSentinel)) {
        throw "Compatibility overwrite refreshed a modified template file instead of preserving it."
    }
    $rootAgentsText = Get-Content -LiteralPath $rootAgentsPath -Raw
    foreach ($section in $rootCustomSections) {
        if ($rootAgentsText -notlike ("*## {0}*" -f $section)) {
            throw "Bootstrap refresh dropped customized root AGENTS.md section: $section"
        }
    }
    $agentGuideText = Get-Content -LiteralPath $agentGuidePath -Raw
    foreach ($section in $agentCustomSections) {
        if ($agentGuideText -notlike ("*## {0}*" -f $section)) {
            throw "Bootstrap refresh dropped customized .agents/AGENTS.md section: $section"
        }
    }
    if (@($preserveOutput | Where-Object { $_ -match '^Template files preserved for manual review:' }).Count -lt 1) {
        throw "Bootstrap refresh did not report preserved memory files for manual review."
    }
    if (@($preserveOutput | Where-Object { [string]$_ -match '-OverwriteTemplates is a compatibility alias for -RefreshUnmodifiedTemplates' }).Count -lt 1) {
        throw "Compatibility overwrite did not emit the expected warning."
    }
    if (@($preserveOutput | Where-Object { $_ -match '^Template refresh mode: unmodified template files may be refreshed;' }).Count -lt 1) {
        throw "Compatibility overwrite did not report refresh-unmodified mode."
    }
    if (@($preserveOutput | Where-Object { $_ -match '^Project language refresh preserved existing memory files;' }).Count -lt 1) {
        throw "Bootstrap language refresh did not report existing memory preservation."
    }
    if (@($preserveOutput | Where-Object { $_ -match '^Bootstrap evidence report:' }).Count -lt 1) {
        throw "Bootstrap refresh did not report the evidence report path."
    }

    $lockPath = Join-PathParts $preserveProject ".agents" "hub.lock.json"
    $lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
    if ([string]$lock.bootstrap_operation_mode -ne "refresh-unmodified-templates") {
        throw "Bootstrap lock did not record refresh-unmodified operation mode."
    }
    if (-not [bool]$lock.refresh_unmodified_templates) {
        throw "Bootstrap lock did not record refresh_unmodified_templates."
    }
    if ([int]$lock.template_manual_review_count -lt 4) {
        throw "Bootstrap lock did not record manual-review files."
    }
    $evidenceJsonPath = [string]$lock.template_evidence_report_json
    $evidenceMarkdownPath = [string]$lock.template_evidence_report_markdown
    if ([string]::IsNullOrWhiteSpace($evidenceJsonPath) -or -not (Test-Path -LiteralPath $evidenceJsonPath)) {
        throw "Bootstrap refresh did not create a JSON evidence report."
    }
    if ([string]::IsNullOrWhiteSpace($evidenceMarkdownPath) -or -not (Test-Path -LiteralPath $evidenceMarkdownPath)) {
        throw "Bootstrap refresh did not create a Markdown evidence report."
    }
    $bootstrapEvidence = Get-Content -LiteralPath $evidenceJsonPath -Raw | ConvertFrom-Json
    $preserved = @($bootstrapEvidence.preserved | ForEach-Object { [string]$_ })
    $manualReview = @($bootstrapEvidence.manual_review | ForEach-Object { [string]$_ })
    $replaced = @($bootstrapEvidence.replaced | ForEach-Object { [string]$_ })
    $skipped = @($bootstrapEvidence.skipped | ForEach-Object { [string]$_ })
    $backup = @($bootstrapEvidence.backup)

    foreach ($requiredMemoryPath in @("AGENTS.md", ".agents/AGENTS.md", ".agents/process.txt", "docs/specs/README.md")) {
        if ($preserved -notcontains $requiredMemoryPath) {
            throw "Bootstrap evidence report did not list $requiredMemoryPath as preserved."
        }
        if ($manualReview -notcontains $requiredMemoryPath) {
            throw "Bootstrap evidence report did not list $requiredMemoryPath for manual review."
        }
    }
    if ($replaced -contains "docs/specs/README.md") {
        throw "Bootstrap evidence report listed a modified template as replaced during compatibility overwrite."
    }
    if ($bootstrapEvidence.PSObject.Properties.Name -notcontains "skipped") {
        throw "Bootstrap evidence report did not include a skipped group."
    }
    if ((Get-Content -LiteralPath $evidenceMarkdownPath -Raw) -notmatch '(?m)^## Skipped\r?$') {
        throw "Bootstrap Markdown evidence report did not include a Skipped section."
    }
    $forceOutput = @(& $bootstrapScript -ProjectDir $preserveProject -HubDir $hubDir -ForceResetScaffold -ProjectLanguage "zh-CN" -SkipMemoryUpgradeAnalysis 3>&1)
    if (@($forceOutput | Where-Object { [string]$_ -match '-ForceResetScaffold can replace existing scaffold and memory template files' }).Count -lt 1) {
        throw "Force reset did not emit the expected warning."
    }
    if (@($forceOutput | Where-Object { $_ -match '^Template reset mode: explicit force reset requested;' }).Count -lt 1) {
        throw "Force reset did not report explicit reset mode."
    }
    if ((Get-Content -LiteralPath $rootAgentsPath -Raw) -like ("*{0}*" -f $rootSentinel)) {
        throw "Force reset preserved customized root AGENTS.md content."
    }
    if ((Get-Content -LiteralPath $agentGuidePath -Raw) -like ("*{0}*" -f $agentSentinel)) {
        throw "Force reset preserved customized .agents/AGENTS.md content."
    }
    if ((Get-Content -LiteralPath $processPath -Raw) -like ("*{0}*" -f $processSentinel)) {
        throw "Force reset preserved customized .agents/process.txt content."
    }
    if ((Get-Content -LiteralPath $replaceableTemplatePath -Raw) -like ("*{0}*" -f $replaceableSentinel)) {
        throw "Force reset preserved customized docs/specs/README.md content."
    }

    $forceLock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
    if ([string]$forceLock.bootstrap_operation_mode -ne "explicit-force-reset") {
        throw "Force reset lock did not record explicit force-reset operation mode."
    }
    if (-not [bool]$forceLock.force_reset_scaffold) {
        throw "Force reset lock did not record force_reset_scaffold."
    }
    if (([int]$forceLock.template_backup_count + [int]$forceLock.language_backup_count) -lt 1) {
        throw "Force reset did not write backup evidence before replacement."
    }
    $forceBackupReadme = @(Get-ChildItem -LiteralPath (Join-PathParts $preserveProject ".agents" "_backup") -Recurse -File -Filter "README.md" | Where-Object {
        $_.FullName -like "*docs*specs*README.md"
    })
    if ($forceBackupReadme.Count -lt 1) {
        throw "Force reset did not create a backup copy for docs/specs/README.md."
    }

    Add-Check "bootstrap memory preservation" "PASS" "Bootstrap modes preserve modified memory by default and require explicit force reset for backup-first replacement." ([ordered]@{
        project = $preserveProject
        manual_review_count = [int]$lock.template_manual_review_count
        compatibility_mode = [string]$lock.bootstrap_operation_mode
        compatibility_backup_count = [int]$lock.template_backup_count
        force_mode = [string]$forceLock.bootstrap_operation_mode
        force_template_backup_count = [int]$forceLock.template_backup_count
        force_language_backup_count = [int]$forceLock.language_backup_count
        backup_dir = [string]$forceLock.template_backup_dir
        evidence_json = $evidenceJsonPath
        evidence_markdown = $evidenceMarkdownPath
        preserved_count = $preserved.Count
        replaced_count = $replaced.Count
        skipped_count = $skipped.Count
    })
}
catch {
    Add-Check "bootstrap memory preservation" "FAIL" $_.Exception.Message
}

}
