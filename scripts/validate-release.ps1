[CmdletBinding()]
param(
    [string]$ScratchRoot = "",
    [switch]$SkipLinkMode,
    [switch]$Json
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
$repoRoot = Split-Path -Parent $scriptDir
$runStamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss")

if ([string]::IsNullOrWhiteSpace($ScratchRoot)) {
    $ScratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-ecosystem-release-validation-{0}" -f $runStamp)
}

$scratchRootFull = [System.IO.Path]::GetFullPath($ScratchRoot)
$liveRuntimeCandidates = @()
if (-not [string]::IsNullOrWhiteSpace($HOME)) {
    $liveRuntimeCandidates += [System.IO.Path]::GetFullPath((Join-Path $HOME ".agents")).TrimEnd('\', '/')
}
if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
    $liveRuntimeCandidates += [System.IO.Path]::GetFullPath((Join-Path $env:USERPROFILE ".agents")).TrimEnd('\', '/')
}
$liveRuntimeCandidates = @($liveRuntimeCandidates | Sort-Object -Unique)

function Assert-PathInsideRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    if (-not ($fullPath.Equals($fullRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
            $fullPath.StartsWith($fullRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase))) {
        throw "Path is outside expected root: $fullPath"
    }
}

function Assert-NotLiveRuntime {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    foreach ($candidate in $script:liveRuntimeCandidates) {
        if ($fullPath.Equals($candidate, [System.StringComparison]::OrdinalIgnoreCase) -or
            $fullPath.StartsWith($candidate + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to use live runtime path: $fullPath"
        }
    }
}

function Join-PathParts {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(ValueFromRemainingArguments = $true)][string[]]$Children
    )

    $path = $Root
    foreach ($child in $Children) {
        if ([string]::IsNullOrWhiteSpace($child)) {
            continue
        }
        foreach ($segment in @($child -split '[\\/]+')) {
            if (-not [string]::IsNullOrWhiteSpace($segment)) {
                $path = Join-Path $path $segment
            }
        }
    }
    return $path
}

function ConvertTo-DisplayPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    if ($fullPath.StartsWith($fullRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $fullPath.Substring($fullRoot.Length).TrimStart([char[]]"\/") -replace "\\", "/"
    }
    return $fullPath -replace "\\", "/"
}

Assert-NotLiveRuntime -Path $scratchRootFull
New-Item -ItemType Directory -Force -Path $scratchRootFull | Out-Null

$checks = New-Object 'System.Collections.Generic.List[object]'
$evidence = [ordered]@{
    profile_matrix = @()
    runtime_smoke = [ordered]@{}
    audit = [ordered]@{}
    knowledge_hub = [ordered]@{}
    duplicate_helpers = @()
    language_policy = [ordered]@{}
}

function Add-Check {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [ValidateSet("PASS", "FAIL", "WARN", "DEFERRED")]
        [string]$Status,
        [string]$Detail = "",
        [object]$Data = $null
    )

    $script:checks.Add([ordered]@{
        name = $Name
        status = $Status
        detail = $Detail
        data = $Data
    })
}

function Test-RequiredPath {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [switch]$Directory
    )

    $path = Join-PathParts $repoRoot $RelativePath
    if ($Directory.IsPresent) {
        return [System.IO.Directory]::Exists($path)
    }
    return [System.IO.File]::Exists($path)
}

function Get-GitFiles {
    $output = & git -C $repoRoot ls-files --cached --others --exclude-standard
    if ($LASTEXITCODE -ne 0) {
        throw "git ls-files failed."
    }
    return @($output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-FileText {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $path = Join-PathParts $repoRoot $RelativePath
    return [System.IO.File]::ReadAllText($path)
}

function Get-LineMatches {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Pattern
    )

    $path = Join-PathParts $repoRoot $RelativePath
    if (-not [System.IO.File]::Exists($path)) {
        return @()
    }

    $lines = [System.IO.File]::ReadAllLines($path)
    $lineMatches = New-Object 'System.Collections.Generic.List[object]'
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $Pattern) {
            $lineMatches.Add([object][ordered]@{
                path = $RelativePath
                line = $i + 1
                text = $lines[$i].Trim()
            })
        }
    }
    return @($lineMatches.ToArray())
}

