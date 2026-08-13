[CmdletBinding()]
param(
    [string]$RepositoryRoot = "",
    [string]$ScratchRoot = "",
    [string]$BootstrapScript = "",
    [string]$HubDir = "",
    [switch]$Json
)

$ErrorActionPreference = "Stop"

# Get-TreeFingerprint: 计算目录的文件和空目录指纹；参数 Root 为待检查目录。
function Get-TreeFingerprint {
    param([Parameter(Mandatory = $true)][string]$Root)

    if (-not (Test-Path -LiteralPath $Root)) {
        return "MISSING"
    }

    $rootFull = (Resolve-Path -LiteralPath $Root).Path.TrimEnd([char[]]"\/")
    $records = New-Object 'System.Collections.Generic.List[string]'
    Get-ChildItem -LiteralPath $rootFull -Recurse -Force | Sort-Object FullName | ForEach-Object {
        $relative = $_.FullName.Substring($rootFull.Length).TrimStart([char[]]"\/") -replace "\\", "/"
        if ($_.PSIsContainer) {
            $records.Add("D:$relative") | Out-Null
        } else {
            $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            $records.Add("F:$relative`:$hash") | Out-Null
        }
    }
    return ($records.ToArray() -join "`n")
}

# Assert-ExpectedFailure: 执行预期失败的命令并校验错误文本；参数 Name、Command、ExpectedToken 描述用例。
function Assert-ExpectedFailure {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Command,
        [Parameter(Mandatory = $true)][string]$ExpectedToken
    )

    try {
        & $Command | Out-Null
    } catch {
        $message = $_.Exception.Message
        if ($message -notlike ("*{0}*" -f $ExpectedToken)) {
            throw "Fixture '$Name' expected error containing '$ExpectedToken', got: $message"
        }
        return [ordered]@{ name = $Name; error = $message }
    }

    throw "Fixture '$Name' expected bootstrap to fail."
}

# Assert-Unchanged: 校验失败命令没有改变目录；参数 Root、Before、Name 为目录、旧指纹和用例名。
function Assert-Unchanged {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Before,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $after = Get-TreeFingerprint -Root $Root
    if ($after -ne $Before) {
        throw "Fixture '$Name' changed the target tree on an error path."
    }
}

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}
if ([string]::IsNullOrWhiteSpace($ScratchRoot)) {
    $ScratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("project-bootstrap-safety-{0}" -f [guid]::NewGuid().ToString("N"))
}
if ([string]::IsNullOrWhiteSpace($BootstrapScript)) {
    $BootstrapScript = Join-Path $RepositoryRoot "skills/project-bootstrap/scripts/bootstrap_project.ps1"
}
if ([string]::IsNullOrWhiteSpace($HubDir)) {
    $HubDir = Join-Path $RepositoryRoot "knowledge-hub"
}
if (-not (Test-Path -LiteralPath $BootstrapScript -PathType Leaf)) {
    throw "Bootstrap script not found: $BootstrapScript"
}
if (-not (Test-Path -LiteralPath $HubDir -PathType Container)) {
    throw "Knowledge hub not found: $HubDir"
}

New-Item -ItemType Directory -Force -Path $ScratchRoot | Out-Null
$scratchFull = (Resolve-Path -LiteralPath $ScratchRoot).Path
$results = New-Object 'System.Collections.Generic.List[object]'

$repositoryStyleHub = Join-Path $scratchFull "repository-style-hub"
$repositoryStyleProject = Join-Path $scratchFull "repository-style-project"
New-Item -ItemType Directory -Path (Join-Path $repositoryStyleHub "skills") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $repositoryStyleHub "knowledge-hub/templates/languages") -Force | Out-Null
Set-Content -LiteralPath (Join-Path $repositoryStyleHub "README.md") -Value "fixture" -Encoding ASCII
New-Item -ItemType Directory -Path $repositoryStyleProject | Out-Null
Set-Content -LiteralPath (Join-Path $repositoryStyleProject "sentinel.txt") -Value "project fixture" -Encoding ASCII
$repositoryStyleHubBefore = Get-TreeFingerprint -Root $repositoryStyleHub
$repositoryStyleProjectBefore = Get-TreeFingerprint -Root $repositoryStyleProject
$repositoryStyleFailure = Assert-ExpectedFailure -Name "repository-style-explicit-hub" -ExpectedToken "directly contains templates/languages" -Command {
    & $BootstrapScript -ProjectDir $repositoryStyleProject -HubDir $repositoryStyleHub -SkipMemoryUpgradeAnalysis
}
if ($repositoryStyleFailure.error -notlike "*knowledge-hub subdirectory*") {
    throw "Fixture 'repository-style-explicit-hub' expected a knowledge-hub subdirectory hint."
}
Assert-Unchanged -Root $repositoryStyleHub -Before $repositoryStyleHubBefore -Name "repository-style-explicit-hub-hub"
Assert-Unchanged -Root $repositoryStyleProject -Before $repositoryStyleProjectBefore -Name "repository-style-explicit-hub-project"
$results.Add([ordered]@{ name = "repository-style-explicit-hub"; status = "PASS"; error = $repositoryStyleFailure.error }) | Out-Null

