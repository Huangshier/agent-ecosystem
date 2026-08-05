[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [AllowNull()]
    [object]$Result
)

$ErrorActionPreference = "Stop"

function Get-RequiredPropertyValue {
    param([object]$InputObject, [string]$Name)
    $property = @($InputObject.PSObject.Properties | Where-Object { $_.Name -ceq $Name })
    if ($property.Count -ne 1) { throw "Local validation contract is missing required property '$Name'." }
    return $property[0].Value
}

function Assert-ExactHosts {
    param([object[]]$Actions, [string]$Script, [string[]]$Expected, [string]$Context)
    $actual = @($Actions | Where-Object { [string]$_.script -ceq $Script } | ForEach-Object { [string]$_.host })
    if (($actual -join ',') -cne ($Expected -join ',')) {
        throw "$Context must use '$Script' on exactly: $($Expected -join ', ')."
    }
}

function Assert-ExactArguments {
    param([object[]]$Actions, [string]$Script, [string[]]$Expected, [string]$Context)
    $matching = @($Actions | Where-Object { [string]$_.script -ceq $Script })
    foreach ($action in $matching) {
        if ((@($action.arguments) -join ',') -cne ($Expected -join ',')) {
            throw "$Context must pass exactly: $($Expected -join ' ')."
        }
    }
}

if ($null -eq $Result -or $Result -is [string] -or $Result -is [System.Array]) { throw "Classifier result must be an object." }
$tier = Get-RequiredPropertyValue -InputObject $Result -Name "detected_tier"
if ($tier -isnot [int] -and $tier -isnot [long]) { throw "Classifier property 'detected_tier' must be an integer." }
$heavyDecision = Get-RequiredPropertyValue -InputObject $Result -Name "run_heavy_targeted_regression"
if ($heavyDecision -isnot [bool]) { throw "Classifier property 'run_heavy_targeted_regression' must be an actual Boolean." }
$selfProtectionDecision = Get-RequiredPropertyValue -InputObject $Result -Name "run_validation_self_protection"
if ($selfProtectionDecision -isnot [bool] -or [bool]$selfProtectionDecision -ne [bool]$heavyDecision) { throw "Classifier self-protection decision is invalid." }
$plan = Get-RequiredPropertyValue -InputObject $Result -Name "local_plan"
if ($null -eq $plan -or [int](Get-RequiredPropertyValue -InputObject $plan -Name "schema_version") -ne 2) { throw "Classifier local plan must use schema version 2." }
$stages = Get-RequiredPropertyValue -InputObject $plan -Name "stages"

$stageActions = [ordered]@{}
foreach ($stageName in @("iteration", "pre_push", "release")) {
    $stage = Get-RequiredPropertyValue -InputObject $stages -Name $stageName
    Get-RequiredPropertyValue -InputObject $stage -Name "actions" | Out-Null
    Get-RequiredPropertyValue -InputObject $stage -Name "skipped" | Out-Null
    if ($stage.actions -is [string]) { throw "Local stage '$stageName' actions must be an array." }
    if ($stage.skipped -is [string]) { throw "Local stage '$stageName' skipped must be an array." }
    $actions = @($stage.actions)
    if ($actions.Count -eq 0) { throw "Local stage '$stageName' must contain at least one action." }
    $ids = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($action in $actions) {
        foreach ($name in @("id", "script", "host", "suite", "reason")) {
            $value = Get-RequiredPropertyValue -InputObject $action -Name $name
            if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value)) { throw "Local stage '$stageName' action property '$name' must be a non-blank string." }
        }
        Get-RequiredPropertyValue -InputObject $action -Name "arguments" | Out-Null
        if ($action.arguments -is [string]) { throw "Local stage '$stageName' action arguments must be an array." }
        if (-not $ids.Add([string]$action.id)) { throw "Local stage '$stageName' has duplicate action id '$($action.id)'." }
        if (@("current", "pwsh") -cnotcontains [string]$action.host) { throw "Local stage '$stageName' uses unsupported host '$($action.host)'." }
        if ([string]$action.script -notmatch '^scripts/[a-z0-9-]+\.ps1$') { throw "Local stage '$stageName' action script is outside the approved scripts boundary." }
    }
    foreach ($skip in @($stage.skipped)) {
        foreach ($name in @("id", "status", "reason")) { Get-RequiredPropertyValue -InputObject $skip -Name $name | Out-Null }
        if ([string]$skip.status -cne "SKIPPED") { throw "Local stage '$stageName' skip records must use SKIPPED status." }
    }
    $stageActions[$stageName] = $actions
}

if (@($stageActions.iteration | Where-Object { [string]$_.script -eq "scripts/validate-release.ps1" }).Count -gt 0) {
    throw "Iteration must never plan a release checkpoint."
}
Assert-ExactHosts -Actions $stageActions.release -Script "scripts/validate-release.ps1" -Expected @("pwsh") -Context "Release local validation"
Assert-ExactArguments -Actions $stageActions.release -Script "scripts/validate-release.ps1" -Expected @("-ValidationShard", "RepositoryCheckpoint") -Context "Release local validation"
Assert-ExactHosts -Actions $stageActions.pre_push -Script "scripts/validate-release.ps1" -Expected @() -Context "Affected pre-push validation"
Assert-ExactHosts -Actions $stageActions.iteration -Script "scripts/validate-targeted-change.ps1" -Expected @("current") -Context "Iteration affected validation"
$expectedPrePushAffectedHosts = @("current")
Assert-ExactHosts -Actions $stageActions.pre_push -Script "scripts/validate-targeted-change.ps1" -Expected $expectedPrePushAffectedHosts -Context "Pre-push affected validation"
$expectedIterationOracle = if ([bool]$selfProtectionDecision) { @("current") } else { @() }
$expectedPrePushOracle = if ([bool]$selfProtectionDecision) { @("current") } else { @() }
$expectedReleaseOracle = if ([bool]$selfProtectionDecision) { @("pwsh") } else { @() }
Assert-ExactHosts -Actions $stageActions.iteration -Script "scripts/test-heavy-targeted-regression.ps1" -Expected $expectedIterationOracle -Context "Iteration self-protection"
Assert-ExactHosts -Actions $stageActions.pre_push -Script "scripts/test-heavy-targeted-regression.ps1" -Expected $expectedPrePushOracle -Context "Pre-push self-protection"
Assert-ExactHosts -Actions $stageActions.release -Script "scripts/test-heavy-targeted-regression.ps1" -Expected $expectedReleaseOracle -Context "Release self-protection"

Write-Output $Result
