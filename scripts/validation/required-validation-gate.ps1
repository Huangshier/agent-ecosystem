[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$EventName,
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Tier,
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$ClassifyResult,
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$QuickResult,
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$TargetedResult,
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$SelfProtectionResult,
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$SelfProtectionRequired,
    [AllowEmptyString()][string]$MainHealthResult = "skipped",
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$PlatformNeutralResult,
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$PwshMatrixResult,
    [switch]$Json
)

$ErrorActionPreference = "Stop"

$knownEvents = @("pull_request", "push", "workflow_dispatch")
$knownTiers = @("0", "1", "2", "3")
$knownResults = @("success", "failure", "cancelled", "skipped")
$results = [ordered]@{
    classify = $ClassifyResult
    quick = $QuickResult
    targeted = $TargetedResult
    self_protection = $SelfProtectionResult
    main_health = $MainHealthResult
    platform_neutral = $PlatformNeutralResult
    pwsh_matrix = $PwshMatrixResult
}

if ($knownEvents -cnotcontains $EventName) {
    throw "Required validation gate received unknown event '$EventName'."
}
if ($knownTiers -cnotcontains $Tier) {
    throw "Required validation gate received missing or invalid Tier '$Tier'."
}
if ($EventName -ceq "workflow_dispatch" -and $Tier -cne "3") {
    throw "Required validation gate requires Tier '3' for checkpoint events, got '$Tier'."
}
$booleanValues = @("true", "false")
if ($booleanValues -cnotcontains $SelfProtectionRequired) {
    throw "Required validation gate received an invalid suite/oracle routing decision."
}
# NOTE: self-protection 只属于验证控制面 PR；main 与手动 Release/checkpoint 不重复运行。
$expectedSelfProtection = if ($SelfProtectionRequired -ceq "true" -and $EventName -ceq "pull_request") { "success" } else { "skipped" }
foreach ($entry in $results.GetEnumerator()) {
    if ($knownResults -cnotcontains [string]$entry.Value) {
        throw "Required validation gate received unknown result '$($entry.Value)' for '$($entry.Key)'."
    }
}

$expected = if ($EventName -ceq "pull_request") {
    switch ($Tier) {
        { $_ -ceq "0" -or $_ -ceq "1" } {
            [ordered]@{ classify = "success"; quick = "success"; targeted = "skipped"; self_protection = $expectedSelfProtection; main_health = "skipped"; platform_neutral = "skipped"; pwsh_matrix = "skipped" }
            break
        }
        "2" {
            [ordered]@{ classify = "success"; quick = "skipped"; targeted = "success"; self_protection = $expectedSelfProtection; main_health = "skipped"; platform_neutral = "skipped"; pwsh_matrix = "skipped" }
            break
        }
        "3" {
            [ordered]@{ classify = "success"; quick = "skipped"; targeted = "success"; self_protection = $expectedSelfProtection; main_health = "skipped"; platform_neutral = "skipped"; pwsh_matrix = "skipped" }
            break
        }
    }
}
elseif ($EventName -ceq "push") {
    [ordered]@{ classify = "success"; quick = "skipped"; targeted = "skipped"; self_protection = $expectedSelfProtection; main_health = "success"; platform_neutral = "skipped"; pwsh_matrix = "skipped" }
}
else {
    [ordered]@{ classify = "success"; quick = "skipped"; targeted = "skipped"; self_protection = "skipped"; main_health = "skipped"; platform_neutral = "success"; pwsh_matrix = "success" }
}

$mismatches = New-Object 'System.Collections.Generic.List[string]'
foreach ($name in $expected.Keys) {
    if ($EventName -ceq "pull_request" -and
        $name -ceq "main_health" -and
        [string]$results[$name] -in @("skipped", "success")) {
        continue
    }
    if ([string]$results[$name] -cne [string]$expected[$name]) {
        $mismatches.Add(("{0}: expected '{1}', got '{2}'" -f $name, $expected[$name], $results[$name]))
    }
}
if ($mismatches.Count -gt 0) {
    throw ("Required validation gate rejected the job routing contract for event '{0}', Tier '{1}': {2}" -f $EventName, $Tier, ($mismatches -join "; "))
}

$output = [ordered]@{
    schema_version = 1
    status = "PASS"
    event_name = $EventName
    tier = $Tier
    results = $results
}
if ($Json.IsPresent) {
    $output | ConvertTo-Json -Depth 4
}
else {
    Write-Output ("Required validation gate passed for event '{0}', Tier '{1}'." -f $EventName, $Tier)
}
