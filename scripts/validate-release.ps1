[CmdletBinding()]
param(
    [string]$ScratchRoot = "",
    [switch]$SkipLinkMode,
    [switch]$Json
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
$repoRoot = Split-Path -Parent $scriptDir
. (Join-Path $scriptDir "lib/path-guard.ps1")
. (Join-Path $scriptDir "validation/release-test-helper.ps1")
$runStamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss")

if ([string]::IsNullOrWhiteSpace($ScratchRoot)) {
    $ScratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-ecosystem-release-validation-{0}" -f $runStamp)
}

$scratchRootFull = [System.IO.Path]::GetFullPath($ScratchRoot)
$liveRuntimeCandidates = @(Get-AgentLiveRuntimeCandidates)

Assert-NotLiveRuntime -Path $scratchRootFull
New-Item -ItemType Directory -Force -Path $scratchRootFull | Out-Null

$checks = New-Object 'System.Collections.Generic.List[object]'
$evidence = [ordered]@{
    profile_matrix = @()
    runtime_smoke = [ordered]@{}
    audit = [ordered]@{}
    knowledge_hub = [ordered]@{}
    duplicate_helpers = @()
    memory_metadata = [ordered]@{}
    language_policy = [ordered]@{}
    language_migration = [ordered]@{}
    routing = [ordered]@{}
    scratch_retention = [ordered]@{}
    spec_lite = [ordered]@{}
    agent_template_guidance = [ordered]@{}
}

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
        Force = $true
    }
    if ($Mode -eq "copy") {
        $installParams.Copy = $true
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
    if ($mode -eq "copy" -and [bool]$manifest.link_preferred) {
        $errors.Add("copy mode should not prefer links")
    }
    if ($mode -eq "link" -and -not [bool]$manifest.link_preferred) {
        $errors.Add("link mode should prefer links")
    }

    $items = @($manifest.items)
    if ($items.Count -ne (1 + $ExpectedSkills.Count)) {
        $errors.Add(("item count mismatch: expected {0}, got {1}" -f (1 + $ExpectedSkills.Count), $items.Count))
    }

    foreach ($item in $items) {
        foreach ($field in @("name", "source", "destination", "mode")) {
            if ([string]::IsNullOrWhiteSpace([string]$item.$field)) {
                $errors.Add("manifest item missing field: $field")
            }
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$item.destination)) {
            try {
                Assert-PathInsideRoot -Path ([string]$item.destination) -Root $targetDir
                Assert-NotLiveRuntime -Path ([string]$item.destination)
            }
            catch {
                $errors.Add($_.Exception.Message)
            }
        }
        if ($mode -eq "copy" -and [string]$item.mode -ne "copy") {
            $errors.Add(("copy install item used mode {0}" -f $item.mode))
        }
        if ($mode -eq "link" -and [string]$item.mode -notin @("junction", "symboliclink", "copy-fallback")) {
            $errors.Add(("link install item used unexpected mode {0}" -f $item.mode))
        }
    }

    return @($errors.ToArray())
}

