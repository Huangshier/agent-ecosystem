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

$inheritProject = Join-Path $scratchFull "existing-zh-cn"
New-Item -ItemType Directory -Path $inheritProject | Out-Null
& $BootstrapScript -ProjectDir $inheritProject -HubDir $HubDir -ProjectLanguage "zh-CN" -SkipMemoryUpgradeAnalysis | Out-Null
$missingScaffold = Join-Path $inheritProject ".agents/context/README.md"
Remove-Item -LiteralPath $missingScaffold -Force
$inheritOutput = @(& $BootstrapScript -ProjectDir $inheritProject -HubDir $HubDir -AnalyzeMemoryUpgrade)
$inheritLock = Get-Content -LiteralPath (Join-Path $inheritProject ".agents/hub.lock.json") -Raw | ConvertFrom-Json
if ([string]$inheritLock.project_language -ne "zh-CN") {
    throw "Omitted -ProjectLanguage did not inherit zh-CN from hub.lock.json."
}
$expectedZhScaffold = Join-Path $HubDir "templates/languages/zh-CN/project-agent/context/README.md"
if (-not (Test-Path -LiteralPath $missingScaffold -PathType Leaf) -or
    (Get-FileHash -LiteralPath $missingScaffold -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $expectedZhScaffold -Algorithm SHA256).Hash) {
    throw "Inherited bootstrap did not restore the missing zh-CN scaffold."
}
$resolvedIndex = [array]::FindIndex([string[]]$inheritOutput, [Predicate[string]]{ param($line) $line -match '^Resolved project dir: ' })
$completeIndex = [array]::FindIndex([string[]]$inheritOutput, [Predicate[string]]{ param($line) $line -eq 'Project bootstrap complete.' })
if ($resolvedIndex -lt 0 -or $completeIndex -lt 0 -or $resolvedIndex -ge $completeIndex) {
    throw "Resolved project dir was not visible before bootstrap completion output."
}
$results.Add([ordered]@{ name = "inherit-lock-language"; status = "PASS"; project_language = "zh-CN" }) | Out-Null

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

$conflictProject = Join-Path $scratchFull "language-conflict"
New-Item -ItemType Directory -Path $conflictProject | Out-Null
& $BootstrapScript -ProjectDir $conflictProject -HubDir $HubDir -ProjectLanguage "zh-CN" -SkipMemoryUpgradeAnalysis | Out-Null
$conflictGuide = Join-Path $conflictProject ".agents/AGENTS.md"
Set-Content -LiteralPath $conflictGuide -Value "Project memory language: English." -Encoding ASCII
$conflictBefore = Get-TreeFingerprint -Root $conflictProject
$conflictFailure = Assert-ExpectedFailure -Name "language-conflict" -ExpectedToken "Project language conflict" -Command {
    & $BootstrapScript -ProjectDir $conflictProject -HubDir $HubDir -AnalyzeMemoryUpgrade
}
Assert-Unchanged -Root $conflictProject -Before $conflictBefore -Name "language-conflict"
$results.Add([ordered]@{ name = "language-conflict"; status = "PASS"; error = $conflictFailure.error }) | Out-Null

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
if ($Json.IsPresent) {
    $report | ConvertTo-Json -Depth 6
} else {
    Write-Output ("Project bootstrap safety fixtures: PASS ({0})" -f $results.Count)
    foreach ($result in $results) {
        Write-Output ("  - {0}: {1}" -f $result.name, $result.status)
    }
}
