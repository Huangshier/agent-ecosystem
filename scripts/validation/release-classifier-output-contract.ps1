[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [AllowNull()]
    [object]$Result
)

$ErrorActionPreference = "Stop"
$knownSelfProtectionReasons = @(
    "full-coverage-unproven",
    "unknown-or-ambiguous-input",
    "self-protection-control-surface",
    "not-tier-3",
    "no-control-plane-change"
)

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
if ($reason -isnot [string] -or [string]::IsNullOrWhiteSpace($reason) -or $knownSelfProtectionReasons -cnotcontains $reason) {
    throw "Classifier property 'heavy_targeted_reason' must be a known self-protection reason."
}

$selfProtection = Get-RequiredPropertyValue -InputObject $Result -Name "run_validation_self_protection"
if ($selfProtection -isnot [bool] -or [bool]$selfProtection -ne [bool]$decision) {
    throw "Classifier self-protection decision must be Boolean and match the compatibility heavy-targeted decision."
}
$selfProtectionReason = Get-RequiredPropertyValue -InputObject $Result -Name "validation_self_protection_reason"
if ($selfProtectionReason -isnot [string] -or [string]::IsNullOrWhiteSpace($selfProtectionReason) -or
    $knownSelfProtectionReasons -cnotcontains $selfProtectionReason -or $selfProtectionReason -cne $reason) {
    throw "Classifier self-protection reason must be known and match the compatibility reason."
}
$controlPlane = Get-RequiredPropertyValue -InputObject $Result -Name "control_plane"
if ($controlPlane -isnot [bool]) {
    throw "Classifier property 'control_plane' must be an actual Boolean."
}
$explicitSelfProtection = Get-RequiredPropertyValue -InputObject $Result -Name "self_protection_required"
if ($explicitSelfProtection -isnot [bool] -or [bool]$explicitSelfProtection -ne [bool]$selfProtection) {
    throw "Classifier property 'self_protection_required' must be Boolean and match the compatibility decision."
}
$explicitSelfProtectionReason = Get-RequiredPropertyValue -InputObject $Result -Name "self_protection_reason"
if ($explicitSelfProtectionReason -isnot [string] -or [string]::IsNullOrWhiteSpace($explicitSelfProtectionReason) -or
    $knownSelfProtectionReasons -cnotcontains $explicitSelfProtectionReason -or $explicitSelfProtectionReason -cne $selfProtectionReason) {
    throw "Classifier property 'self_protection_reason' must be known and match the compatibility reason."
}
if ([bool]$controlPlane -and -not [bool]$selfProtection) {
    throw "A classifier control-plane owner must require self-protection."
}
$requiredSuites = @(Get-RequiredPropertyValue -InputObject $Result -Name "required_suites")
$requiredHosts = @(Get-RequiredPropertyValue -InputObject $Result -Name "required_hosts")
$suiteHostMap = Get-RequiredPropertyValue -InputObject $Result -Name "suite_host_map"
$knownSuites = @("agent-skill-bridge", "bootstrap-safety", "hooks-runtime", "installer-contract", "knowledge-contracts", "project-context-gate", "repository-guards", "release-checkpoint", "runtime-smoke", "template-consistency", "workspace-assets")
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
$conservativeFallback = Get-RequiredPropertyValue -InputObject $Result -Name "conservative_fallback"
if ($conservativeFallback -isnot [bool]) { throw "Classifier property 'conservative_fallback' must be an actual Boolean." }
if ([bool]$conservativeFallback -and ($requiredSuites.Count -eq 0 -or $requiredHosts.Count -eq 0 -or -not [bool]$selfProtection)) {
    throw "Conservative fallback must produce non-empty suites, hosts, and an independent self-protection oracle."
}
if ([int]$Result.detected_tier -eq 3 -and $requiredSuites.Count -eq 0 -and -not [bool]$selfProtection) {
    throw "Tier 3 must execute an affected suite or independent self-protection oracle."
}

$requiredChecksValue = Get-RequiredPropertyValue -InputObject $Result -Name "required_checks"
$skippedChecksValue = Get-RequiredPropertyValue -InputObject $Result -Name "skipped_checks"
if ($requiredChecksValue -is [string] -or $skippedChecksValue -is [string]) { throw "Classifier required_checks and skipped_checks must be arrays." }
$requiredChecks = @($requiredChecksValue)
$skippedChecks = @($skippedChecksValue)
foreach ($field in @(@{ Name = "required_checks"; Value = $requiredChecks }, @{ Name = "skipped_checks"; Value = $skippedChecks })) {
    if (@($field.Value | Where-Object { $_ -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0 -or @($field.Value | Sort-Object -Unique).Count -ne $field.Value.Count) {
        throw "Classifier $($field.Name) must contain unique non-blank strings."
    }
}
if (@($requiredChecks | Where-Object { $skippedChecks -ccontains [string]$_ }).Count -gt 0) { throw "Classifier required_checks and skipped_checks must be disjoint." }
$expectedRequiredChecks = New-Object 'System.Collections.Generic.List[string]'
$expectedSkippedChecks = New-Object 'System.Collections.Generic.List[string]'
foreach ($check in @("change-classification", "diff-check", "document-and-data-parse", "public-safe-scan", "base-guard", "identity-guard")) { $expectedRequiredChecks.Add($check) }
if ([int]$Result.detected_tier -le 1) { $expectedRequiredChecks.Add("quick-repository-checks") } else { $expectedSkippedChecks.Add("quick-repository-checks") }
if ($requiredSuites.Count -gt 0) {
    $expectedRequiredChecks.Add("targeted-module-checks")
    foreach ($suite in @($requiredSuites | Sort-Object -Unique)) { $expectedRequiredChecks.Add("affected-suite:$suite") }
}
else { $expectedSkippedChecks.Add("targeted-module-checks") }
if ([bool]$selfProtection) { $expectedRequiredChecks.Add("validation-self-protection") } else { $expectedSkippedChecks.Add("validation-self-protection") }
$expectedSkippedChecks.Add("full-release-matrix")
if (($requiredChecks -join ',') -cne (@($expectedRequiredChecks.ToArray()) -join ',') -or ($skippedChecks -join ',') -cne (@($expectedSkippedChecks.ToArray()) -join ',')) {
    throw "Classifier required_checks/skipped_checks do not match the affected-suite, self-protection, and PR full-skip plan."
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