function Test-ExactArray {
    param(
        [object[]]$Actual,
        [object[]]$Expected
    )

    $actualValues = @($Actual | ForEach-Object { [string]$_ } | Sort-Object)
    $expectedValues = @($Expected | ForEach-Object { [string]$_ } | Sort-Object)
    if ($actualValues.Count -ne $expectedValues.Count) {
        return $false
    }
    for ($i = 0; $i -lt $actualValues.Count; $i++) {
        if ($actualValues[$i] -ne $expectedValues[$i]) {
            return $false
        }
    }
    return $true
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

$requiredFiles = @(
    "README.md",
    "README.zh-CN.md",
    "LICENSE",
    "CONTRIBUTING.md",
    "SECURITY.md",
    "scripts/install.ps1",
    "scripts/validate-release.ps1",
    "docs/architecture.md",
    "docs/language-policy.md",
    "docs/release-process.md",
    "docs/release-readiness.md",
    "knowledge-hub/knowledge-catalog.md"
)
$missingFiles = @($requiredFiles | Where-Object { -not (Test-RequiredPath -RelativePath $_) })

$requiredDirs = @(
    "skills/project-bootstrap",
    "skills/project-context-gate",
    "skills/workflow-spec-lite",
    "skills/memory-governance",
    "knowledge-hub/templates",
    "knowledge-hub/scripts",
    "knowledge-hub/knowledge/experience",
    "knowledge-hub/knowledge/patterns",
    "knowledge-hub/knowledge/standards"
)
$missingDirs = @($requiredDirs | Where-Object { -not (Test-RequiredPath -RelativePath $_ -Directory) })

if ($missingFiles.Count -eq 0 -and $missingDirs.Count -eq 0) {
    Add-Check "public structure" "PASS" "Required release files, skills, docs, and knowledge hub paths exist."
}
else {
    Add-Check "public structure" "FAIL" "Required public paths are missing." ([ordered]@{ files = $missingFiles; directories = $missingDirs })
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
    $hubFixture = Join-PathParts $scratchRootFull "hub-lock-fixture-hub"
    $projectFixture = Join-PathParts $scratchRootFull "hub-lock-fixture-project"
    Assert-PathInsideRoot -Path $hubFixture -Root $scratchRootFull
    Assert-PathInsideRoot -Path $projectFixture -Root $scratchRootFull
    Copy-Item -LiteralPath (Join-PathParts $repoRoot "knowledge-hub") -Destination $hubFixture -Recurse -Force
    New-Item -ItemType Directory -Force -Path $projectFixture | Out-Null

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
    $checkHubLockScript = Join-PathParts $recommendedCopyRuntime "skills" "project-bootstrap" "scripts" "check_hub_lock.ps1"
    $hubLockOutput = @(& $checkHubLockScript -ProjectDir $projectFixture -HubDir $hubFixture)
    $hubLockStatusLine = @($hubLockOutput | Where-Object { $_ -match '^Status:\s+' } | Select-Object -Last 1)
    if ($hubLockStatusLine.Count -lt 1 -or $hubLockStatusLine[0] -notmatch 'Status:\s+in_sync') {
        throw ("hub.lock drift check did not report in_sync. Output: {0}" -f ($hubLockOutput -join " | "))
    }

    Add-Check "hub.lock drift check" "PASS" "Git-backed temporary hub lock check reported in_sync." ([ordered]@{
        temp_hub = $hubFixture
        temp_project = $projectFixture
        status = "in_sync"
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
    $catalogPath = "knowledge-hub/knowledge-catalog.md"
    $catalogText = Get-FileText -RelativePath $catalogPath
    $catalogRequiredTokens = @(
        "knowledge/experience/windows-powershell-command-chaining.md",
        "knowledge/patterns/context-gate-spec-validation-loop.md",
        "knowledge/standards/public-knowledge-boundary.md"
    )
    $missingCatalogTokens = @($catalogRequiredTokens | Where-Object { $catalogText -notlike "*$_*" })

    $metadataFiles = @(
        "knowledge-hub/knowledge/experience/windows-powershell-command-chaining.md",
        "knowledge-hub/knowledge/patterns/context-gate-spec-validation-loop.md",
        "knowledge-hub/knowledge/standards/public-knowledge-boundary.md"
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
        "docs/release-readiness.md",
        "docs/release-process.md",
        "docs/roadmap/evolution-plan.md",
        "knowledge-hub/templates/project-root/AGENTS.md",
        "knowledge-hub/templates/project-agent/AGENTS.md",
        "skills/project-bootstrap/assets/knowledge-hub-template/templates/project-root/AGENTS.md",
        "skills/project-bootstrap/assets/knowledge-hub-template/templates/project-agent/AGENTS.md",
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
    $script:evidence.language_policy = [ordered]@{
        project_language_policy_present = [bool]$languagePolicyPresent
        bootstrap_hot_memory_present = [bool]$hotMemoryExists
        bootstrap_project_language_policy_present = [bool]$bootstrapLanguagePolicyPresent
        auto_language_write_behavior = "deferred"
    }
    if ($languagePolicyPresent -and $hotMemoryExists -and $bootstrapLanguagePolicyPresent) {
        Add-Check "language policy templates" "PASS" "Project Language Policy is present in repo and bootstrap output; bootstrap hot memory files are present." $evidence.language_policy
        Add-Check "first-session language auto-write behavior" "DEFERRED" "Automatic first-session language writing is not implemented as a script capability; validate manually when that feature exists."
    }
    else {
        Add-Check "language policy templates" "FAIL" "Language policy or bootstrap hot memory check failed." $evidence.language_policy
    }
}
catch {
    Add-Check "language policy templates" "FAIL" $_.Exception.Message
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
