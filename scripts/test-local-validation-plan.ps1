[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
$classifier = Join-Path $PSScriptRoot "validate-change.ps1"
$orchestrator = Join-Path $PSScriptRoot "invoke-local-validation.ps1"
$planContract = Join-Path $PSScriptRoot "validation/local-validation-plan-contract.ps1"
$results = New-Object 'System.Collections.Generic.List[object]'

function Get-Classification([string[]]$Path) {
    return ((@(& $classifier -ChangedPath $Path -Json) -join "`n") | ConvertFrom-Json)
}

function Assert-PlanCase {
    param([string]$Name, [string[]]$Path, [int]$Tier, [bool]$ExpectPrePushHeavy)
    $value = Get-Classification -Path $Path
    if ([int]$value.detected_tier -ne $Tier) { throw "$Name expected Tier $Tier." }
    if ([int]$value.local_plan.schema_version -ne 2) { throw "$Name has no schema-2 local plan." }
    & $planContract -Result $value | Out-Null
    $iterationScripts = @($value.local_plan.stages.iteration.actions.script)
    if ($iterationScripts -contains "scripts/validate-release.ps1") {
        throw "$Name iteration plan includes a release checkpoint."
    }
    $releaseFullHosts = @($value.local_plan.stages.release.actions | Where-Object script -eq "scripts/validate-release.ps1" | ForEach-Object host)
    if (($releaseFullHosts -join ',') -cne "pwsh") { throw "$Name release plan does not preserve the pwsh host." }
    $releaseFullActions = @($value.local_plan.stages.release.actions | Where-Object script -eq "scripts/validate-release.ps1")
    foreach ($action in $releaseFullActions) {
        if ((@($action.arguments) -join ',') -cne "-ValidationShard,RepositoryCheckpoint") { throw "$Name release plan does not explicitly select the RepositoryCheckpoint shard." }
    }
    $prePushHeavy = @($value.local_plan.stages.pre_push.actions | Where-Object script -eq "scripts/test-heavy-targeted-regression.ps1")
    if (($prePushHeavy.Count -gt 0) -ne $ExpectPrePushHeavy) { throw "$Name has an incorrect pre-push heavy decision." }
    $results.Add([ordered]@{ name = $Name; status = "PASS" })
}

Assert-PlanCase -Name "tier-zero" -Path "README.md" -Tier 0 -ExpectPrePushHeavy $false
Assert-PlanCase -Name "tier-one" -Path "knowledge-hub/knowledge/catalog.md" -Tier 1 -ExpectPrePushHeavy $false
Assert-PlanCase -Name "tier-two" -Path "scripts/install.ps1" -Tier 2 -ExpectPrePushHeavy $false
Assert-PlanCase -Name "tier-three-covered" -Path "CHANGELOG.md" -Tier 3 -ExpectPrePushHeavy $false
Assert-PlanCase -Name "tier-three-self-protection" -Path "scripts/validate-change.ps1" -Tier 3 -ExpectPrePushHeavy $true
Assert-PlanCase -Name "tier-three-unknown" -Path "future-surface/value.bin" -Tier 3 -ExpectPrePushHeavy $true

$iterationDryRun = ((@(& $orchestrator -Stage iteration -ChangedPath "scripts/validate-change.ps1" -DryRun -Json) -join "`n") | ConvertFrom-Json)
if (@($iterationDryRun.actions | Where-Object suite -eq "full-release-validation").Count -ne 0) { throw "Tier 3 iteration dry-run planned full validation." }
if (@($iterationDryRun.actions | Where-Object status -eq "PLANNED").Count -ne @($iterationDryRun.actions).Count) { throw "Dry-run actions were not reported as PLANNED." }

$prePushDryRun = ((@(& $orchestrator -Stage pre-push -ChangedPath "scripts/validate-change.ps1" -DryRun -Json) -join "`n") | ConvertFrom-Json)
if (@($prePushDryRun.actions | Where-Object suite -eq "validation-self-protection").Count -ne 1) { throw "Control-surface pre-push dry-run did not plan one independent self-protection oracle." }
if (@($prePushDryRun.actions | Where-Object suite -eq "full-release-validation").Count -ne 0) { throw "Affected pre-push dry-run planned a release checkpoint." }
foreach ($action in @($prePushDryRun.actions)) {
    if ([string]::IsNullOrWhiteSpace([string]$action.command_line) -or [string]::IsNullOrWhiteSpace([string]$action.host) -or [string]::IsNullOrWhiteSpace([string]$action.suite) -or [string]::IsNullOrWhiteSpace([string]$action.reason)) {
        throw "Pre-push dry-run omitted command, host, suite, or reason."
    }
    if ([long]$action.duration_ms -lt 0) { throw "Pre-push dry-run emitted negative timing." }
}
if ([long]$prePushDryRun.timing.duration_ms -lt 0) { throw "Pre-push stage emitted negative timing." }
$results.Add([ordered]@{ name = "orchestrator-dry-run"; status = "PASS" })

$processStartInfo = [System.Diagnostics.ProcessStartInfo]::new()
$processStartInfo.FileName = [string](Get-Process -Id $PID).Path
$processStartInfo.UseShellExecute = $false
$processStartInfo.RedirectStandardOutput = $true
$processStartInfo.RedirectStandardError = $true
$escapedOrchestrator = $orchestrator.Replace("'", "''")
$missingPwshCommand = @"
function global:Get-Command {
    [CmdletBinding()]
    param([Parameter(Position = 0)][string]`$Name, [object]`$CommandType)
    if (`$Name -ceq 'pwsh') { return `$null }
    return Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
}
& '$escapedOrchestrator' -Stage release -ChangedPath README.md -DryRun -Json
"@
$encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($missingPwshCommand))
foreach ($argument in @("-NoProfile", "-NonInteractive", "-EncodedCommand", $encodedCommand)) {
    [void]$processStartInfo.ArgumentList.Add([string]$argument)
}
$missingPwshProcess = [System.Diagnostics.Process]::Start($processStartInfo)
$missingPwshStdout = $missingPwshProcess.StandardOutput.ReadToEnd()
$missingPwshStderr = $missingPwshProcess.StandardError.ReadToEnd()
$missingPwshProcess.WaitForExit()
if ($missingPwshProcess.ExitCode -eq 0) {
    throw "Release dry-run with missing pwsh returned a successful process exit."
}
$missingPwshDryRun = $missingPwshStdout | ConvertFrom-Json
$unavailablePwshActions = @($missingPwshDryRun.actions | Where-Object {
    $_.host -eq "pwsh" -and $_.status -eq "UNAVAILABLE" -and [int]$_.exit_code -eq 127
})
if ([string]$missingPwshDryRun.status -cne "FAIL" -or $unavailablePwshActions.Count -lt 1 -or [int]$missingPwshDryRun.summary.fail -lt 1) {
    throw "Release dry-run reported missing pwsh as executable success."
}
if (@($missingPwshDryRun.actions | Where-Object { $_.host -eq "pwsh" -and $_.status -in @("PASS", "PLANNED") }).Count -ne 0) {
    throw "Release dry-run left a missing pwsh action in a successful or executable state."
}
if ($missingPwshStderr -notmatch "Local validation stage 'release' failed\.") {
    throw "Release dry-run with missing pwsh did not emit the stable stage failure."
}
$results.Add([ordered]@{ name = "missing-pwsh-fails-closed"; status = "PASS" })

