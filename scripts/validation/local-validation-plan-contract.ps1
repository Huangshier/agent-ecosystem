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

if ($null -eq $Result -or $Result -is [string] -or $Result -is [System.Array]) { throw "Classifier result must be an object." }
$tier = Get-RequiredPropertyValue -InputObject $Result -Name "detected_tier"
if ($tier -isnot [int] -and $tier -isnot [long]) { throw "Classifier property 'detected_tier' must be an integer." }
$heavyDecision = Get-RequiredPropertyValue -InputObject $Result -Name "run_heavy_targeted_regression"
if ($heavyDecision -isnot [bool]) { throw "Classifier property 'run_heavy_targeted_regression' must be an actual Boolean." }
$plan = Get-RequiredPropertyValue -InputObject $Result -Name "local_plan"
if ($null -eq $plan -or [int](Get-RequiredPropertyValue -InputObject $plan -Name "schema_version") -ne 1) { throw "Classifier local plan must use schema version 1." }
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
        if (@("current", "pwsh", "windows-powershell") -cnotcontains [string]$action.host) { throw "Local stage '$stageName' uses unsupported host '$($action.host)'." }
        if ([string]$action.script -notmatch '^scripts/[a-z0-9-]+\.ps1$') { throw "Local stage '$stageName' action script is outside the approved scripts boundary." }
    }
    foreach ($skip in @($stage.skipped)) {
        foreach ($name in @("id", "status", "reason")) { Get-RequiredPropertyValue -InputObject $skip -Name $name | Out-Null }
        if ([string]$skip.status -cne "SKIPPED") { throw "Local stage '$stageName' skip records must use SKIPPED status." }
    }
    $stageActions[$stageName] = $actions
}

if (@($stageActions.iteration | Where-Object { [string]$_.script -in @("scripts/validate-release.ps1", "scripts/test-heavy-targeted-regression.ps1") }).Count -gt 0) {
    throw "Iteration must never plan full or heavy validation."
}
Assert-ExactHosts -Actions $stageActions.release -Script "scripts/validate-release.ps1" -Expected @("pwsh", "windows-powershell") -Context "Release local validation"
if ([int]$tier -eq 3) {
    Assert-ExactHosts -Actions $stageActions.pre_push -Script "scripts/validate-release.ps1" -Expected @("pwsh", "windows-powershell") -Context "Tier 3 pre-push validation"
}
else {
    Assert-ExactHosts -Actions $stageActions.pre_push -Script "scripts/validate-release.ps1" -Expected @() -Context "Tier 0-2 pre-push validation"
}
$expectedHeavyHosts = if ([int]$tier -eq 3 -and [bool]$heavyDecision) { @("pwsh", "windows-powershell") } else { @() }
Assert-ExactHosts -Actions $stageActions.pre_push -Script "scripts/test-heavy-targeted-regression.ps1" -Expected $expectedHeavyHosts -Context "Pre-push heavy targeted regression"
Assert-ExactHosts -Actions $stageActions.release -Script "scripts/test-heavy-targeted-regression.ps1" -Expected $expectedHeavyHosts -Context "Release heavy targeted regression"

Write-Output $Result
