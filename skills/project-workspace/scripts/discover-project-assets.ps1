#requires -Version 7.6

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [AllowEmptyString()][string]$Query = "",
    [ValidateRange(1, 100)][int]$Limit = 5,
    [string[]]$Type = @(),
    [string[]]$Status = @(),
    [switch]$CurrentBranchOnly,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$corePath = Join-Path (Split-Path -Parent $PSCommandPath) "project-workspace.ps1"
$arguments = @{
    Operation = "discover"
    ProjectRoot = $ProjectRoot
    Query = $Query
    Limit = $Limit
    Type = $Type
    Status = $Status
    CurrentBranchOnly = $CurrentBranchOnly
    Json = $Json
    NoExit = $true
}
$output = @(& $corePath @arguments)
$output | ForEach-Object { Write-Output $_ }
$exitCode = [int]$LASTEXITCODE
if ($Json.IsPresent) {
    # Re-run is intentionally avoided; the core already emitted the result.
}
exit $exitCode
