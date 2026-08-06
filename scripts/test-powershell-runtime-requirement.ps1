[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
$requirementScript = Join-Path $PSScriptRoot "validation/powershell-runtime-requirement.ps1"
$fixturePath = Join-Path $PSScriptRoot "validation/powershell-runtime-requirement-fixtures/cases.json"
. $requirementScript

$results = New-Object 'System.Collections.Generic.List[object]'
$cases = Get-Content -LiteralPath $fixturePath -Raw | ConvertFrom-Json
foreach ($case in @($cases)) {
    $accepted = $true
    $errorMessage = ""
    try {
        Assert-AgentEcosystemPowerShellRuntime -Version ([Version][string]$case.version) -Edition ([string]$case.edition)
    }
    catch {
        $accepted = $false
        $errorMessage = $_.Exception.Message
    }

    if ($accepted -ne [bool]$case.accepted) {
        throw "$($case.name) acceptance mismatch."
    }
    if ($errorMessage -cne [string]$case.error) {
        throw "$($case.name) error mismatch: '$errorMessage'."
    }
    $results.Add([ordered]@{ name = [string]$case.name; status = "PASS" })
}

$entrypoints = [ordered]@{
    "scripts/invoke-local-validation.ps1" = '$defaultRepoRoot ='
    "scripts/validate-change.ps1" = '$defaultRepoRoot ='
    "scripts/validate-targeted-change.ps1" = '$repoRoot ='
    "scripts/validate-release.ps1" = '$repoRoot ='
}
$repoRoot = Split-Path -Parent $PSScriptRoot
foreach ($relativePath in $entrypoints.Keys) {
    $source = Get-Content -LiteralPath (Join-Path $repoRoot $relativePath) -Raw
    $helperIndex = $source.IndexOf('validation/powershell-runtime-requirement.ps1', [System.StringComparison]::Ordinal)
    $assertIndex = $source.IndexOf('Assert-AgentEcosystemPowerShellRuntime', [System.StringComparison]::Ordinal)
    $operationalIndex = $source.IndexOf([string]$entrypoints[$relativePath], [System.StringComparison]::Ordinal)
    if ($helperIndex -lt 0 -or $assertIndex -lt $helperIndex -or $operationalIndex -lt 0 -or $assertIndex -gt $operationalIndex) {
        throw "$relativePath does not enforce the PowerShell runtime before operational setup."
    }
    $results.Add([ordered]@{ name = "entrypoint:$relativePath"; status = "PASS" })
}

$summary = [ordered]@{
    schema_version = 1
    pass = $results.Count
    fail = 0
    cases = @($results.ToArray())
}
if ($Json.IsPresent) {
    $summary | ConvertTo-Json -Depth 6
}
else {
    Write-Output ("PowerShell runtime requirement fixtures: PASS={0} FAIL=0" -f $summary.pass)
}