try {

$requiredFiles = @(
    "README.md",
    "README.zh-CN.md",
    "LICENSE",
    "CHANGELOG.md",
    "CONTRIBUTING.md",
    "SECURITY.md",
    "scripts/benchmark-context-gate.ps1",
    "scripts/install.ps1",
    "scripts/lib/path-guard.ps1",
    "scripts/prune-validation-scratch.ps1",
    "scripts/uninstall.ps1",
    "scripts/validation/release-test-helper.ps1",
    "scripts/validate-release.ps1",
    "docs/architecture.md",
    "docs/existing-project-upgrade.md",
    "docs/how-to-adapt.md",
    "docs/language-policy.md",
    "docs/release-process.md",
    "docs/release-readiness.md",
    "docs/shell-strategy.md",
    "docs/template-path-reference-audit.md",
    "docs/releases/v0.1.0.md",
    "docs/releases/v0.2.0.md",
    "docs/releases/v0.3.0.md",
    "docs/releases/v0.3.1.md",
    "docs/releases/v0.4.0.md",
    "docs/releases/v0.4.1.md",
    "docs/releases/v0.4.2.md",
    "docs/releases/v0.4.3.md",
    "knowledge-hub/knowledge-catalog.md",
    "knowledge-hub/knowledge/standards/bilingual-public-private-routing.md",
    "skills/workflow-spec-lite/scripts/validate_spec.ps1",
    "examples/minimal-project/README.md",
    "examples/minimal-project/.agents/AGENTS.md",
    "examples/minimal-project/docs/specs/example-work/spec.md",
    "examples/minimal-project/docs/specs/example-work/tasks.md"
)
$missingFiles = @($requiredFiles | Where-Object { -not (Test-RequiredPath -RelativePath $_) })

$requiredDirs = @(
    "skills/project-bootstrap",
    "skills/project-context-gate",
    "skills/workflow-spec-lite",
    "skills/memory-governance",
    "knowledge-hub/templates",
    "knowledge-hub/templates/languages/en/project-root",
    "knowledge-hub/templates/languages/en/project-agent",
    "knowledge-hub/templates/languages/zh-CN/project-root",
    "knowledge-hub/templates/languages/zh-CN/project-agent",
    "knowledge-hub/scripts",
    "knowledge-hub/knowledge/experience",
    "knowledge-hub/knowledge/patterns",
    "knowledge-hub/knowledge/standards",
    "knowledge-hub/knowledge/domain-packs",
    "skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/en/project-root",
    "skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/en/project-agent",
    "skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/zh-CN/project-root",
    "skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/zh-CN/project-agent"
)
$missingDirs = @($requiredDirs | Where-Object { -not (Test-RequiredPath -RelativePath $_ -Directory) })
$forbiddenDirs = @(
    "knowledge-hub/templates/project-root",
    "knowledge-hub/templates/project-agent",
    "knowledge-hub/templates/project-memory",
    "skills/project-bootstrap/assets/knowledge-hub-template/templates/project-root",
    "skills/project-bootstrap/assets/knowledge-hub-template/templates/project-agent",
    "skills/project-bootstrap/assets/knowledge-hub-template/templates/project-memory",
    "skills/project-bootstrap/templates/project-memory"
)
$presentForbiddenDirs = @($forbiddenDirs | Where-Object { Test-RequiredPath -RelativePath $_ -Directory })

if ($missingFiles.Count -eq 0 -and $missingDirs.Count -eq 0 -and $presentForbiddenDirs.Count -eq 0) {
    Add-Check "public structure" "PASS" "Required release files, skills, docs, knowledge hub paths, and language-scoped template paths exist; legacy template entry paths are absent."
}
else {
    Add-Check "public structure" "FAIL" "Required public paths are missing or forbidden legacy paths are present." ([ordered]@{ files = $missingFiles; directories = $missingDirs; forbidden_directories = $presentForbiddenDirs })
}

try {
    $legacyReferencePattern = 'templates/project-root|templates/project-agent|templates/project-memory|project-bootstrap/templates/project-memory'
    $allowedLegacyReferenceFiles = @(
        "CHANGELOG.md",
        "docs/release-readiness.md",
        "docs/releases/v0.4.1.md",
        "docs/releases/v0.4.2.md",
        "docs/template-path-reference-audit.md",
        "scripts/validate-release.ps1",
        "skills/project-bootstrap/scripts/init_hub.ps1"
    )
    $legacyMatches = New-Object 'System.Collections.Generic.List[object]'
    $unexpectedLegacyMatches = New-Object 'System.Collections.Generic.List[object]'

    foreach ($file in @(Get-GitFiles)) {
        foreach ($match in @(Get-LineMatches -RelativePath $file -Pattern $legacyReferencePattern)) {
            $legacyMatches.Add([object]$match)
            $isAllowed = $false

            if ($file -in $allowedLegacyReferenceFiles) {
                $isAllowed = $true
            }
            elseif ($file -like "docs/specs/*") {
                $fileText = Get-FileText -RelativePath $file
                $isAllowed = ($fileText -match "Historical note:" -and $fileText -match "(legacy|superseded|removed|negative validation)")
            }

            if (-not $isAllowed) {
                $unexpectedLegacyMatches.Add([object]$match)
            }
        }
    }

    $script:evidence.legacy_template_references = [ordered]@{
        total_matches = $legacyMatches.Count
        unexpected_matches = @($unexpectedLegacyMatches.ToArray())
        allowed_files = @($allowedLegacyReferenceFiles)
    }

    if ($unexpectedLegacyMatches.Count -gt 0) {
        Add-Check "legacy template path references" "FAIL" "Legacy template path references appeared outside allowed validator, remediation, or marked historical records." @($unexpectedLegacyMatches.ToArray())
    }
    else {
        Add-Check "legacy template path references" "PASS" ("Legacy template path references are limited to validator/remediation logic or marked historical records ({0} matches)." -f $legacyMatches.Count) $evidence.legacy_template_references
    }
}
catch {
    Add-Check "legacy template path references" "FAIL" $_.Exception.Message
}

try {
    $upgradeGuide = Get-FileText -RelativePath "docs/existing-project-upgrade.md"
    $adaptGuide = Get-FileText -RelativePath "docs/how-to-adapt.md"
    $bootstrapReadme = Get-FileText -RelativePath "skills/project-bootstrap/README.md"
    $upgradeTokens = @(
        "language-scoped project-memory templates",
        "templates/languages/<language>/project-root|project-agent",
        "project-specific memory",
        ".agents/context/experience",
        ".agents/context/patterns",
        ".agents/context/standards",
        "analyze -> plan -> backup -> apply -> validate",
        "memory_upgrade.ps1",
        "-Mode Analyze",
        "-AnalyzeMemoryUpgrade",
        "missing scaffold files",
        "memory-only and no-edit",
        "Do not recreate legacy template directories",
        "ApplyMemoryUpgrade",
        "Validate"
    )
    $missingUpgradeTokens = @($upgradeTokens | Where-Object { $upgradeGuide -notlike "*$_*" })
    $missingLinks = @()
    if ($adaptGuide -notlike "*existing project upgrade path*") {
        $missingLinks += "docs/how-to-adapt.md missing existing project upgrade path link."
    }
    if ($bootstrapReadme -notlike "*docs/existing-project-upgrade.md*") {
        $missingLinks += "skills/project-bootstrap/README.md missing existing project upgrade guide link."
    }

    if ($missingUpgradeTokens.Count -gt 0 -or $missingLinks.Count -gt 0) {
        Add-Check "existing project upgrade path" "FAIL" "Existing project upgrade guidance is incomplete." ([ordered]@{
            missing_tokens = @($missingUpgradeTokens)
            missing_links = @($missingLinks)
        })
    }
    else {
        Add-Check "existing project upgrade path" "PASS" "Existing project upgrade guidance covers language-scoped templates, memory preservation, conservative flow, old path handling, and validation."
    }
}
catch {
    Add-Check "existing project upgrade path" "FAIL" $_.Exception.Message
}

try {
    $initHubScript = Join-PathParts $repoRoot "skills" "project-bootstrap" "scripts" "init_hub.ps1"
    $defaultHub = Join-PathParts $scratchRootFull "init-hub-default"
    $explicitGitHub = Join-PathParts $scratchRootFull "init-hub-explicit-git"
    Assert-PathInsideRoot -Path $defaultHub -Root $scratchRootFull
    Assert-PathInsideRoot -Path $explicitGitHub -Root $scratchRootFull

    & $initHubScript -HubDir $defaultHub | Out-Host
    if (Test-Path -LiteralPath (Join-PathParts $defaultHub ".git")) {
        throw "init_hub.ps1 created .git without -InitializeGit or -CommitInitial."
    }

    & $initHubScript -HubDir $explicitGitHub -InitializeGit | Out-Host
    if (-not (Test-Path -LiteralPath (Join-PathParts $explicitGitHub ".git"))) {
        throw "init_hub.ps1 -InitializeGit did not create .git."
    }

    Add-Check "hub initialization git mode" "PASS" "init_hub.ps1 leaves default hubs as ordinary directories and initializes Git only when requested." ([ordered]@{
        default_hub = $defaultHub
        explicit_git_hub = $explicitGitHub
    })
}
catch {
    Add-Check "hub initialization git mode" "FAIL" $_.Exception.Message
}

try {
    $pathGuardHelper = Get-FileText -RelativePath "scripts/lib/path-guard.ps1"
    $pathGuardConsumers = @("scripts/benchmark-context-gate.ps1", "scripts/install.ps1", "scripts/prune-validation-scratch.ps1", "scripts/uninstall.ps1", "scripts/validate-release.ps1")
    $missingDotSource = New-Object 'System.Collections.Generic.List[string]'
    $localDefinitions = New-Object 'System.Collections.Generic.List[string]'

    foreach ($functionName in @("Join-PathParts", "Assert-PathInsideRoot", "Assert-NotLiveRuntime")) {
        if ($pathGuardHelper -notmatch ("(?m)^function\s+{0}\s*\{{" -f [regex]::Escape($functionName))) {
            $localDefinitions.Add("scripts/lib/path-guard.ps1 missing $functionName")
        }
    }

    foreach ($consumer in $pathGuardConsumers) {
        $consumerText = Get-FileText -RelativePath $consumer
        if ($consumerText -notmatch 'lib/path-guard\.ps1') {
            $missingDotSource.Add("$consumer does not dot-source scripts/lib/path-guard.ps1")
        }
        foreach ($functionName in @("Join-PathParts", "Assert-PathInsideRoot", "Assert-NotLiveRuntime")) {
            if ($consumerText -match ("(?m)^function\s+{0}\s*\{{" -f [regex]::Escape($functionName))) {
                $localDefinitions.Add("$consumer still defines $functionName locally")
            }
        }
    }

    if ($missingDotSource.Count -eq 0 -and $localDefinitions.Count -eq 0) {
        Add-Check "shared path guard helper" "PASS" "Installer and release validator use the shared PowerShell path guard helper." ([ordered]@{
            helper = "scripts/lib/path-guard.ps1"
            consumers = @($pathGuardConsumers)
        })
    }
    else {
        Add-Check "shared path guard helper" "FAIL" "Shared path guard helper wiring is incomplete." ([ordered]@{
            missing_dot_source = @($missingDotSource.ToArray())
            local_definitions = @($localDefinitions.ToArray())
        })
    }
}
catch {
    Add-Check "shared path guard helper" "FAIL" $_.Exception.Message
}

try {
    $releaseHelper = Get-FileText -RelativePath "scripts/validation/release-test-helper.ps1"
    $validatorText = Get-FileText -RelativePath "scripts/validate-release.ps1"
    $helperFunctions = @(
        "ConvertTo-DisplayPath",
        "Add-Check",
        "Test-RequiredPath",
        "Get-GitFiles",
        "Get-FileText",
        "Get-LineMatches",
        "Get-CurrentPowerShellPath",
        "Get-PowerShellFileArguments",
        "Invoke-IsolatedPowerShellScript",
        "Test-ExactArray"
    )
    $helperErrors = New-Object 'System.Collections.Generic.List[string]'

    if ($validatorText -notmatch 'validation/release-test-helper\.ps1') {
        $helperErrors.Add("scripts/validate-release.ps1 does not dot-source scripts/validation/release-test-helper.ps1")
    }
    foreach ($functionName in $helperFunctions) {
        if ($releaseHelper -notmatch ("(?m)^function\s+{0}\s*\{{" -f [regex]::Escape($functionName))) {
            $helperErrors.Add("scripts/validation/release-test-helper.ps1 missing $functionName")
        }
        if ($validatorText -match ("(?m)^function\s+{0}\s*\{{" -f [regex]::Escape($functionName))) {
            $helperErrors.Add("scripts/validate-release.ps1 still defines $functionName locally")
        }
    }

    if ($helperErrors.Count -eq 0) {
        Add-Check "release validation helper" "PASS" "Release validator uses the shared validation helper for common test utilities." ([ordered]@{
            helper = "scripts/validation/release-test-helper.ps1"
            functions = @($helperFunctions)
        })
    }
    else {
        Add-Check "release validation helper" "FAIL" "Release validation helper wiring is incomplete." @($helperErrors.ToArray())
    }
}
catch {
    Add-Check "release validation helper" "FAIL" $_.Exception.Message
}

$skillNames = @("project-bootstrap", "project-context-gate", "workflow-spec-lite", "memory-governance")
$metadataErrors = New-Object 'System.Collections.Generic.List[string]'
foreach ($skillName in $skillNames) {
    $skillPath = "skills/$skillName/SKILL.md"
    $content = Get-FileText -RelativePath $skillPath
    foreach ($line in @("category: kernel", "stability: stable", "scope: cross-project")) {
        $pattern = "(?m)^\s*{0}\s*$" -f [regex]::Escape($line)
        if ($content -notmatch $pattern) {
            $metadataErrors.Add("$skillPath missing $line")
        }
    }
}
if ($metadataErrors.Count -eq 0) {
    Add-Check "skill metadata" "PASS" "All Workflow Kernel skills include category, stability, and scope metadata."
}
else {
    Add-Check "skill metadata" "FAIL" "Skill metadata mismatch." @($metadataErrors.ToArray())
}

$profileExpectations = [ordered]@{
    minimal = @("project-bootstrap")
    recommended = @("project-bootstrap", "project-context-gate", "workflow-spec-lite", "memory-governance")
    full = @("project-bootstrap", "project-context-gate", "workflow-spec-lite", "memory-governance")
    dev = @("project-bootstrap", "project-context-gate", "workflow-spec-lite", "memory-governance")
}

$installModes = @("copy")
if (-not $SkipLinkMode.IsPresent) {
    $installModes += "link"
}

$installFailures = New-Object 'System.Collections.Generic.List[string]'
$recommendedCopyRuntime = $null
$recommendedLinkRuntime = $null
foreach ($profile in $profileExpectations.Keys) {
    foreach ($mode in $installModes) {
        try {
            $result = Invoke-InstallerProfile -Profile $profile -Mode $mode
            $errors = @(Test-Manifest -InstallResult $result -ExpectedSkills $profileExpectations[$profile])
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
                $recommendedCopyRuntime = $result.target_dir
            }
            if ($profile -eq "recommended" -and $mode -eq "link") {
                $recommendedLinkRuntime = $result.target_dir
            }
        }
        catch {
            $installFailures.Add(("{0}/{1}: {2}" -f $profile, $mode, $_.Exception.Message))
        }
    }
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
        spec = $specTarget
        tasks = $tasksTarget
        memory_diagnose_findings = $findingCount
        hub_lock_status = $hubLockStatus
    }
}

