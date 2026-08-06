[CmdletBinding(DefaultParameterSetName = "GitDiff")]
param(
    [ValidateSet("iteration", "pre-push", "release")]
    [string]$Stage = "iteration",
    [Parameter(ParameterSetName = "Paths", Mandatory = $true)]
    [Alias("Paths")]
    [string[]]$ChangedPath,
    [Parameter(ParameterSetName = "GitDiff")]
    [string]$BaseRef = "HEAD~1",
    [Parameter(ParameterSetName = "GitDiff")]
    [string]$HeadRef = "HEAD",
    [Parameter(ParameterSetName = "GitDiff")]
    [string]$RepositoryRoot = "",
    [string]$ScratchRoot = "",
    [switch]$DryRun,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $scriptDir "validation/powershell-runtime-requirement.ps1")
Assert-AgentEcosystemPowerShellRuntime
$defaultRepoRoot = Split-Path -Parent $scriptDir
$repoRoot = if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $defaultRepoRoot } else { [System.IO.Path]::GetFullPath($RepositoryRoot) }
$script:inputParameterSet = $PSCmdlet.ParameterSetName
$stageKey = $Stage.Replace('-', '_')
if ([string]::IsNullOrWhiteSpace($ScratchRoot)) {
    $ScratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-ecosystem-local-validation-{0}" -f ([Guid]::NewGuid().ToString("N")))
}
$scratchRootFull = [System.IO.Path]::GetFullPath($ScratchRoot)
$resultPath = Join-Path $scratchRootFull "local-validation-result.json"

function Get-HostExecutable {
    param([string]$HostName)
    if ($HostName -eq "current") {
        return [string](Get-Process -Id $PID).Path
    }
    return Resolve-AgentEcosystemPwshExecutable
}

function Format-CommandArgument {
    param([string]$Value)
    if ($Value -notmatch '[\s"]') { return $Value }
    return ('"{0}"' -f $Value.Replace('"', '\"'))
}

function Get-ActionInvocation {
    param([object]$Action, [int]$Index)
    $scriptPath = Join-Path $repoRoot ([string]$Action.script).Replace('/', [IO.Path]::DirectorySeparatorChar)
    $scriptArguments = @($Action.arguments)
    if ([string]$Action.script -eq "scripts/validate-targeted-change.ps1") {
        if ($script:inputParameterSet -eq "Paths") {
            $scriptArguments += "-ChangedPath"
            # -File cannot bind multiple command-line arguments to one array parameter reliably.
            $scriptArguments += (@($ChangedPath) -join ',')
        }
        else {
            $scriptArguments += @("-BaseRef", $BaseRef, "-HeadRef", $HeadRef)
        }
    }
    if ([string]$Action.script -eq "scripts/validate-release.ps1") {
        $scriptArguments += @("-ScratchRoot", (Join-Path $scratchRootFull ("{0:D2}-{1}" -f $Index, [string]$Action.id)))
    }
    $scriptArguments += "-Json"

    $hostExecutable = Get-HostExecutable -HostName ([string]$Action.host)
    $hostArguments = @("-NoProfile", "-NonInteractive")
    $hostArguments += @("-File", $scriptPath)
    $hostArguments += $scriptArguments
    $displayExecutable = if ([string]::IsNullOrWhiteSpace($hostExecutable)) { "<unavailable:$($Action.host)>" } else { $hostExecutable }
    $commandLine = ((@($displayExecutable) + $hostArguments | ForEach-Object { Format-CommandArgument -Value ([string]$_) }) -join ' ')
    return [ordered]@{
        executable = $hostExecutable
        arguments = @($hostArguments)
        command_line = $commandLine
    }
}

function Write-ActionCheckpoint {
    param([string]$Status, [DateTimeOffset]$StageStartedAt, [System.Diagnostics.Stopwatch]$StageStopwatch, [object[]]$Results, [object[]]$Skipped)
    if ($DryRun.IsPresent) { return }
    $checkpoint = [ordered]@{
        schema_version = 1
        stage = $Stage
        status = $Status
        updated_at_utc = [DateTimeOffset]::UtcNow.ToString("o")
        duration_ms = [long]$StageStopwatch.ElapsedMilliseconds
        stage_started_at_utc = $StageStartedAt.ToString("o")
        actions = @($Results)
        skipped = @($Skipped)
    }
    $checkpoint | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8
}

if ($script:inputParameterSet -eq "Paths") {
    $classificationRaw = @(& (Join-Path $scriptDir "validate-change.ps1") -ChangedPath $ChangedPath -Json) -join "`n"
}
else {
    $classificationRaw = @(& (Join-Path $scriptDir "validate-change.ps1") -BaseRef $BaseRef -HeadRef $HeadRef -RepositoryRoot $repoRoot -Json) -join "`n"
}
$classification = $classificationRaw | ConvertFrom-Json
& (Join-Path $scriptDir "validation/release-classifier-output-contract.ps1") -Result $classification | Out-Null
& (Join-Path $scriptDir "validation/local-validation-plan-contract.ps1") -Result $classification | Out-Null
$stagePlan = $classification.local_plan.stages.$stageKey
if ($null -eq $stagePlan) { throw "Classifier local plan is missing stage '$stageKey'." }
if (-not $DryRun.IsPresent) { New-Item -ItemType Directory -Force -Path $scratchRootFull | Out-Null }

