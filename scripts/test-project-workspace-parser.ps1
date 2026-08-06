#requires -Version 7.6

[CmdletBinding()]
param(
    [string]$RepoRoot = "",
    [string]$ScratchRoot = "",
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $scriptDir "validation/powershell-runtime-requirement.ps1")
Assert-AgentEcosystemPowerShellRuntime

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent $scriptDir
}

$checkParameters = @{
    RepositoryRoot = [System.IO.Path]::GetFullPath($RepoRoot)
    Json           = $Json.IsPresent
}
if (-not [string]::IsNullOrWhiteSpace($ScratchRoot)) {
    $checkParameters.ScratchRoot = $ScratchRoot
}

& (Join-Path $scriptDir "validation/project-workspace-parser-checks.ps1") @checkParameters
exit $LASTEXITCODE
