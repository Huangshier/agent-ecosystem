[CmdletBinding()]
param(
    [switch]$Json,
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"
$validator = Join-Path $PSScriptRoot "test-validate-change.ps1"
if ($Json.IsPresent -and -not [string]::IsNullOrWhiteSpace($OutputPath)) {
    & $validator -RunTargetedRegression -Json -OutputPath $OutputPath
}
elseif ($Json.IsPresent) {
    & $validator -RunTargetedRegression -Json
}
elseif (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    & $validator -RunTargetedRegression -OutputPath $OutputPath
}
else {
    & $validator -RunTargetedRegression
}
if ($LASTEXITCODE -ne 0) {
    throw "Heavy targeted regression failed with exit code $LASTEXITCODE."
}
