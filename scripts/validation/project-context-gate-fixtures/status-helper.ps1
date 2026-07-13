param(
    [string]$ProjectDir,
    [switch]$Json
)

$casePath = Join-Path $PSScriptRoot "status-case.json"
$case = Get-Content -LiteralPath $casePath -Raw | ConvertFrom-Json
if ($case.stderr) { [Console]::Error.WriteLine([string]$case.stderr) }
switch ([string]$case.behavior) {
    "throw" { throw "CONTEXT_GATE_CONFIDENTIAL_SENTINEL" }
    "nonzero" { [Console]::Error.WriteLine("CONTEXT_GATE_CONFIDENTIAL_SENTINEL"); exit 23 }
    "empty" { return }
    "malformed" { Write-Output '{malformed'; return }
}
if ($case.raw_json) { Write-Output ([string]$case.raw_json); return }
$case.payload | ConvertTo-Json -Depth 8