$invalid = Get-Classification -Path "README.md"
$invalid.local_plan.stages.iteration.actions[0].script = "scripts/validate-release.ps1"
$rejected = $false
try { & $planContract -Result $invalid | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw "Local plan contract accepted full validation during iteration." }
$results.Add([ordered]@{ name = "invalid-plan-fails-closed"; status = "PASS" })

$missingAction = Get-Classification -Path "README.md"
$missingAction.local_plan.stages.pre_push.actions = @($missingAction.local_plan.stages.pre_push.actions | Where-Object script -ne "scripts/validate-targeted-change.ps1")
$rejected = $false
try { & $planContract -Result $missingAction | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw "Local plan contract accepted a pre-push plan with no affected-suite action." }
$results.Add([ordered]@{ name = "missing-action-fails-closed"; status = "PASS" })

$invalidShard = Get-Classification -Path "README.md"
$invalidShard.local_plan.stages.release.actions[1].arguments = @("-ValidationShard", "Full")
$rejected = $false
try { & $planContract -Result $invalidShard | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw "Local plan contract accepted a release action without the RepositoryCheckpoint shard." }
$results.Add([ordered]@{ name = "release-shard-fails-closed"; status = "PASS" })

$summary = [ordered]@{ schema_version = 2; pass = $results.Count; fail = 0; cases = @($results.ToArray()) }
if ($Json.IsPresent) { $summary | ConvertTo-Json -Depth 6 } else { Write-Output ("local validation plan fixtures: PASS={0} FAIL=0" -f $summary.pass) }