$ordinaryNonHub = Join-Path $scratchFull "ordinary-non-hub"
$ordinaryNonHubProject = Join-Path $scratchFull "ordinary-non-hub-project"
New-Item -ItemType Directory -Path $ordinaryNonHub | Out-Null
Set-Content -LiteralPath (Join-Path $ordinaryNonHub "sentinel.txt") -Value "hub fixture" -Encoding ASCII
New-Item -ItemType Directory -Path $ordinaryNonHubProject | Out-Null
Set-Content -LiteralPath (Join-Path $ordinaryNonHubProject "sentinel.txt") -Value "project fixture" -Encoding ASCII
$ordinaryNonHubBefore = Get-TreeFingerprint -Root $ordinaryNonHub
$ordinaryNonHubProjectBefore = Get-TreeFingerprint -Root $ordinaryNonHubProject
$ordinaryNonHubFailure = Assert-ExpectedFailure -Name "ordinary-explicit-non-hub" -ExpectedToken "directly contains templates/languages" -Command {
    & $BootstrapScript -ProjectDir $ordinaryNonHubProject -HubDir $ordinaryNonHub -SkipMemoryUpgradeAnalysis
}
if ($ordinaryNonHubFailure.error -like "*knowledge-hub subdirectory*") {
    throw "Fixture 'ordinary-explicit-non-hub' received an inapplicable knowledge-hub subdirectory hint."
}
Assert-Unchanged -Root $ordinaryNonHub -Before $ordinaryNonHubBefore -Name "ordinary-explicit-non-hub-hub"
Assert-Unchanged -Root $ordinaryNonHubProject -Before $ordinaryNonHubProjectBefore -Name "ordinary-explicit-non-hub-project"
$results.Add([ordered]@{ name = "ordinary-explicit-non-hub"; status = "PASS"; error = $ordinaryNonHubFailure.error }) | Out-Null

$explicitNewHub = Join-Path $scratchFull "explicit-new-hub"
$explicitNewProject = Join-Path $scratchFull "explicit-new-project"
New-Item -ItemType Directory -Path $explicitNewProject | Out-Null
& $BootstrapScript -ProjectDir $explicitNewProject -HubDir $explicitNewHub -SkipMemoryUpgradeAnalysis | Out-Null
if (-not (Test-Path -LiteralPath (Join-Path $explicitNewHub "templates/languages") -PathType Container)) {
    throw "Explicit new hub directory was not initialized."
}
if ($LASTEXITCODE -ne 0) {
    throw "Successful explicit new hub initialization leaked LASTEXITCODE=$LASTEXITCODE."
}
$results.Add([ordered]@{ name = "explicit-new-hub"; status = "PASS" }) | Out-Null

$explicitEmptyHub = Join-Path $scratchFull "explicit-empty-hub"
$explicitEmptyProject = Join-Path $scratchFull "explicit-empty-project"
New-Item -ItemType Directory -Path $explicitEmptyHub | Out-Null
New-Item -ItemType Directory -Path $explicitEmptyProject | Out-Null
& $BootstrapScript -ProjectDir $explicitEmptyProject -HubDir $explicitEmptyHub -SkipMemoryUpgradeAnalysis | Out-Null
if (-not (Test-Path -LiteralPath (Join-Path $explicitEmptyHub "templates/languages") -PathType Container)) {
    throw "Explicit empty hub directory was not initialized."
}
$results.Add([ordered]@{ name = "explicit-empty-hub"; status = "PASS" }) | Out-Null

