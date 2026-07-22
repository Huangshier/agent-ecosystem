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

if ([int](Get-RequiredPropertyValue -InputObject $Result -Name "schema_version") -ne 2) {
    throw "Classifier result must use schema version 2."
}

$decision = Get-RequiredPropertyValue -InputObject $Result -Name "run_heavy_targeted_regression"
if ($decision -isnot [bool]) {
    throw "Classifier property 'run_heavy_targeted_regression' must be an actual Boolean."
}

$reason = Get-RequiredPropertyValue -InputObject $Result -Name "heavy_targeted_reason"
if ($reason -isnot [string] -or [string]::IsNullOrWhiteSpace($reason)) {
    throw "Classifier property 'heavy_targeted_reason' must be a non-blank string."
}

$selfProtection = Get-RequiredPropertyValue -InputObject $Result -Name "run_validation_self_protection"
if ($selfProtection -isnot [bool] -or [bool]$selfProtection -ne [bool]$decision) {
    throw "Classifier self-protection decision must be Boolean and match the compatibility heavy-targeted decision."
}
$selfProtectionReason = Get-RequiredPropertyValue -InputObject $Result -Name "validation_self_protection_reason"
if ($selfProtectionReason -isnot [string] -or [string]::IsNullOrWhiteSpace($selfProtectionReason) -or $selfProtectionReason -cne $reason) {
    throw "Classifier self-protection reason must be non-blank and match the compatibility reason."
}
foreach ($booleanName in @("requires_windows_powershell", "conservative_fallback")) {
    if ((Get-RequiredPropertyValue -InputObject $Result -Name $booleanName) -isnot [bool]) {
        throw "Classifier property '$booleanName' must be an actual Boolean."
    }
}
$requiredWindowsPowerShellSuites = @(Get-RequiredPropertyValue -InputObject $Result -Name "required_windows_powershell_suites")
if ([bool]$Result.requires_windows_powershell -ne ($requiredWindowsPowerShellSuites.Count -gt 0)) {
    throw "Classifier WinPS decision must exactly match its WinPS suite list."
}

$requiredSuites = @(Get-RequiredPropertyValue -InputObject $Result -Name "required_suites")
$requiredHosts = @(Get-RequiredPropertyValue -InputObject $Result -Name "required_hosts")
$suiteHostMap = Get-RequiredPropertyValue -InputObject $Result -Name "suite_host_map"
$knownSuites = @("agent-skill-bridge", "bootstrap-safety", "hooks-runtime", "installer-contract", "knowledge-contracts", "project-context-gate", "repository-guards", "release-checkpoint", "runtime-smoke", "template-consistency")
$knownHosts = @("windows-latest", "ubuntu-latest", "macos-latest")
if (@($requiredHosts | Where-Object { $_ -isnot [string] -or $knownHosts -cnotcontains [string]$_ }).Count -gt 0) {
    throw "Classifier required_hosts contains an unknown or invalid host."
}
foreach ($suite in $requiredSuites) {
    if ($suite -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$suite) -or $knownSuites -cnotcontains [string]$suite) { throw "Classifier required_suites contains an unknown or invalid suite '$suite'." }
    $property = @($suiteHostMap.PSObject.Properties | Where-Object Name -CEQ ([string]$suite))
    if ($property.Count -ne 1 -or @($property[0].Value).Count -eq 0) { throw "Classifier suite '$suite' has no host dependency mapping." }
    foreach ($hostName in @($property[0].Value)) {
        if ($knownHosts -cnotcontains [string]$hostName -or $requiredHosts -cnotcontains [string]$hostName) { throw "Classifier suite '$suite' has an invalid or missing required host '$hostName'." }
    }
}
foreach ($suite in $requiredWindowsPowerShellSuites) {
    if ($requiredSuites -cnotcontains [string]$suite) { throw "Classifier WinPS suite '$suite' is not an affected suite." }
}
if ([bool]$Result.conservative_fallback -and ($requiredSuites.Count -eq 0 -or $requiredHosts.Count -eq 0 -or -not [bool]$selfProtection)) {
    throw "Conservative fallback must produce non-empty suites, hosts, and an independent self-protection oracle."
}
if ([int]$Result.detected_tier -eq 3 -and $requiredSuites.Count -eq 0 -and -not [bool]$selfProtection) {
    throw "Tier 3 must execute an affected suite or independent self-protection oracle."
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
if ([int]$hostedPlan.full_validator_calls -ne 0 -or
    [int]$hostedPlan.platform_neutral_validator_calls -ne 0 -or
    [int]$hostedPlan.runtime_platform_validator_calls -ne 0 -or
    [int]$hostedPlan.targeted_os_jobs -ne @($requiredHosts | Sort-Object -Unique).Count) {
    throw "Classifier hosted_plan must route affected hosts without PR full-validator calls."
}

Write-Output $Result
