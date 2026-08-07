#requires -Version 7.6

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$corePath = Join-Path (Split-Path -Parent $PSCommandPath) "project-workspace.ps1"
$arguments = @{
    Operation = "check"
    ProjectRoot = $ProjectRoot
    Json = $Json
    NoExit = $true
}
$output = @(& $corePath @arguments)
$output | ForEach-Object { Write-Output $_ }
$exitCode = [int]$LASTEXITCODE
exit $exitCode