$defaultHubProfile = Join-Path $scratchFull "default-hub-profile"
$defaultHubProject = Join-Path $scratchFull "default-hub-project"
New-Item -ItemType Directory -Path $defaultHubProfile | Out-Null
New-Item -ItemType Directory -Path $defaultHubProject | Out-Null
$previousUserProfile = $env:USERPROFILE
try {
    $env:USERPROFILE = $defaultHubProfile
    & $BootstrapScript -ProjectDir $defaultHubProject -SkipMemoryUpgradeAnalysis | Out-Null
} finally {
    $env:USERPROFILE = $previousUserProfile
}
$expectedDefaultHub = Join-Path $defaultHubProfile ".agents/knowledge-hub/templates/languages"
if (-not (Test-Path -LiteralPath $expectedDefaultHub -PathType Container)) {
    throw "Missing default runtime hub was not initialized."
}
$results.Add([ordered]@{ name = "missing-default-hub"; status = "PASS" }) | Out-Null

$inheritProject = Join-Path $scratchFull "existing-zh-cn"
New-Item -ItemType Directory -Path $inheritProject | Out-Null
& $BootstrapScript -ProjectDir $inheritProject -HubDir $HubDir -ProjectLanguage "zh-CN" -SkipMemoryUpgradeAnalysis | Out-Null
$missingScaffold = Join-Path $inheritProject ".agents/context"
Remove-Item -LiteralPath $missingScaffold -Recurse -Force
$inheritOutput = @(& $BootstrapScript -ProjectDir $inheritProject -HubDir $HubDir -AnalyzeMemoryUpgrade)
$inheritLock = Get-Content -LiteralPath (Join-Path $inheritProject ".agents/hub.lock.json") -Raw | ConvertFrom-Json
if ([string]$inheritLock.project_language -ne "zh-CN") {
    throw "Omitted -ProjectLanguage did not inherit zh-CN from hub.lock.json."
}
$inheritWorkspaceModel = [string]$inheritLock.workspace_model
if ($inheritWorkspaceModel -ne "c3.3" -or [string]$inheritLock.workspace_state -ne "active") {
    throw "Fresh project bootstrap did not produce the active C3.3 workspace contract."
}
$expectedZhWorkspace = Join-Path $inheritProject ".agents/context"
if (-not (Test-Path -LiteralPath $expectedZhWorkspace -PathType Container)) {
    throw "Inherited bootstrap did not restore the C3.3 workspace context root."
}
$resolvedIndex = [array]::FindIndex([string[]]$inheritOutput, [Predicate[string]]{ param($line) $line -match '^Resolved project dir: ' })
$completeIndex = [array]::FindIndex([string[]]$inheritOutput, [Predicate[string]]{ param($line) $line -eq 'Project bootstrap complete.' })
if ($resolvedIndex -lt 0 -or $completeIndex -lt 0 -or $resolvedIndex -ge $completeIndex) {
    throw "Resolved project dir was not visible before bootstrap completion output."
}
$results.Add([ordered]@{ name = "inherit-lock-language"; status = "PASS"; project_language = "zh-CN" }) | Out-Null
$results.Add([ordered]@{ name = "valid-explicit-hub"; status = "PASS" }) | Out-Null

$unknownProject = Join-Path $scratchFull "unknown-parameter"
New-Item -ItemType Directory -Path $unknownProject | Out-Null
$unknownBefore = Get-TreeFingerprint -Root $unknownProject
$unknownFailure = Assert-ExpectedFailure -Name "unknown-parameter" -ExpectedToken "UnknownFixtureParameter" -Command {
    & $BootstrapScript -ProjectDir $unknownProject -HubDir $HubDir -UnknownFixtureParameter "value" -SkipMemoryUpgradeAnalysis
}
Assert-Unchanged -Root $unknownProject -Before $unknownBefore -Name "unknown-parameter"
$results.Add([ordered]@{ name = "unknown-parameter"; status = "PASS"; error = $unknownFailure.error }) | Out-Null

$projectRootMistake = Join-Path $scratchFull "project-root-mistake"
New-Item -ItemType Directory -Path $projectRootMistake | Out-Null
$projectRootBefore = Get-TreeFingerprint -Root $projectRootMistake
$projectRootFailure = Assert-ExpectedFailure -Name "project-root-mistake" -ExpectedToken "Use -ProjectDir" -Command {
    & $BootstrapScript -ProjectRoot $projectRootMistake -HubDir $HubDir -AnalyzeMemoryUpgrade
}
Assert-Unchanged -Root $projectRootMistake -Before $projectRootBefore -Name "project-root-mistake"
$results.Add([ordered]@{ name = "project-root-mistake"; status = "PASS"; error = $projectRootFailure.error }) | Out-Null

