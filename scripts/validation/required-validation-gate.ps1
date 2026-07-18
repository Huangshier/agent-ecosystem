[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$EventName,
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Tier,
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$ClassifyResult,
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$QuickResult,
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$TargetedResult,
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$PlatformNeutralResult,
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$PwshMatrixResult,
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$WindowsPowerShellResult,
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
    platform_neutral = $PlatformNeutralResult
    pwsh_matrix = $PwshMatrixResult
    windows_powershell = $WindowsPowerShellResult
}

if ($knownEvents -cnotcontains $EventName) {
    throw "Required validation gate received unknown event '$EventName'."
}
if ($knownTiers -cnotcontains $Tier) {
    throw "Required validation gate received missing or invalid Tier '$Tier'."
}
if ($EventName -ceq "workflow_dispatch" -and $Tier -cne "3") {
    throw "Required validation gate requires Tier '3' for workflow_dispatch, got '$Tier'."
}
foreach ($entry in $results.GetEnumerator()) {
    if ($knownResults -cnotcontains [string]$entry.Value) {
        throw "Required validation gate received unknown result '$($entry.Value)' for '$($entry.Key)'."
    }
}

$expected = if ($EventName -ceq "pull_request" -or $EventName -ceq "push") {
    switch ($Tier) {
        { $_ -ceq "0" -or $_ -ceq "1" } {
            [ordered]@{ classify = "success"; quick = "success"; targeted = "skipped"; platform_neutral = "skipped"; pwsh_matrix = "skipped"; windows_powershell = "skipped" }
            break
        }
        "2" {
            [ordered]@{ classify = "success"; quick = "skipped"; targeted = "success"; platform_neutral = "skipped"; pwsh_matrix = "skipped"; windows_powershell = "skipped" }
            break
        }
        "3" {
            [ordered]@{ classify = "success"; quick = "skipped"; targeted = "skipped"; platform_neutral = "success"; pwsh_matrix = "success"; windows_powershell = "success" }
            break
        }
    }
}
else {
    [ordered]@{ classify = "success"; quick = "skipped"; targeted = "skipped"; platform_neutral = "skipped"; pwsh_matrix = "success"; windows_powershell = "success" }
}

$mismatches = New-Object 'System.Collections.Generic.List[string]'
foreach ($name in $expected.Keys) {
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
