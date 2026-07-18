[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [AllowNull()]
    [object]$Result
)

$ErrorActionPreference = "Stop"

function Get-RequiredPropertyValue {
    param(
        [Parameter(Mandatory = $true)][object]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $property = @($InputObject.PSObject.Properties | Where-Object { $_.Name -ceq $Name })
    if ($property.Count -ne 1) {
        throw "Classifier result is missing required property '$Name'."
    }
    return $property[0].Value
}

function Assert-CoverageSuiteList {
    param(
        [Parameter(Mandatory = $true)][object]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string[]]$Expected
    )

    $value = Get-RequiredPropertyValue -InputObject $InputObject -Name $Name
    if ($null -eq $value -or $value -is [string]) {
        throw "Classifier property '$Name' must be a non-empty suite array."
    }
    $actual = @($value)
    if ($actual.Count -eq 0 -or @($actual | Where-Object { $_ -isnot [string] -or [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
        throw "Classifier property '$Name' must be a non-empty array of non-blank strings."
    }
    if (($actual -join ',') -cne ($Expected -join ',')) {
        throw "Classifier property '$Name' does not match the current heavy targeted coverage contract."
    }
}

if ($null -eq $Result -or $Result -is [string] -or $Result -is [System.Array]) {
    throw "Classifier result must be an object."
}

$decision = Get-RequiredPropertyValue -InputObject $Result -Name "run_heavy_targeted_regression"
if ($decision -isnot [bool]) {
    throw "Classifier property 'run_heavy_targeted_regression' must be an actual Boolean."
}

$reason = Get-RequiredPropertyValue -InputObject $Result -Name "heavy_targeted_reason"
if ($reason -isnot [string] -or [string]::IsNullOrWhiteSpace($reason)) {
    throw "Classifier property 'heavy_targeted_reason' must be a non-blank string."
}

$expectedCoverageSuites = @(
    "agent-skill-bridge",
    "bootstrap-safety",
    "installer-contract",
    "knowledge-contracts",
    "project-context-gate",
    "runtime-smoke"
)
Assert-CoverageSuiteList -InputObject $Result -Name "heavy_targeted_required_suites" -Expected $expectedCoverageSuites
Assert-CoverageSuiteList -InputObject $Result -Name "full_validator_coverage_suites" -Expected $expectedCoverageSuites

$hostedPlan = Get-RequiredPropertyValue -InputObject $Result -Name "hosted_plan"
foreach ($field in @("full_validator_calls", "platform_neutral_validator_calls", "runtime_platform_validator_calls", "targeted_os_jobs")) {
    $value = Get-RequiredPropertyValue -InputObject $hostedPlan -Name $field
    if ($value -isnot [int] -and $value -isnot [long]) {
        throw "Classifier hosted_plan property '$field' must be an integer."
    }
    if ([int]$value -lt 0) {
        throw "Classifier hosted_plan property '$field' must be non-negative."
    }
}
if ([int]$Result.detected_tier -eq 3) {
    if ([int]$hostedPlan.full_validator_calls -ne 0 -or
        [int]$hostedPlan.platform_neutral_validator_calls -ne 1 -or
        [int]$hostedPlan.runtime_platform_validator_calls -ne 4) {
        throw "Tier 3 hosted_plan must route one platform-neutral and four runtime-platform validators without PR/push full calls."
    }
}

Write-Output $Result