$startedAt = [DateTimeOffset]::UtcNow
$stageStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$actionResults = New-Object 'System.Collections.Generic.List[object]'
$failed = $false
$unavailable = $false
$actions = @($stagePlan.actions)
Write-ActionCheckpoint -Status "RUNNING" -StageStartedAt $startedAt -StageStopwatch $stageStopwatch -Results @() -Skipped @($stagePlan.skipped)
for ($index = 0; $index -lt $actions.Count; $index++) {
    $action = $actions[$index]
    $invocation = Get-ActionInvocation -Action $action -Index ($index + 1)
    $actionStartedAt = [DateTimeOffset]::UtcNow
    $actionStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $status = "PLANNED"
    $exitCode = $null
    $outputLines = @()
    if ($DryRun.IsPresent -and [string]::IsNullOrWhiteSpace([string]$invocation.executable)) {
        $status = "UNAVAILABLE"
        $exitCode = 127
        $outputLines = @("Required host '$($action.host)' is unavailable.")
        $unavailable = $true
    }
    elseif (-not $DryRun.IsPresent) {
        if ([string]::IsNullOrWhiteSpace([string]$invocation.executable)) {
            $status = "FAIL"
            $exitCode = 127
            $outputLines = @("Required host '$($action.host)' is unavailable.")
        }
        else {
            $outputLines = @(& $invocation.executable @($invocation.arguments) 2>&1 | ForEach-Object { [string]$_ })
            $exitCode = [int]$LASTEXITCODE
            $status = if ($exitCode -eq 0) { "PASS" } else { "FAIL" }
        }
    }
    $actionStopwatch.Stop()
    $actionCompletedAt = [DateTimeOffset]::UtcNow
    $actionResults.Add([ordered]@{
        id = [string]$action.id
        host = [string]$action.host
        suite = [string]$action.suite
        reason = [string]$action.reason
        command_line = [string]$invocation.command_line
        status = $status
        exit_code = $exitCode
        started_at_utc = $actionStartedAt.ToString("o")
        completed_at_utc = $actionCompletedAt.ToString("o")
        duration_ms = [long]$actionStopwatch.ElapsedMilliseconds
        output_line_count = @($outputLines).Count
        failure_output = $(if ($status -in @("FAIL", "UNAVAILABLE")) { @($outputLines | Select-Object -Last 20) } else { @() })
    })
    Write-ActionCheckpoint -Status $(if ($status -eq "FAIL") { "FAIL" } else { "RUNNING" }) -StageStartedAt $startedAt -StageStopwatch $stageStopwatch -Results @($actionResults.ToArray()) -Skipped @($stagePlan.skipped)
    if ($status -eq "FAIL") {
        $failed = $true
        for ($remaining = $index + 1; $remaining -lt $actions.Count; $remaining++) {
            $remainingAction = $actions[$remaining]
            $remainingInvocation = Get-ActionInvocation -Action $remainingAction -Index ($remaining + 1)
            $actionResults.Add([ordered]@{
                id = [string]$remainingAction.id
                host = [string]$remainingAction.host
                suite = [string]$remainingAction.suite
                reason = [string]$remainingAction.reason
                command_line = [string]$remainingInvocation.command_line
                status = "SKIPPED"
                exit_code = $null
                started_at_utc = $null
                completed_at_utc = $null
                duration_ms = 0L
                output_line_count = 0
                failure_output = @()
            })
        }
        Write-ActionCheckpoint -Status "FAIL" -StageStartedAt $startedAt -StageStopwatch $stageStopwatch -Results @($actionResults.ToArray()) -Skipped @($stagePlan.skipped)
        break
    }
}
$stageStopwatch.Stop()
$completedAt = [DateTimeOffset]::UtcNow
$result = [ordered]@{
    schema_version = 1
    stage = $Stage
    status = $(if ($failed -or $unavailable) { "FAIL" } else { "PASS" })
    dry_run = [bool]$DryRun.IsPresent
    result_path = $(if ($DryRun.IsPresent) { $null } else { $resultPath })
    classification = $classification
    actions = @($actionResults.ToArray())
    skipped = @($stagePlan.skipped)
    timing = [ordered]@{
        started_at_utc = $startedAt.ToString("o")
        completed_at_utc = $completedAt.ToString("o")
        duration_ms = [long]$stageStopwatch.ElapsedMilliseconds
    }
    summary = [ordered]@{
        planned = @($actionResults | Where-Object status -eq "PLANNED").Count
        pass = @($actionResults | Where-Object status -eq "PASS").Count
        fail = @($actionResults | Where-Object status -in @("FAIL", "UNAVAILABLE")).Count
        skipped = @($stagePlan.skipped).Count + @($actionResults | Where-Object status -eq "SKIPPED").Count
    }
}
if (-not $DryRun.IsPresent) {
    $result | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $resultPath -Encoding UTF8
}

if ($Json.IsPresent) {
    $result | ConvertTo-Json -Depth 14
}
else {
    Write-Output ("Local validation stage: {0} (Tier {1})" -f $Stage, $classification.detected_tier)
    foreach ($action in $result.actions) {
        Write-Output ("[{0}] {1} | host={2} | suite={3} | {4}" -f $action.status, $action.id, $action.host, $action.suite, $action.command_line)
    }
    foreach ($skip in $result.skipped) {
        Write-Output ("[SKIPPED] {0} | {1}" -f $skip.id, $skip.reason)
    }
    Write-Output ("Stage duration: {0} ms" -f $result.timing.duration_ms)
    if (-not $DryRun.IsPresent) { Write-Output ("Result: {0}" -f $resultPath) }
}

if ($failed -or $unavailable) { throw "Local validation stage '$Stage' failed." }