try {
    if ([string]::IsNullOrWhiteSpace($recommendedCopyRuntime)) {
        throw "Recommended copy runtime was not created."
    }

    $runtimeSmokeResults = New-Object 'System.Collections.Generic.List[object]'
    $runtimeSmokeResults.Add((Invoke-RuntimeSmoke -RuntimeDir $recommendedCopyRuntime -Name "copy"))

    if (-not $SkipLinkMode.IsPresent) {
        if ([string]::IsNullOrWhiteSpace($recommendedLinkRuntime)) {
            throw "Recommended link runtime was not created."
        }
        $runtimeSmokeResults.Add((Invoke-RuntimeSmoke -RuntimeDir $recommendedLinkRuntime -Name "link"))
    }

    $script:evidence.runtime_smoke = @($runtimeSmokeResults.ToArray())
    Add-Check "runtime smoke" "PASS" "Bootstrap, context gate, workflow-spec-lite, and memory-governance smoke checks passed for recommended runtime installs." $evidence.runtime_smoke
}
catch {
    Add-Check "runtime smoke" "FAIL" $_.Exception.Message
}

try {
    if ([string]::IsNullOrWhiteSpace($recommendedCopyRuntime)) {
        throw "Recommended copy runtime was not created."
    }

    $localizedProject = Join-PathParts $scratchRootFull "localized-context-discovery"
    New-Item -ItemType Directory -Force -Path $localizedProject | Out-Null
    Assert-PathInsideRoot -Path $localizedProject -Root $scratchRootFull

    $hubDir = Join-PathParts $recommendedCopyRuntime "knowledge-hub"
    $bootstrapScript = Join-PathParts $recommendedCopyRuntime "skills" "project-bootstrap" "scripts" "bootstrap_project.ps1"
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

    $memoryDiagnoseScript = Join-PathParts $recommendedCopyRuntime "skills" "memory-governance" "scripts" "memory_diagnose.ps1"
    $diagnose = & $memoryDiagnoseScript -ProjectRoot $localizedProject -Json | ConvertFrom-Json
    $diagnoseMetadataFindings = @($diagnose.findings | Where-Object { [string]$_.code -eq "context_missing_discovery_metadata" })

    $memoryUpgradeScript = Join-PathParts $recommendedCopyRuntime "skills" "project-bootstrap" "scripts" "memory_upgrade.ps1"
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

try {
    $specValidator = Join-PathParts $repoRoot "skills" "workflow-spec-lite" "scripts" "validate_spec.ps1"
    $fixtureDir = Join-PathParts $scratchRootFull "spec-lite-fixtures"
    New-Item -ItemType Directory -Force -Path $fixtureDir | Out-Null
    Assert-PathInsideRoot -Path $fixtureDir -Root $scratchRootFull

    $completeSpec = @"
# Work Spec

- **Title**: Spec validator fixture
- **Slug**: spec-validator-fixture
- **Status**: Active
- **Owner**: release validation
- **Updated**: 2026-05-08

## 1. Summary
- Validate the workflow-spec-lite spec validator helper.

## 2. Current Context
- Release validation creates temporary positive and negative fixtures.

## 3. Goals
- Confirm complete specs pass.

## 4. Non-Goals
- Do not rewrite or normalize the target spec automatically.

## 5. Constraints
- Run only against temporary fixture files.

## 6. Assumptions
- Markdown headings follow the lightweight spec template.

## 7. Risks
- Missing acceptance or stop rules can let scope drift go unnoticed.

## 8. Proposed Approach
- Execute the validator and inspect structured findings.

## 9. Acceptance / Evidence
- Positive fixture passes and targeted negative fixtures fail.

## 10. Loop Contract
- Not required for this fixture.

## 11. Execution Contract
- Use for multi-phase work where the agent should continue after each validated phase.
- **Autonomy level**: bounded-autonomous
- **Phase list**:
  - P01: Run validator fixture checks.
- **Continue rule**: Continue only when fixture results match expectations.
- **Stop rule**: Stop when required goals, non-goals, risks, acceptance, or stop rule fields are missing.
- **State record**: release validation evidence.

## 12. Open Questions
- None for this fixture.
"@

    $positivePath = Join-PathParts $fixtureDir "complete-spec.md"
    Set-Content -LiteralPath $positivePath -Value $completeSpec -Encoding UTF8
    $positive = & $specValidator -SpecPath $positivePath -RequireExecutionContract -Json | ConvertFrom-Json
    if (-not [bool]$positive.pass) {
        throw ("Complete spec fixture failed: {0}" -f (($positive.findings | ConvertTo-Json -Compress -Depth 5)))
    }

    $loopSpec = @"
# Work Spec

- **Title**: Loop contract fixture
- **Slug**: loop-contract-fixture
- **Status**: Active
- **Owner**: release validation
- **Updated**: 2026-05-08

## 1. Summary
- Validate that loop-oriented specs can pass the lightweight validator.

## 2. Current Context
- Release validation needs a positive fixture with a Loop Contract.

## 3. Goals
- Confirm loop specs pass when required sections are present.

## 4. Non-Goals
- Do not execute the loop action.

## 5. Constraints
- Run only against temporary fixture files.

## 6. Assumptions
- The loop contract is agent-facing state, not executable code.

## 7. Risks
- A vague loop can lead to unbounded repeated work.

## 8. Proposed Approach
- Validate a bounded Loop Contract fixture.

## 9. Acceptance / Evidence
- The Loop Contract fixture passes validation.

## 10. Loop Contract
- **Variable**: retry count
- **Source of truth**: temporary fixture text
- **Check command**: inspect fixture
- **Pass predicate**: retry count is below the limit
- **Iteration action**: no-op validation fixture
- **State record**: release validation evidence
- **Limits**: one validation attempt
- **Abort conditions**: missing required spec sections

## 11. Execution Contract

## 12. Open Questions
- None for this fixture.
"@

    $loopPath = Join-PathParts $fixtureDir "loop-contract-spec.md"
    Set-Content -LiteralPath $loopPath -Value $loopSpec -Encoding UTF8
    $loopPositive = & $specValidator -SpecPath $loopPath -Json | ConvertFrom-Json
    if (-not [bool]$loopPositive.pass) {
        throw ("Loop Contract spec fixture failed: {0}" -f (($loopPositive.findings | ConvertTo-Json -Compress -Depth 5)))
    }

    $chineseSpec = @"
# 工作说明

- **Title**: 中文章节 fixture
- **Slug**: chinese-section-fixture
- **Status**: Active
- **Owner**: release validation
- **Updated**: 2026-05-08

## 1. 摘要
- 验证中文章节别名可以通过轻量 spec validator。

## 2. 当前上下文
- release validation 需要覆盖中文项目记忆场景。

## 3. 目标
- 确认中文章节正例通过。

## 4. 非目标
- 不改写 fixture 文件。

## 5. 约束
- 只使用临时 fixture。

## 6. 假设
- 中文章节标题保持模板约定。

## 7. 风险
- 中文章节别名缺失会影响中文项目 spec。

## 8. 方案
- 执行 validator 并检查 pass 字段。

## 9. 验收与证据
- 中文章节 fixture 通过验证。

## 10. 循环契约
- 不适用。

## 11. 执行契约
- **Autonomy level**: bounded-autonomous
- **Phase list**:
  - P01: 验证中文章节 fixture。
- **Continue rule**: fixture 通过时继续。
- **Stop rule**: 必需章节缺失时停止。
- **State record**: release validation evidence。

## 12. 开放问题
- 无。
"@

    $chinesePath = Join-PathParts $fixtureDir "chinese-section-spec.md"
    Set-Content -LiteralPath $chinesePath -Value $chineseSpec -Encoding UTF8
    $chinesePositive = & $specValidator -SpecPath $chinesePath -RequireExecutionContract -Json | ConvertFrom-Json
    if (-not [bool]$chinesePositive.pass) {
        throw ("Chinese section spec fixture failed: {0}" -f (($chinesePositive.findings | ConvertTo-Json -Compress -Depth 5)))
    }

    $negativeFixtures = @(
        [ordered]@{
            name = "missing-goals"
            expected_finding = "section_goals_missing"
            text = [regex]::Replace($completeSpec, '(?ms)^## 3\. Goals\s*\r?\n.*?(?=^## 4\.)', '')
        },
        [ordered]@{
            name = "missing-non-goals"
            expected_finding = "section_non_goals_missing"
            text = [regex]::Replace($completeSpec, '(?ms)^## 4\. Non-Goals\s*\r?\n.*?(?=^## 5\.)', '')
        },
        [ordered]@{
            name = "missing-acceptance"
            expected_finding = "section_acceptance_missing"
            text = [regex]::Replace($completeSpec, '(?ms)^## 9\. Acceptance / Evidence\s*\r?\n.*?(?=^## 10\.)', '')
        },
        [ordered]@{
            name = "missing-risks"
            expected_finding = "section_risks_missing"
            text = [regex]::Replace($completeSpec, '(?ms)^## 7\. Risks\s*\r?\n.*?(?=^## 8\.)', '')
        },
        [ordered]@{
            name = "missing-stop-rule"
            expected_finding = "execution_stop_rule_missing"
            text = [regex]::Replace($completeSpec, '(?m)^\-\s+\*\*Stop rule\*\*:\s+.*\r?$', '- **Stop rule**:')
        }
    )

    $negativeEvidence = New-Object 'System.Collections.Generic.List[object]'
    foreach ($fixture in $negativeFixtures) {
        $path = Join-PathParts $fixtureDir ("{0}.md" -f $fixture.name)
        Set-Content -LiteralPath $path -Value $fixture.text -Encoding UTF8
        $result = & $specValidator -SpecPath $path -RequireExecutionContract -Json | ConvertFrom-Json
        $findingIds = @($result.findings | ForEach-Object { [string]$_.id })
        if ([bool]$result.pass) {
            throw ("Negative fixture unexpectedly passed: {0}" -f $fixture.name)
        }
        if ([string]$fixture.expected_finding -notin $findingIds) {
            throw ("Negative fixture {0} did not report expected finding {1}. Findings: {2}" -f $fixture.name, $fixture.expected_finding, ($findingIds -join ", "))
        }
        $negativeEvidence.Add([ordered]@{
            name = [string]$fixture.name
            expected_finding = [string]$fixture.expected_finding
            findings = @($findingIds)
        })
    }

    $script:evidence.spec_lite = [ordered]@{
        validator = $specValidator
        positive_fixture = $positivePath
        positive_variants = @(
            [ordered]@{ name = "loop-contract"; path = $loopPath },
            [ordered]@{ name = "chinese-sections"; path = $chinesePath }
        )
        negative_fixtures = @($negativeEvidence.ToArray())
    }
    Add-Check "spec-lite validator" "PASS" "workflow-spec-lite validator accepts a complete spec and rejects missing goals, non-goals, acceptance, risks, and stop rule fixtures." $evidence.spec_lite
}
catch {
    Add-Check "spec-lite validator" "FAIL" $_.Exception.Message
}

try {
    $antiDriftFiles = [ordered]@{
        "skills/workflow-spec-lite/references/spec-template.md" = @("## 3. Goals", "## 4. Non-Goals", "## 9. Acceptance / Evidence", "Scope control:", "scope drift", "skipped acceptance")
        "docs/specs/_templates/spec-lite.md" = @("## 3. Goals", "## 4. Non-Goals", "## 9. Acceptance / Evidence", "Scope control:", "scope drift", "skipped acceptance")
        "knowledge-hub/templates/languages/en/project-root/docs/specs/_templates/spec-lite.md" = @("## 3. Goals", "## 4. Non-Goals", "## 9. Acceptance / Evidence", "Scope control:", "scope drift", "skipped acceptance")
        "skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/en/project-root/docs/specs/_templates/spec-lite.md" = @("## 3. Goals", "## 4. Non-Goals", "## 9. Acceptance / Evidence", "Scope control:", "scope drift", "skipped acceptance")
        "knowledge-hub/templates/languages/en/project-agent/AGENTS.md" = @("Scope discipline:", "unrelated refactors", "acceptance checks are skipped")
        "skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/en/project-agent/AGENTS.md" = @("Scope discipline:", "unrelated refactors", "acceptance checks are skipped")
        "skills/workflow-spec-lite/SKILL.md" = @("scope drift", "unrelated refactors", "skipped acceptance checks", "validate_spec.ps1")
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
        "AGENTS.md" = @('`.agents/context/README.md`', 'Do not preload the full `.agents/context/` tree at startup.')
        "knowledge-hub/templates/languages/en/project-root/AGENTS.md" = @('`.agents/context/README.md`', 'Do not preload the full `.agents/context/` tree at startup.')
        "knowledge-hub/templates/languages/zh-CN/project-root/AGENTS.md" = @('`.agents/context/README.md`', '启动时不要预加载完整 `.agents/context/` 目录。')
        "skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/en/project-root/AGENTS.md" = @('`.agents/context/README.md`', 'Do not preload the full `.agents/context/` tree at startup.')
        "skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/zh-CN/project-root/AGENTS.md" = @('`.agents/context/README.md`', '启动时不要预加载完整 `.agents/context/` 目录。')
    }
    $agentGuidanceFiles = [ordered]@{
        ".agents/AGENTS.md" = @("## Project Commands", '`.agents/commands/README.md`', "## Large Issue Planning", "implementation plan", "PR-Ready And Phase-Close Memory Sync Gate", "opens a pull request", "After a PR has been opened, do not push memory-only commits", '`.agents/context/README.md`')
        "knowledge-hub/templates/languages/en/project-agent/AGENTS.md" = @("## Project Commands", '`.agents/commands/README.md`', "## Large Issue Planning", "implementation plan", "PR-Ready And Phase-Close Memory Sync Gate", "opens a pull request", "After a PR has been opened, do not push memory-only commits", '`.agents/context/README.md`')
        "knowledge-hub/templates/languages/zh-CN/project-agent/AGENTS.md" = @("## 项目命令", '`.agents/commands/README.md`', "## 大 issue 规划", "implementation plan", "PR 就绪与阶段收尾记忆同步门禁", "创建 PR", "PR 创建后，不要仅为了刷新状态或 hosted-check 时间戳而推送 memory-only commit", '`.agents/context/README.md`')
        "skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/en/project-agent/AGENTS.md" = @("## Project Commands", '`.agents/commands/README.md`', "## Large Issue Planning", "implementation plan", "PR-Ready And Phase-Close Memory Sync Gate", "opens a pull request", "After a PR has been opened, do not push memory-only commits", '`.agents/context/README.md`')
        "skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/zh-CN/project-agent/AGENTS.md" = @("## 项目命令", '`.agents/commands/README.md`', "## 大 issue 规划", "implementation plan", "PR 就绪与阶段收尾记忆同步门禁", "创建 PR", "PR 创建后，不要仅为了刷新状态或 hosted-check 时间戳而推送 memory-only commit", '`.agents/context/README.md`')
    }
    $commandGuidanceFiles = [ordered]@{
        ".agents/commands/README.md" = @('`.agents/AGENTS.md`', "reusable high-frequency project workflows", "Do not invent commands", "Expected pass/fail evidence")
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

    $guidanceMissing = New-Object 'System.Collections.Generic.List[string]'
    foreach ($relativePath in $guidanceExpectations.Keys) {
        $text = Get-FileText -RelativePath $relativePath
        foreach ($token in $guidanceExpectations[$relativePath]) {
            if (-not $text.Contains($token)) {
                $guidanceMissing.Add("$relativePath missing token: $token")
            }
        }
    }

    $script:evidence.agent_template_guidance = [ordered]@{
        checked_files = @($guidanceExpectations.Keys)
        missing = @($guidanceMissing.ToArray())
    }

    if ($guidanceMissing.Count -gt 0) {
        Add-Check "agent template startup guidance" "FAIL" "Root, project-agent, or commands templates are missing lean startup, command, PR-ready, or large-issue guidance." $evidence.agent_template_guidance
    }
    else {
        Add-Check "agent template startup guidance" "PASS" "Root, project-agent, and commands templates include lean startup context discovery, Project Commands, PR-ready memory sync, and large-issue planning guidance." $evidence.agent_template_guidance
    }
}
catch {
    Add-Check "agent template startup guidance" "FAIL" $_.Exception.Message
}

try {
    $adoptionFiles = [ordered]@{
        "docs/how-to-adapt.md" = @("Install A Runtime", "Bootstrap A Project", "Use The Workflow Kernel", "Keep Layers Separate", "examples/minimal-project")
        "examples/README.md" = @("Minimal Project", "How To Adapt")
        "examples/minimal-project/README.md" = @("Workflow Kernel", ".agents", "docs/specs")
        "examples/minimal-project/.agents/AGENTS.md" = @("Project Language Policy", "unrelated refactors", "skipped validation")
        "examples/minimal-project/docs/specs/example-work/spec.md" = @("## 3. Goals", "## 4. Non-Goals", "## 9. Acceptance / Evidence", "Stop rule")
        "README.md" = @("How to adapt", "Examples")
    }

    $adoptionMissing = New-Object 'System.Collections.Generic.List[string]'
    foreach ($relativePath in $adoptionFiles.Keys) {
        $text = Get-FileText -RelativePath $relativePath
        foreach ($token in $adoptionFiles[$relativePath]) {
            if ($text -notlike ("*{0}*" -f $token)) {
                $adoptionMissing.Add("$relativePath missing token: $token")
            }
        }
    }

    if ($adoptionMissing.Count -gt 0) {
        Add-Check "adoption surface" "FAIL" "Adoption guide or examples are incomplete." @($adoptionMissing.ToArray())
    }
    else {
        Add-Check "adoption surface" "PASS" "How-to-adapt guide and minimal project example are present and linked from public entrypoints." ([ordered]@{
            checked_files = @($adoptionFiles.Keys)
        })
    }
}
catch {
    Add-Check "adoption surface" "FAIL" $_.Exception.Message
}

try {
    $triageWorkflow = Get-FileText -RelativePath ".github/workflows/issue-triage-label-sync.yml"
    $governance = Get-FileText -RelativePath "docs/agent-governance.md"
    $issueTemplate = Get-FileText -RelativePath ".github/ISSUE_TEMPLATE/agent-candidate.md"
    $triageExpectations = [ordered]@{
        ".github/workflows/issue-triage-label-sync.yml" = @(
            "issues:",
            "issues: write",
            "contents: read",
            "source:agent",
            "Human Triage Decision",
            "triage:accepted",
            "triage:rejected",
            "triage:deferred",
            "triage:needs-human",
            "review:needs-human",
            "core.setFailed"
        )
        "docs/agent-governance.md" = @(
            "Issue Triage Label Sync",
            "mirrors the explicit",
            "does not make triage decisions",
            "source:agent",
            "review:needs-human"
        )
        ".github/ISSUE_TEMPLATE/agent-candidate.md" = @(
            "issue triage label sync workflow",
            "Leave only one checked"
        )
    }

    $triageMissing = New-Object 'System.Collections.Generic.List[string]'
    foreach ($relativePath in $triageExpectations.Keys) {
        $text = switch ($relativePath) {
            ".github/workflows/issue-triage-label-sync.yml" { $triageWorkflow }
            "docs/agent-governance.md" { $governance }
            default { $issueTemplate }
        }
        foreach ($token in $triageExpectations[$relativePath]) {
            if ($text -notlike ("*{0}*" -f $token)) {
                $triageMissing.Add("$relativePath missing token: $token")
            }
        }
    }

    if ($triageMissing.Count -gt 0) {
        Add-Check "issue triage label sync" "FAIL" "Issue triage label sync workflow or docs are incomplete." @($triageMissing.ToArray())
    }
    else {
        Add-Check "issue triage label sync" "PASS" "Agent candidate issue triage decisions are mirrored to labels by a scoped workflow." ([ordered]@{
            workflow = ".github/workflows/issue-triage-label-sync.yml"
            docs = @("docs/agent-governance.md", ".github/ISSUE_TEMPLATE/agent-candidate.md")
        })
    }
}
catch {
    Add-Check "issue triage label sync" "FAIL" $_.Exception.Message
}

try {
    $shellStrategy = Get-FileText -RelativePath "docs/shell-strategy.md"
    $releaseProcess = Get-FileText -RelativePath "docs/release-process.md"
    $workflow = Get-FileText -RelativePath ".github/workflows/release-validation.yml"
    $readme = Get-FileText -RelativePath "README.md"
    $roadmap = Get-FileText -RelativePath "docs/roadmap/evolution-plan.md"
    $shellExpectations = [ordered]@{
        "docs/shell-strategy.md" = @("Windows PowerShell 5.1", "PowerShell 7+", "pwsh -NoProfile -File", "No Bash or Zsh wrappers", "canonical", ".ps1")
        "docs/release-process.md" = @("Shell strategy", "Bash or Zsh wrappers", "canonical", ".ps1")
        "README.md" = @("Shell strategy")
        "docs/roadmap/evolution-plan.md" = @("Shell Direction", "Bash or Zsh wrappers are deferred", "canonical", ".ps1")
    }
    $shellMissing = New-Object 'System.Collections.Generic.List[string]'
    foreach ($relativePath in $shellExpectations.Keys) {
        $text = switch ($relativePath) {
            "docs/shell-strategy.md" { $shellStrategy }
            "docs/release-process.md" { $releaseProcess }
            "README.md" { $readme }
            default { $roadmap }
        }
        foreach ($token in $shellExpectations[$relativePath]) {
            if ($text -notlike ("*{0}*" -f $token)) {
                $shellMissing.Add("$relativePath missing token: $token")
            }
        }
    }

    $workflowTokens = @("windows-latest", "ubuntu-latest", "macos-latest", "shell: pwsh", "shell: powershell")
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
    $missingReleaseTokens = @($releaseTokens | Where-Object { $releaseNotes -notlike "*$_*" })
    if ($missingReleaseTokens.Count -gt 0) {
        Add-Check "v0.2.0 release notes" "FAIL" "Release notes are missing required v0.2.0 summary tokens." @($missingReleaseTokens)
    }
    else {
        Add-Check "v0.2.0 release notes" "PASS" "v0.2.0 release notes summarize closeout features, validation expectation, and public boundary."
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
    $missingReleaseTokens = @($releaseTokens | Where-Object { $releaseNotes -notlike "*$_*" })
    if ($missingReleaseTokens.Count -gt 0) {
        Add-Check "v0.3.0 release notes" "FAIL" "Release notes are missing required v0.3.0 summary tokens." @($missingReleaseTokens)
    }
    else {
        Add-Check "v0.3.0 release notes" "PASS" "v0.3.0 release notes summarize backlog remediation, issue fixes, validation expectation, and public boundary."
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
    $missingReleaseTokens = @($releaseTokens | Where-Object { $releaseNotes -notlike "*$_*" })
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
    $missingReleaseTokens = @($releaseTokens | Where-Object { $releaseNotes -notlike "*$_*" })
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
    $missingReleaseTokens = @($releaseTokens | Where-Object { $releaseNotes -notlike "*$_*" })
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
    $missingReleaseTokens = @($releaseTokens | Where-Object { $releaseNotes -notlike "*$_*" })
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
        "release prep draft",
        "post-convergence stabilization",
        "Issue #53",
        "Issue #54",
        "Issue #55",
        "Issue #56",
        "Issue #57",
        "PASS=46 FAIL=0 WARN=0 DEFERRED=0",
        "Do not tag or publish"
    )
    $missingReleaseTokens = @($releaseTokens | Where-Object { $releaseNotes -notlike "*$_*" })
    if ($missingReleaseTokens.Count -gt 0) {
        Add-Check "v0.4.3 release prep notes" "FAIL" "Release-prep notes are missing required v0.4.3 summary tokens." @($missingReleaseTokens)
    }
    else {
        Add-Check "v0.4.3 release prep notes" "PASS" "v0.4.3 release-prep notes summarize stabilization scope, validation expectation, human decisions, and public boundary."
    }
}
catch {
    Add-Check "v0.4.3 release prep notes" "FAIL" $_.Exception.Message
}

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

    $bootstrapScript = Join-PathParts $recommendedCopyRuntime "skills" "project-bootstrap" "scripts" "bootstrap_project.ps1"
    & $bootstrapScript -ProjectDir $projectFixture -HubDir $hubFixture -SkipMemoryUpgradeAnalysis | Out-Host
    & $bootstrapScript -ProjectDir $batchProjectFixture -HubDir $hubFixture -SkipMemoryUpgradeAnalysis | Out-Host
    $checkHubLockScript = Join-PathParts $recommendedCopyRuntime "skills" "project-bootstrap" "scripts" "check_hub_lock.ps1"
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
    if (-not (Test-ExactArray -Actual @($secondManifest.skills) -Expected $profileExpectations.recommended)) {
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
    if ([string]::IsNullOrWhiteSpace($recommendedCopyRuntime)) {
        throw "Recommended copy runtime was not created."
    }

    $memoryUpgradeProject = Join-PathParts $scratchRootFull "memory-upgrade-flow-project"
    New-Item -ItemType Directory -Force -Path $memoryUpgradeProject | Out-Null
    Assert-PathInsideRoot -Path $memoryUpgradeProject -Root $scratchRootFull

    $hubDir = Join-PathParts $recommendedCopyRuntime "knowledge-hub"
    $bootstrapScript = Join-PathParts $recommendedCopyRuntime "skills" "project-bootstrap" "scripts" "bootstrap_project.ps1"
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

    $memoryUpgradeScript = Join-PathParts $recommendedCopyRuntime "skills" "project-bootstrap" "scripts" "memory_upgrade.ps1"
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
    if ([string]::IsNullOrWhiteSpace($recommendedCopyRuntime)) {
        throw "Recommended copy runtime was not created."
    }

    $hubDir = Join-PathParts $recommendedCopyRuntime "knowledge-hub"
    $bootstrapScript = Join-PathParts $recommendedCopyRuntime "skills" "project-bootstrap" "scripts" "bootstrap_project.ps1"
    $languageMigrationScript = Join-PathParts $recommendedCopyRuntime "skills" "project-bootstrap" "scripts" "language_migration.ps1"
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

    Add-Check "conservative language migration" "PASS" "Conservative en/zh-CN migration covers analyze, proposal, backup, apply, validate, narrative proposal routing, mixed memory, and project-specific preservation." $evidence.language_migration
}
catch {
    Add-Check "conservative language migration" "FAIL" $_.Exception.Message
}

try {
    if ([string]::IsNullOrWhiteSpace($recommendedCopyRuntime)) {
        throw "Recommended copy runtime was not created."
    }

    $preserveProject = Join-PathParts $scratchRootFull "bootstrap-memory-preservation-project"
    New-Item -ItemType Directory -Force -Path $preserveProject | Out-Null
    Assert-PathInsideRoot -Path $preserveProject -Root $scratchRootFull

    $hubDir = Join-PathParts $recommendedCopyRuntime "knowledge-hub"
    $bootstrapScript = Join-PathParts $recommendedCopyRuntime "skills" "project-bootstrap" "scripts" "bootstrap_project.ps1"
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

try {
    $catalogPath = "knowledge-hub/knowledge-catalog.md"
    $catalogText = Get-FileText -RelativePath $catalogPath
    $catalogRequiredTokens = @(
        "knowledge/experience/windows-powershell-command-chaining.md",
        "knowledge/patterns/context-gate-spec-validation-loop.md",
        "knowledge/standards/public-knowledge-boundary.md",
        "knowledge/standards/bilingual-public-private-routing.md",
        "knowledge/domain-packs/embedded-core/catalog.md"
    )
    $missingCatalogTokens = @($catalogRequiredTokens | Where-Object { $catalogText -notlike "*$_*" })

    $metadataFiles = @(
        "knowledge-hub/knowledge/experience/windows-powershell-command-chaining.md",
        "knowledge-hub/knowledge/patterns/context-gate-spec-validation-loop.md",
        "knowledge-hub/knowledge/standards/public-knowledge-boundary.md",
        "knowledge-hub/knowledge/standards/bilingual-public-private-routing.md",
        "knowledge-hub/knowledge/domain-packs/embedded-core/catalog.md",
        "knowledge-hub/knowledge/domain-packs/embedded-core/validation-checklist.md"
    )
    $metadataErrors = New-Object 'System.Collections.Generic.List[string]'
    foreach ($metadataFile in $metadataFiles) {
        $metadataText = Get-FileText -RelativePath $metadataFile
        foreach ($field in @("Maturity:", "Scope:", "Source:", "Last reviewed:")) {
            if ($metadataText -notmatch ("(?m)^{0}\s*.+" -f [regex]::Escape($field))) {
                $metadataErrors.Add("$metadataFile missing $field")
            }
        }
    }

    if ($missingCatalogTokens.Count -gt 0 -or $metadataErrors.Count -gt 0) {
        Add-Check "knowledge hub catalog" "FAIL" "Knowledge catalog or entry metadata is incomplete." ([ordered]@{
            missing_catalog_entries = @($missingCatalogTokens)
            metadata_errors = @($metadataErrors.ToArray())
        })
    }
    else {
        Add-Check "knowledge hub catalog" "PASS" "Catalog links experience, patterns, and standards entries with required metadata." ([ordered]@{
            catalog = $catalogPath
            entries = @($catalogRequiredTokens)
            metadata_files = @($metadataFiles)
        })
    }
}
catch {
    Add-Check "knowledge hub catalog" "FAIL" $_.Exception.Message
}

try {
    $indexPath = Join-PathParts $repoRoot "knowledge-hub" "knowledge" "experience" "index.json"
    $index = Get-Content -LiteralPath $indexPath -Raw | ConvertFrom-Json
    $searchScript = Join-PathParts $repoRoot "knowledge-hub" "scripts" "search_experience.ps1"
    $searchText = & $searchScript -HubDir (Join-PathParts $repoRoot "knowledge-hub") -Query "PowerShell command chaining" -Json
    $search = $searchText | ConvertFrom-Json
    $resultCount = @($search.results).Count
    if ($resultCount -lt 1) {
        throw "Experience search returned no matching entries."
    }
    $script:evidence.knowledge_hub = [ordered]@{
        index_path = $indexPath
        index_entries = @($index.entries).Count
        search_query = "PowerShell command chaining"
        search_results = $resultCount
        top_result = [string]$search.results[0].title
    }
    Add-Check "knowledge hub experience search" "PASS" "Experience index parsed and search returned public workflow experience." $evidence.knowledge_hub
}
catch {
    Add-Check "knowledge hub experience search" "FAIL" $_.Exception.Message
}

try {
    $tempHub = Join-PathParts $scratchRootFull "experience-promote-hub"
    $tempProject = Join-PathParts $scratchRootFull "experience-promote-project"
    Assert-PathInsideRoot -Path $tempHub -Root $scratchRootFull
    Assert-PathInsideRoot -Path $tempProject -Root $scratchRootFull
    Copy-Item -LiteralPath (Join-PathParts $repoRoot "knowledge-hub") -Destination $tempHub -Recurse -Force
    New-Item -ItemType Directory -Force -Path (Join-PathParts $tempProject ".agents" "context" "experience") | Out-Null

    $candidatePath = Join-PathParts $tempProject ".agents" "context" "experience" "validation-promote-closure.md"
    $candidateText = @"
# Validation Promote Closure

## Summary
Temporary cross-project validation lesson used only by release validation.

## Keywords
validation promote closure, release gate, temporary hub

Scope: Cross-project reusable
Global candidate: Yes

## Prevention Rule
Validate experience promotion with a temporary hub so the public source tree is not mutated during release checks.
"@
    Set-Content -LiteralPath $candidatePath -Value $candidateText -Encoding UTF8

    $promoteScript = Join-PathParts $repoRoot "knowledge-hub" "scripts" "promote_experience.ps1"
    $rebuildScript = Join-PathParts $repoRoot "knowledge-hub" "scripts" "rebuild_experience_index.ps1"
    $searchScript = Join-PathParts $repoRoot "knowledge-hub" "scripts" "search_experience.ps1"
    $promoteOutput = @(& $promoteScript -ProjectDir $tempProject -HubDir $tempHub -ProjectTag "validation")
    & $rebuildScript -HubDir $tempHub | Out-Host
    $registryPath = Join-PathParts $tempHub "knowledge" "experience" "index.json"
    $registryHashAfterRebuild = (Get-FileHash -LiteralPath $registryPath -Algorithm SHA256).Hash
    & $rebuildScript -HubDir $tempHub | Out-Host
    $registryHashAfterNoop = (Get-FileHash -LiteralPath $registryPath -Algorithm SHA256).Hash
    if ($registryHashAfterNoop -ne $registryHashAfterRebuild) {
        throw "No-op experience index rebuild changed the registry file."
    }

    $searchText = & $searchScript -HubDir $tempHub -Query "validation promote closure" -Json
    $search = $searchText | ConvertFrom-Json
    $resultCount = @($search.results).Count
    if ($resultCount -lt 1) {
        throw "Promoted experience could not be found by search."
    }

    $topResult = $search.results[0]
    if ([string]$topResult.title -ne "Validation Promote Closure") {
        throw ("Unexpected promoted experience search result: {0}" -f [string]$topResult.title)
    }

    Add-Check "experience promote closure" "PASS" "Temporary experience promotion, index rebuild, and search passed without mutating public source." ([ordered]@{
        temp_hub = $tempHub
        temp_project = $tempProject
        promote_output = @($promoteOutput)
        noop_rebuild_preserved_hash = $true
        search_results = $resultCount
        top_result = [string]$topResult.title
    })
}
catch {
    Add-Check "experience promote closure" "FAIL" $_.Exception.Message
}

try {
    $helperPairs = @(
        @("knowledge-hub/scripts/rebuild_experience_index.ps1", "skills/project-bootstrap/scripts/rebuild_experience_index.ps1"),
        @("knowledge-hub/scripts/promote_experience.ps1", "skills/project-bootstrap/scripts/promote_experience.ps1")
    )
    $helperErrors = New-Object 'System.Collections.Generic.List[string]'
    foreach ($pair in $helperPairs) {
        $left = Join-PathParts $repoRoot $pair[0]
        $right = Join-PathParts $repoRoot $pair[1]
        $leftHash = (Get-FileHash -LiteralPath $left -Algorithm SHA256).Hash
        $rightHash = (Get-FileHash -LiteralPath $right -Algorithm SHA256).Hash
        $script:evidence.duplicate_helpers += [ordered]@{
            preferred = $pair[0]
            compatibility_copy = $pair[1]
            hash_sha256 = $leftHash
            identical = ($leftHash -eq $rightHash)
        }
        if ($leftHash -ne $rightHash) {
            $helperErrors.Add(("{0} differs from {1}" -f $pair[0], $pair[1]))
        }
    }
    if ($helperErrors.Count -gt 0) {
        Add-Check "duplicate helper hash" "FAIL" "Compatibility helper hashes differ." @($helperErrors.ToArray())
    }
    else {
        Add-Check "duplicate helper hash" "PASS" "Compatibility helper hashes match preferred knowledge hub scripts." $evidence.duplicate_helpers
    }
}
catch {
    Add-Check "duplicate helper hash" "FAIL" $_.Exception.Message
}

try {
    $gitDiffCheck = & git -c core.autocrlf=false -c core.safecrlf=false -C $repoRoot diff --check 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ($gitDiffCheck -join "`n")
    }
    Add-Check "git diff check" "PASS" "git diff --check found no whitespace errors."
}
catch {
    Add-Check "git diff check" "FAIL" $_.Exception.Message
}

try {
    $encodingErrors = New-Object 'System.Collections.Generic.List[string]'
    $psFiles = @(Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Filter "*.ps1" | Where-Object { (ConvertTo-DisplayPath -Path $_.FullName -Root $repoRoot) -notmatch '(^|/)\.git(/|$)' })
    foreach ($file in $psFiles) {
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        if ($bytes.Length -eq 0) {
            continue
        }

        $hasUtf8Bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        $hasNonAscii = $false
        foreach ($byte in $bytes) {
            if ($byte -gt 0x7F) {
                $hasNonAscii = $true
                break
            }
        }

        if ($hasNonAscii -and -not $hasUtf8Bom) {
            $encodingErrors.Add(("{0}: contains non-ASCII bytes but is not UTF-8 with BOM" -f (ConvertTo-DisplayPath -Path $file.FullName -Root $repoRoot)))
        }
    }

    if ($encodingErrors.Count -gt 0) {
        Add-Check "Windows PowerShell script encoding" "FAIL" "Non-ASCII PowerShell scripts must be UTF-8 with BOM so Windows PowerShell 5.1 parses them correctly." @($encodingErrors.ToArray())
    }
    else {
        Add-Check "Windows PowerShell script encoding" "PASS" "Non-ASCII PowerShell scripts are UTF-8 with BOM for Windows PowerShell 5.1 compatibility."
    }
}
catch {
    Add-Check "Windows PowerShell script encoding" "FAIL" $_.Exception.Message
}

try {
    $parseErrors = New-Object 'System.Collections.Generic.List[string]'
    $psFiles = @(Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Filter "*.ps1" | Where-Object { (ConvertTo-DisplayPath -Path $_.FullName -Root $repoRoot) -notmatch '(^|/)\.git(/|$)' })
    foreach ($file in $psFiles) {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
        if ($errors.Count -gt 0) {
            $parseErrors.Add(("{0}: {1}" -f (ConvertTo-DisplayPath -Path $file.FullName -Root $repoRoot), ($errors | ForEach-Object { $_.Message }) -join "; "))
        }
    }
    if ($parseErrors.Count -gt 0) {
        Add-Check "PowerShell parse" "FAIL" "One or more PowerShell scripts failed parser checks." @($parseErrors.ToArray())
    }
    else {
        Add-Check "PowerShell parse" "PASS" ("Parsed {0} PowerShell scripts." -f $psFiles.Count)
    }
}
catch {
    Add-Check "PowerShell parse" "FAIL" $_.Exception.Message
}

try {
    $jsonErrors = New-Object 'System.Collections.Generic.List[string]'
    $jsonFiles = @(Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Filter "*.json" | Where-Object { (ConvertTo-DisplayPath -Path $_.FullName -Root $repoRoot) -notmatch '(^|/)\.git(/|$)' })
    foreach ($file in $jsonFiles) {
        try {
            Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json | Out-Null
        }
        catch {
            $jsonErrors.Add(("{0}: {1}" -f (ConvertTo-DisplayPath -Path $file.FullName -Root $repoRoot), $_.Exception.Message))
        }
    }
    if ($jsonErrors.Count -gt 0) {
        Add-Check "JSON parse" "FAIL" "One or more JSON files failed parse checks." @($jsonErrors.ToArray())
    }
    else {
        Add-Check "JSON parse" "PASS" ("Parsed {0} JSON files." -f $jsonFiles.Count)
    }
}
catch {
    Add-Check "JSON parse" "FAIL" $_.Exception.Message
}

try {
    $gitFiles = @(Get-GitFiles)
    $highRiskPatterns = @(
        [ordered]@{ name = "windows_user_path"; pattern = '(?i)\b[A-Z]:[\\/]+Users[\\/]+[^\\/ ]+' },
        [ordered]@{ name = "windows_projects_path"; pattern = '(?i)\b[A-Z]:[\\/]+Projects[\\/]+[^\\/ ]+' },
        [ordered]@{ name = "private_key_marker"; pattern = '-----BEGIN [A-Z ]*PRIVATE KEY-----' },
        [ordered]@{ name = "github_token"; pattern = '(?i)\b(ghp|github_pat)_[A-Za-z0-9_]{20,}\b' },
        [ordered]@{ name = "openai_key"; pattern = '(?i)\bsk-[A-Za-z0-9]{20,}\b' },
        [ordered]@{ name = "aws_access_key"; pattern = '\bAKIA[0-9A-Z]{16}\b' },
        [ordered]@{ name = "slack_token"; pattern = '(?i)\bxox[abprs]-[A-Za-z0-9-]{20,}\b' }
    )

    $highRiskMatches = New-Object 'System.Collections.Generic.List[object]'
    foreach ($file in $gitFiles) {
        foreach ($rule in $highRiskPatterns) {
            foreach ($match in @(Get-LineMatches -RelativePath $file -Pattern $rule.pattern)) {
                $highRiskMatches.Add([object][ordered]@{
                    rule = $rule.name
                    path = $match.path
                    line = $match.line
                    text = $match.text
                })
            }
        }
    }

    $secretPattern = '(?i)\b(secret|password|api[_ -]?key|credential|credentials|cookie|cookies|token|tokens|private key|private keys)\b'
    $allowedSecretPaths = @(
        "AGENTS.md",
        ".agents/AGENTS.md",
        "CONTRIBUTING.md",
        "SECURITY.md",
        "docs/agent-governance.md",
        "docs/release-readiness.md",
        "docs/release-process.md",
        "docs/roadmap/evolution-plan.md",
        "knowledge-hub/templates/languages/en/project-root/AGENTS.md",
        "knowledge-hub/templates/languages/en/project-agent/AGENTS.md",
        "skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/en/project-root/AGENTS.md",
        "skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/en/project-agent/AGENTS.md",
        "skills/project-bootstrap/scripts/set_project_language.ps1",
        "skills/project-context-gate/SKILL.md",
        "scripts/validate-release.ps1"
    )
    $keywordMatches = New-Object 'System.Collections.Generic.List[object]'
    $unexpectedKeywordMatches = New-Object 'System.Collections.Generic.List[object]'
    foreach ($file in $gitFiles) {
        foreach ($match in @(Get-LineMatches -RelativePath $file -Pattern $secretPattern)) {
            $keywordMatches.Add([object]$match)
            if ($file -notin $allowedSecretPaths) {
                $unexpectedKeywordMatches.Add([object]$match)
            }
        }
    }

    $script:evidence.audit = [ordered]@{
        public_files_scanned = $gitFiles.Count
        high_risk_matches = @($highRiskMatches.ToArray())
        secret_keyword_matches = @($keywordMatches.ToArray())
        unexpected_secret_keyword_matches = @($unexpectedKeywordMatches.ToArray())
    }

    if ($highRiskMatches.Count -gt 0) {
        Add-Check "high-risk sensitive scan" "FAIL" "High-risk sensitive patterns were found." @($highRiskMatches.ToArray())
    }
    else {
        Add-Check "high-risk sensitive scan" "PASS" ("Scanned {0} tracked and untracked public files; no high-risk matches." -f $gitFiles.Count)
    }

    if ($unexpectedKeywordMatches.Count -gt 0) {
        Add-Check "secret keyword scan" "FAIL" "Secret-related keywords appeared outside expected public safety/documentation/audit-tooling files." @($unexpectedKeywordMatches.ToArray())
    }
    else {
        Add-Check "secret keyword scan" "PASS" ("Secret-related keyword matches were limited to expected public safety/documentation/audit-tooling files ({0} matches)." -f $keywordMatches.Count)
    }
}
catch {
    Add-Check "sensitive audit" "FAIL" $_.Exception.Message
}

try {
    $agentGuide = Get-FileText -RelativePath ".agents/AGENTS.md"
    $languagePolicyPresent = $agentGuide -match '(?m)^## Project Language Policy\s*$'
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

        if ([string]::IsNullOrWhiteSpace($recommendedCopyRuntime)) {
            throw "Recommended copy runtime was not created."
        }

        $projectName = "language-auto-write-{0}" -f ($Language -replace '[^A-Za-z0-9-]', '-')
        $languageProjectDir = Join-PathParts $scratchRootFull $projectName
        New-Item -ItemType Directory -Force -Path $languageProjectDir | Out-Null
        Assert-PathInsideRoot -Path $languageProjectDir -Root $scratchRootFull

        $hubDir = Join-PathParts $recommendedCopyRuntime "knowledge-hub"
        $bootstrapScript = Join-PathParts $recommendedCopyRuntime "skills" "project-bootstrap" "scripts" "bootstrap_project.ps1"
        & $bootstrapScript -ProjectDir $languageProjectDir -HubDir $hubDir -ProjectLanguage $Language -SkipMemoryUpgradeAnalysis | Out-Host

        $requiredMarkers = [ordered]@{
            "AGENTS.md" = $ExpectedMarker
            ".agents/AGENTS.md" = $ExpectedMarker
            ".agents/process.txt" = $ExpectedMarker
            ".agents/plan.md" = $ExpectedMarker
            ".agents/notes.md" = $ExpectedMarker
            ".agents/context/README.md" = $ExpectedContextToken
            ".agents/context/tech/README.md" = $ExpectedMarker
            ".agents/context/business/README.md" = $ExpectedMarker
            ".agents/context/experience/README.md" = $ExpectedMarker
            ".agents/context/experience/cases/README.md" = $ExpectedMarker
            ".agents/context/experience/cases/case_template.md" = $ExpectedMarker
            ".agents/commands/README.md" = $ExpectedCommandToken
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
            "project-root/docs/specs/README.md",
            "project-root/docs/specs/_templates/spec-lite.md",
            "project-root/docs/specs/_templates/tasks-lite.md",
            "project-agent/AGENTS.md",
            "project-agent/process.txt",
            "project-agent/plan.md",
            "project-agent/notes.md",
            "project-agent/commands/README.md",
            "project-agent/context/README.md",
            "project-agent/context/tech/README.md",
            "project-agent/context/business/README.md",
            "project-agent/context/experience/README.md",
            "project-agent/context/experience/cases/README.md",
            "project-agent/context/experience/cases/case_template.md"
        )

        $missing = New-Object 'System.Collections.Generic.List[string]'
        $mismatched = New-Object 'System.Collections.Generic.List[string]'
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
        foreach ($legacyRoot in $legacyRoots) {
            if (Test-Path -LiteralPath $legacyRoot) {
                $missing.Add("legacy template directory should not exist: $legacyRoot")
            }
        }

        if ($missing.Count -gt 0 -or $mismatched.Count -gt 0) {
            throw ("Project language file templates are missing, mismatched, or legacy paths remain. Missing: {0}; mismatched: {1}" -f ($missing.ToArray() -join "; "), ($mismatched.ToArray() -join "; "))
        }

        return [ordered]@{
            authority_root = $authorityRoot
            bundled_snapshot_root = $snapshotRoot
            legacy_roots_absent = -not [bool](@($legacyRoots | Where-Object { Test-Path -LiteralPath $_ }).Count)
            languages = @("en", "zh-CN")
            checked_files_per_language = @($requiredRelativePaths)
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
        $fileTemplateEvidence += Test-ProjectMemoryTemplateFiles -RuntimeDir $recommendedCopyRuntime
        $autoWriteEvidence += Test-PlainBootstrapDefaultsToEnglish -RuntimeDir $recommendedCopyRuntime
        $autoWriteEvidence += Test-ProjectLanguageBootstrap -Language "en" -ExpectedMarker "Project memory language: English." -ExpectedContextToken "Use this folder as the long-term memory base." -ExpectedCommandToken "Use this folder for reusable high-frequency project workflows." -ExpectedSpecToken "Use this directory for long-lived work packages"
        $autoWriteEvidence += Test-ProjectLanguageBootstrap -Language "zh-CN" -ExpectedMarker "项目记忆语言：简体中文。" -ExpectedContextToken "此目录是长期项目记忆入口。" -ExpectedCommandToken "此目录用于沉淀高频、可复用的项目工作流命令。" -ExpectedSpecToken "此目录用于保存需要跨会话延续的长期工作包。"
        $fallbackEvidence += Test-ProjectLanguageTemplateFallback -RuntimeDir $recommendedCopyRuntime
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
        Add-Check "language policy templates" "PASS" "Project Language Policy is present in repo and bootstrap output; bootstrap hot memory files are present." $evidence.language_policy
        Add-Check "file-based memory template sources" "PASS" "English and Simplified Chinese project memory templates exist as files for root, hot memory, context, commands, and spec scaffolds." @($fileTemplateEvidence)
        Add-Check "first-session language auto-write behavior" "PASS" "Bootstrap can write English and Simplified Chinese project memory scaffolds when the agent/workflow supplies the first-session language." @($autoWriteEvidence)
        Add-Check "missing language template fallback" "PASS" "A missing Simplified Chinese template file falls back to the English template with fallback metadata." @($fallbackEvidence)
    }
    else {
        Add-Check "language policy templates" "FAIL" "Language policy or bootstrap hot memory check failed." $evidence.language_policy
    }
}
catch {
    Add-Check "language policy templates" "FAIL" $_.Exception.Message
}

try {
    $routingStandard = Get-FileText -RelativePath "knowledge-hub/knowledge/standards/bilingual-public-private-routing.md"
    $assetRoutingStandard = Get-FileText -RelativePath "skills/project-bootstrap/assets/knowledge-hub-template/knowledge/standards/bilingual-public-private-routing.md"
    $catalogText = Get-FileText -RelativePath "knowledge-hub/knowledge-catalog.md"
    $assetCatalogText = Get-FileText -RelativePath "skills/project-bootstrap/assets/knowledge-hub-template/knowledge-catalog.md"
    $languagePolicy = Get-FileText -RelativePath "docs/language-policy.md"
    $readiness = Get-FileText -RelativePath "docs/release-readiness.md"
    $releaseProcess = Get-FileText -RelativePath "docs/release-process.md"

    $routingExpectations = [ordered]@{
        "knowledge-hub/knowledge/standards/bilingual-public-private-routing.md" = @("Maturity: verified", "Scope: cross-project", "User-facing conversation", "Public Boundary")
        "skills/project-bootstrap/assets/knowledge-hub-template/knowledge/standards/bilingual-public-private-routing.md" = @("Maturity: verified", "Scope: cross-project", "User-facing conversation", "Public Boundary")
        "knowledge-hub/knowledge-catalog.md" = @("Bilingual Public/Private Routing", "language routing")
        "skills/project-bootstrap/assets/knowledge-hub-template/knowledge-catalog.md" = @("Bilingual Public/Private Routing")
        "docs/language-policy.md" = @("Conversation And Artifact Routing", "Bilingual Public/Private Routing", "Public templates remain English-first")
        "docs/release-readiness.md" = @("Bilingual Public/Private Routing", "localized context discovery headings")
        "docs/release-process.md" = @("localized context discovery headings", "bilingual public/private routing")
    }

    $routingMissing = New-Object 'System.Collections.Generic.List[string]'
    foreach ($relativePath in $routingExpectations.Keys) {
        $text = switch ($relativePath) {
            "knowledge-hub/knowledge/standards/bilingual-public-private-routing.md" { $routingStandard }
            "skills/project-bootstrap/assets/knowledge-hub-template/knowledge/standards/bilingual-public-private-routing.md" { $assetRoutingStandard }
            "knowledge-hub/knowledge-catalog.md" { $catalogText }
            "skills/project-bootstrap/assets/knowledge-hub-template/knowledge-catalog.md" { $assetCatalogText }
            "docs/language-policy.md" { $languagePolicy }
            "docs/release-readiness.md" { $readiness }
            default { $releaseProcess }
        }
        foreach ($token in $routingExpectations[$relativePath]) {
            if ($text -notlike ("*{0}*" -f $token)) {
                $routingMissing.Add("$relativePath missing token: $token")
            }
        }
    }

    $script:evidence.routing = [ordered]@{
        checked_files = @($routingExpectations.Keys)
        missing = @($routingMissing.ToArray())
    }

    if ($routingMissing.Count -gt 0) {
        Add-Check "bilingual public/private routing" "FAIL" "Bilingual routing guidance is missing from public docs or bundled knowledge assets." $evidence.routing
    }
    else {
        Add-Check "bilingual public/private routing" "PASS" "Public/private language routing is documented in public-safe docs and bundled knowledge assets." $evidence.routing
    }
}
catch {
    Add-Check "bilingual public/private routing" "FAIL" $_.Exception.Message
}

}
catch {
    Add-Check "validator execution" "FAIL" ("Unhandled validator error: {0}" -f $_.Exception.Message)
}

$result = [ordered]@{
    schema_version = 1
    validated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    repo_root = $repoRoot
    scratch_root = $scratchRootFull
    live_runtime_candidates = @($liveRuntimeCandidates)
    skip_link_mode = [bool]$SkipLinkMode.IsPresent
    checks = @($checks.ToArray())
    evidence = $evidence
    summary = [ordered]@{
        pass = @($checks | Where-Object { $_.status -eq "PASS" }).Count
        fail = @($checks | Where-Object { $_.status -eq "FAIL" }).Count
        warn = @($checks | Where-Object { $_.status -eq "WARN" }).Count
        deferred = @($checks | Where-Object { $_.status -eq "DEFERRED" }).Count
    }
}

$resultPath = Join-PathParts $scratchRootFull "validation-result.json"
$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8

if ($Json.IsPresent) {
    $result | ConvertTo-Json -Depth 12
}
else {
    Write-Output ""
    Write-Output "Release validation summary"
    Write-Output ("Scratch root: {0}" -f $scratchRootFull)
    Write-Output ("Result: {0}" -f $resultPath)
    Write-Output ("PASS={0} FAIL={1} WARN={2} DEFERRED={3}" -f $result.summary.pass, $result.summary.fail, $result.summary.warn, $result.summary.deferred)
    foreach ($check in $result.checks) {
        Write-Output ("[{0}] {1} - {2}" -f $check.status, $check.name, $check.detail)
    }
}

if ($result.summary.fail -gt 0) {
    exit 1
}

exit 0
