[CmdletBinding()]
param(
    [string]$ScratchRoot = "",
    [switch]$Json
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $scriptDir "validation/powershell-runtime-requirement.ps1")
Assert-AgentEcosystemPowerShellRuntime

$repoRoot = Split-Path -Parent $scriptDir
. (Join-Path $scriptDir "lib/path-guard.ps1")
. (Join-Path $scriptDir "validation/release-test-helper.ps1")
. (Join-Path $scriptDir "validation/release-parser-safety-checks.ps1")

if ([string]::IsNullOrWhiteSpace($ScratchRoot)) {
    $ScratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-ecosystem-main-health-{0}" -f ([Guid]::NewGuid().ToString("N")))
}

$scratchRootFull = [System.IO.Path]::GetFullPath($ScratchRoot)
Assert-NotLiveRuntime -Path $scratchRootFull
New-Item -ItemType Directory -Force -Path $scratchRootFull | Out-Null

$script:checks = New-Object 'System.Collections.Generic.List[object]'
$script:validationCheckStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$script:validationCheckCheckpointMs = 0L
$script:evidence = [ordered]@{ audit = [ordered]@{} }

function Invoke-MainHealthRuntimeSmoke {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$ScratchRootFull
    )

    $runtimeDir = Join-PathParts $ScratchRootFull "runtime-copy"
    $projectDir = Join-PathParts $ScratchRootFull "runtime-smoke-project"
    Assert-NotLiveRuntime -Path $runtimeDir
    Assert-PathInsideRoot -Path $runtimeDir -Root $ScratchRootFull
    Assert-PathInsideRoot -Path $projectDir -Root $ScratchRootFull

    $installer = Join-PathParts $RepositoryRoot "scripts" "install.ps1"
    & $installer -Profile recommended -TargetDir $runtimeDir | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Main health copy install failed with exit code $LASTEXITCODE."
    }

    $manifestPath = Join-PathParts $runtimeDir "install-manifest.json"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Main health copy install did not create install-manifest.json."
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ([string]$manifest.profile -cne "recommended" -or [string]$manifest.install_strategy -cne "copy") {
        throw "Main health copy install returned an unexpected manifest contract."
    }

    New-Item -ItemType Directory -Force -Path $projectDir | Out-Null
    $hubDir = Join-PathParts $runtimeDir "knowledge-hub"
    $bootstrapScript = Join-PathParts $runtimeDir "skills" "project-bootstrap" "scripts" "bootstrap_project.ps1"
    & $bootstrapScript -ProjectDir $projectDir -HubDir $hubDir -SkipMemoryUpgradeAnalysis | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Main health bootstrap failed with exit code $LASTEXITCODE."
    }

    $lockPath = Join-PathParts $projectDir ".agents" "hub.lock.json"
    if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) {
        throw "Main health bootstrap did not create .agents/hub.lock.json."
    }
    $lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
    if ([string]$lock.workspace_model -cne "c3.3" -or [string]$lock.workspace_state -cne "active") {
        throw ("Main health bootstrap did not produce the active C3.3 workspace contract: {0}/{1}" -f $lock.workspace_model, $lock.workspace_state)
    }

    foreach ($relative in @("AGENTS.md", ".agents/work", ".agents/context", ".agents/procedures", ".agents/skills", "docs/specs")) {
        if (-not (Test-Path -LiteralPath (Join-PathParts $projectDir $relative))) {
            throw "Main health bootstrap did not create the C3.3 workspace path: $relative"
        }
    }

    $checkScript = Join-PathParts $runtimeDir "skills" "project-workspace" "scripts" "check-project-workspace.ps1"
    if (-not (Test-Path -LiteralPath $checkScript -PathType Leaf)) {
        throw "Main health runtime did not install project-workspace check."
    }
    $checkRaw = @(& $checkScript -ProjectRoot $projectDir -Json) -join "`n"
    $checkResult = $checkRaw | ConvertFrom-Json
    if ([string]$checkResult.status -cne "PASS") {
        throw "Main health project-workspace check did not report status=PASS."
    }

    return [ordered]@{
        install = "copy"
        profile = [string]$manifest.profile
        bootstrap = "passed"
        workspace_model = [string]$lock.workspace_model
        workspace_state = [string]$lock.workspace_state
        project_workspace_check = [string]$checkResult.status
    }
}

try {
    Invoke-ReleaseParserSafetyChecks -ValidationShard RuntimePlatform
}
catch {
    Add-Check "repository parser checks" "FAIL" $_.Exception.Message
}

try {
    Invoke-ReleaseParserSafetyChecks -ValidationShard PlatformNeutral
}
catch {
    Add-Check "public-safe and sensitive scan" "FAIL" $_.Exception.Message
}

try {
    $runtimeSmoke = Invoke-MainHealthRuntimeSmoke -RepositoryRoot $repoRoot -ScratchRootFull $scratchRootFull
    Add-Check "runtime smoke" "PASS" "Single-host copy install, C3.3 bootstrap, and project-workspace check passed." $runtimeSmoke
}
catch {
    Add-Check "runtime smoke" "FAIL" $_.Exception.Message
}

$failedChecks = @($script:checks | Where-Object { [string]$_.status -ceq "FAIL" })
$status = if ($failedChecks.Count -eq 0) { "PASS" } else { "FAIL" }
$output = [ordered]@{
    schema_version = 1
    status = $status
    check_count = $script:checks.Count
    checks = @($script:checks.ToArray())
}

if ($Json.IsPresent) {
    $output | ConvertTo-Json -Depth 10
}
else {
    Write-Output ("main health: {0}; checks={1}" -f $status, $script:checks.Count)
}

if ($status -cne "PASS") {
    exit 1
}
