[CmdletBinding()]
param(
    [string]$ScratchRoot = "",
    [int]$ContextFileCount = 500,
    [double]$MaxSeconds = 30,
    [switch]$Json
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
$repoRoot = Split-Path -Parent $scriptDir
. (Join-Path $scriptDir "lib/path-guard.ps1")

if ($ContextFileCount -lt 1) {
    throw "ContextFileCount must be greater than zero."
}
if ($MaxSeconds -le 0) {
    throw "MaxSeconds must be greater than zero."
}

if ([string]::IsNullOrWhiteSpace($ScratchRoot)) {
    $ScratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-ecosystem-context-gate-benchmark-{0}" -f (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss"))
}

$scratchFull = [System.IO.Path]::GetFullPath($ScratchRoot).TrimEnd('\', '/')
Assert-NotLiveRuntime -Path $scratchFull
$projectRoot = Join-PathParts $scratchFull "large-context-project"
$contextRoot = Join-PathParts $projectRoot ".agents" "context"
$contextGateScript = Join-PathParts $repoRoot "skills" "project-context-gate" "scripts" "context_gate.ps1"
if (-not (Test-Path -LiteralPath $contextGateScript)) {
    throw "Context gate script not found: $contextGateScript"
}

New-Item -ItemType Directory -Force -Path $projectRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Join-PathParts $projectRoot ".agents") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-PathParts $projectRoot "docs" "specs" "large-context-benchmark") | Out-Null
New-Item -ItemType Directory -Force -Path $contextRoot | Out-Null

Set-Content -LiteralPath (Join-PathParts $projectRoot "AGENTS.md") -Value @"
# Benchmark Project

Primary instructions are in `.agents/AGENTS.md`.
"@ -Encoding UTF8

Set-Content -LiteralPath (Join-PathParts $projectRoot ".agents" "AGENTS.md") -Value @"
# Benchmark Agent Guide

## Project Language Policy
Project memory language: English.
"@ -Encoding UTF8

Set-Content -LiteralPath (Join-PathParts $projectRoot ".agents" "process.txt") -Value @"
Current State
- Benchmark project for context gate performance.

Active Spec
- docs/specs/large-context-benchmark/spec.md
"@ -Encoding UTF8

Set-Content -LiteralPath (Join-PathParts $projectRoot ".agents" "plan.md") -Value @"
# Active Plan

Active Spec
- docs/specs/large-context-benchmark/spec.md
"@ -Encoding UTF8

Set-Content -LiteralPath (Join-PathParts $projectRoot "docs" "specs" "large-context-benchmark" "spec.md") -Value @"
# Spec

- **Title**: Large context benchmark
- **Slug**: large-context-benchmark
- **Status**: Active
"@ -Encoding UTF8

Set-Content -LiteralPath (Join-PathParts $projectRoot "docs" "specs" "large-context-benchmark" "tasks.md") -Value @"
# Tasks

- **Spec**: docs/specs/large-context-benchmark/spec.md
- **Status**: Active
"@ -Encoding UTF8

Set-Content -LiteralPath (Join-PathParts $contextRoot "README.md") -Value @"
# Context

Synthetic context tree for benchmark validation.
"@ -Encoding UTF8

for ($i = 1; $i -le $ContextFileCount; $i++) {
    $bucket = "bucket-{0:D2}" -f ($i % 20)
    $dir = Join-PathParts $contextRoot $bucket
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $path = Join-PathParts $dir ("entry-{0:D4}.md" -f $i)
    Set-Content -LiteralPath $path -Value @"
# Benchmark Context Entry $i

## Summary
Synthetic context entry $i used to measure context gate discovery overhead.

## Keywords
benchmark, context-gate, large-context, entry-$i
"@ -Encoding UTF8
}

$outputPath = Join-PathParts $scratchFull "context-gate-output.json"
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$contextJsonText = & $contextGateScript -ProjectRoot $projectRoot -Gate start -Json -IncludeTemplates
$stopwatch.Stop()
$contextJsonText | Set-Content -LiteralPath $outputPath -Encoding UTF8
$contextPayload = $contextJsonText | ConvertFrom-Json

$includedContextFiles = @($contextPayload.files | Where-Object {
    [string]$_.path -like ("{0}*" -f $contextRoot)
})
$elapsedSeconds = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 3)
$passed = ($elapsedSeconds -le $MaxSeconds -and $includedContextFiles.Count -ge $ContextFileCount)

$result = [ordered]@{
    schema_version = 1
    project_root = $projectRoot
    context_file_count = $ContextFileCount
    included_context_files = $includedContextFiles.Count
    elapsed_seconds = $elapsedSeconds
    max_seconds = $MaxSeconds
    context_gate_output = $outputPath
    passed = [bool]$passed
}

if ($Json.IsPresent) {
    $result | ConvertTo-Json -Depth 8
}
else {
    Write-Output ("Context gate benchmark: {0} files included in {1}s (threshold {2}s)." -f $includedContextFiles.Count, $elapsedSeconds, $MaxSeconds)
    Write-Output "Output: $outputPath"
}

if (-not $passed) {
    if ($elapsedSeconds -gt $MaxSeconds) {
        throw ("Context gate benchmark exceeded threshold: {0}s > {1}s" -f $elapsedSeconds, $MaxSeconds)
    }
    throw ("Context gate benchmark included {0} context files; expected at least {1}." -f $includedContextFiles.Count, $ContextFileCount)
}