$conflictOmittedProject = Join-Path $scratchFull "language-conflict-omitted"
New-Item -ItemType Directory -Path $conflictOmittedProject | Out-Null
& $BootstrapScript -ProjectDir $conflictOmittedProject -HubDir $HubDir -ProjectLanguage "zh-CN" -SkipMemoryUpgradeAnalysis | Out-Null
$conflictOmittedGuide = Join-Path $conflictOmittedProject ".agents/AGENTS.md"
Set-Content -LiteralPath $conflictOmittedGuide -Value "Project memory language: English." -Encoding ASCII
$conflictOmittedBefore = Get-TreeFingerprint -Root $conflictOmittedProject
$conflictOmittedFailure = Assert-ExpectedFailure -Name "language-conflict-omitted" -ExpectedToken "Project language conflict" -Command {
    & $BootstrapScript -ProjectDir $conflictOmittedProject -HubDir $HubDir -AnalyzeMemoryUpgrade
}
Assert-Unchanged -Root $conflictOmittedProject -Before $conflictOmittedBefore -Name "language-conflict-omitted"
$results.Add([ordered]@{ name = "language-conflict-omitted"; status = "PASS"; error = $conflictOmittedFailure.error }) | Out-Null

$conflictExplicitProject = Join-Path $scratchFull "language-conflict-explicit"
New-Item -ItemType Directory -Path $conflictExplicitProject | Out-Null
& $BootstrapScript -ProjectDir $conflictExplicitProject -HubDir $HubDir -ProjectLanguage "zh-CN" -SkipMemoryUpgradeAnalysis | Out-Null
$conflictExplicitGuide = Join-Path $conflictExplicitProject ".agents/AGENTS.md"
Set-Content -LiteralPath $conflictExplicitGuide -Value "Project memory language: English." -Encoding ASCII
$conflictExplicitBefore = Get-TreeFingerprint -Root $conflictExplicitProject
$conflictExplicitFailure = Assert-ExpectedFailure -Name "language-conflict-explicit" -ExpectedToken "Project language conflict" -Command {
    & $BootstrapScript -ProjectDir $conflictExplicitProject -HubDir $HubDir -ProjectLanguage "zh-CN" -AnalyzeMemoryUpgrade
}
Assert-Unchanged -Root $conflictExplicitProject -Before $conflictExplicitBefore -Name "language-conflict-explicit"
$results.Add([ordered]@{ name = "language-conflict-explicit"; status = "PASS"; error = $conflictExplicitFailure.error }) | Out-Null

$missingProject = Join-Path $scratchFull "missing-target"
$missingFailure = Assert-ExpectedFailure -Name "missing-target" -ExpectedToken "does not exist" -Command {
    & $BootstrapScript -ProjectDir $missingProject -HubDir $HubDir -SkipMemoryUpgradeAnalysis
}
if (Test-Path -LiteralPath $missingProject) {
    throw "Missing target error path created the target directory."
}
$results.Add([ordered]@{ name = "missing-target"; status = "PASS"; error = $missingFailure.error }) | Out-Null

$fileTarget = Join-Path $scratchFull "file-target.txt"
Set-Content -LiteralPath $fileTarget -Value "fixture" -Encoding ASCII
$fileHashBefore = (Get-FileHash -LiteralPath $fileTarget -Algorithm SHA256).Hash
$fileFailure = Assert-ExpectedFailure -Name "file-target" -ExpectedToken "does not exist" -Command {
    & $BootstrapScript -ProjectDir $fileTarget -HubDir $HubDir -SkipMemoryUpgradeAnalysis
}
if ((Get-FileHash -LiteralPath $fileTarget -Algorithm SHA256).Hash -ne $fileHashBefore) {
    throw "File target error path modified the target file."
}
$results.Add([ordered]@{ name = "file-target"; status = "PASS"; error = $fileFailure.error }) | Out-Null

$report = [ordered]@{
    status = "PASS"
    fixture_count = $results.Count
    scratch_root = $scratchFull
    fixtures = @($results.ToArray())
}
$global:LASTEXITCODE = 0
if ($Json.IsPresent) {
    $report | ConvertTo-Json -Depth 6
} else {
    Write-Output ("Project bootstrap safety fixtures: PASS ({0})" -f $results.Count)
    foreach ($result in $results) {
        Write-Output ("  - {0}: {1}" -f $result.name, $result.status)
    }
}
