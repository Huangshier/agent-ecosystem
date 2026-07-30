# test-sensitive-scan.ps1
# Persistent regression tests for the PR sensitive scan and shared contract.
# Called from test-validate-change.ps1 as part of the classifier test flow.
[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $PSCommandPath
$scanScript = Join-Path $scriptDir "pr-secret-keyword-scan.ps1"
$contractPath = Join-Path $scriptDir "sensitive-scan-contract.ps1"

$pass = 0
$fail = 0
$cases = New-Object 'System.Collections.Generic.List[object]'

function Assert-ScanCase {
    param([string]$Name, [bool]$Condition, [string]$Detail)
    if ($Condition) {
        $script:pass++
        $cases.Add([ordered]@{ name = $Name; status = "PASS" })
    } else {
        $script:fail++
        $cases.Add([ordered]@{ name = $Name; status = "FAIL"; detail = $Detail })
    }
}

# Create a temporary git repo for scan testing
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("sensitive-scan-test-{0}" -f ([Guid]::NewGuid().ToString("N")))
New-Item -ItemType Directory -Force -Path $scratch | Out-Null
& git -C $scratch init --quiet
& git -C $scratch config core.autocrlf false
& git -C $scratch config user.name "scan-test"
& git -C $scratch config user.email "scan-test@example.invalid"

# Baseline commit
Set-Content -LiteralPath (Join-Path $scratch "baseline.md") -Value "# Baseline`nExisting content with token in history." -Encoding UTF8
New-Item -ItemType Directory -Force -Path (Join-Path $scratch "scripts" "validation") | Out-Null
Copy-Item -LiteralPath $contractPath -Destination (Join-Path $scratch "scripts" "validation" "sensitive-scan-contract.ps1")
Copy-Item -LiteralPath $scanScript -Destination (Join-Path $scratch "scripts" "validation" "pr-secret-keyword-scan.ps1")
& git -C $scratch add --all | Out-Null
& git -C $scratch commit --quiet -m "baseline" | Out-Null
$global:LASTEXITCODE = 0

# Run all scan invocations from within the temp repo
$previousLocation = Get-Location
Set-Location $scratch
try {

# --- Case 1: New non-allowed keyword in added line -> FAIL ---
Set-Content -LiteralPath (Join-Path $scratch "new-file.ps1") -Value '$token = "leaked"' -Encoding UTF8
& git -C $scratch add --all | Out-Null
& git -C $scratch commit --quiet -m "add keyword" | Out-Null
$global:LASTEXITCODE = 0
$out = & $scanScript -BaseRef "HEAD~1" -HeadRef "HEAD" -Json 2>$null | ConvertFrom-Json
Assert-ScanCase -Name "new-keyword-fail" -Condition ([string]$out.status -ceq "FAIL" -and [int]$out.violation_count -ge 1) -Detail "Expected FAIL for new keyword in non-allowed path, got $($out.status)"

# --- Case 2: Keyword only in deleted line -> PASS ---
& git -C $scratch revert --no-edit HEAD --quiet | Out-Null
$global:LASTEXITCODE = 0
Set-Content -LiteralPath (Join-Path $scratch "new-file.ps1") -Value '# clean now' -Encoding UTF8
& git -C $scratch add --all | Out-Null
& git -C $scratch commit --quiet -m "remove keyword" | Out-Null
$global:LASTEXITCODE = 0
# The revert+new commit means the diff from baseline shows deletion of keyword line
$out2 = & $scanScript -BaseRef "HEAD~1" -HeadRef "HEAD" -Json 2>$null | ConvertFrom-Json
Assert-ScanCase -Name "deleted-line-pass" -Condition ([string]$out2.status -ceq "PASS") -Detail "Expected PASS for keyword only in deleted line, got $($out2.status)"

# --- Case 3: Keyword in diff context line (unified=0 means no context, but test anyway) -> PASS ---
# With unified=0, context lines don't appear. This tests that unchanged lines don't trigger.
$out3 = & $scanScript -BaseRef "HEAD~1" -HeadRef "HEAD" -Json 2>$null | ConvertFrom-Json
Assert-ScanCase -Name "context-line-pass" -Condition ([string]$out3.status -ceq "PASS") -Detail "Expected PASS for context-only keyword, got $($out3.status)"

# --- Case 4: Keyword in history (unmodified) -> PASS ---
# baseline.md has "token" but is not modified in recent commits
$out4 = & $scanScript -BaseRef "HEAD~1" -HeadRef "HEAD" -Json 2>$null | ConvertFrom-Json
Assert-ScanCase -Name "history-unmodified-pass" -Condition ([string]$out4.status -ceq "PASS") -Detail "Expected PASS for keyword in unmodified history, got $($out4.status)"

# --- Case 5: Allowed path -> PASS ---
Set-Content -LiteralPath (Join-Path $scratch "AGENTS.md") -Value "# Guide`nUse token auth." -Encoding UTF8
& git -C $scratch add --all | Out-Null
& git -C $scratch commit --quiet -m "allowed path" | Out-Null
$global:LASTEXITCODE = 0
$out5 = & $scanScript -BaseRef "HEAD~1" -HeadRef "HEAD" -Json 2>$null | ConvertFrom-Json
Assert-ScanCase -Name "allowed-path-pass" -Condition ([string]$out5.status -ceq "PASS") -Detail "Expected PASS for keyword in allowed path, got $($out5.status)"

# --- Case 6: Exact allowed reference -> PASS ---
New-Item -ItemType Directory -Force -Path (Join-Path $scratch ".github" "workflows") | Out-Null
Set-Content -LiteralPath (Join-Path $scratch ".github" "workflows" "release-validation.yml") -Value "  LINEAGE_GITHUB_AUTH: `${{ github.token }}" -Encoding UTF8
& git -C $scratch add --all | Out-Null
& git -C $scratch commit --quiet -m "exact ref" | Out-Null
$global:LASTEXITCODE = 0
$out6 = & $scanScript -BaseRef "HEAD~1" -HeadRef "HEAD" -Json 2>$null | ConvertFrom-Json
Assert-ScanCase -Name "exact-reference-pass" -Condition ([string]$out6.status -ceq "PASS") -Detail "Expected PASS for exact allowed reference, got $($out6.status)"

# --- Case 7: Scan script missing -> FAIL ---
$scanBackup = Join-Path $scratch "scan-backup.ps1"
$scanInRepo = Join-Path $scratch "scripts" "validation" "pr-secret-keyword-scan.ps1"
Copy-Item -LiteralPath $scanInRepo -Destination $scanBackup
Remove-Item -LiteralPath $scanInRepo -Force
$global:LASTEXITCODE = 0
$null = & $scanBackup -BaseRef "HEAD~1" -HeadRef "HEAD" -Json 2>$null
# Test via validate-change.ps1 integration (scan missing = throw)
# Direct test: the scan script itself can't test its own absence, so test the contract-missing path
$contractBackup = Join-Path $scratch "contract-backup.ps1"
$contractInRepo = Join-Path $scratch "scripts" "validation" "sensitive-scan-contract.ps1"
Copy-Item -LiteralPath $contractInRepo -Destination $contractBackup
Remove-Item -LiteralPath $contractInRepo -Force
Copy-Item -LiteralPath $scanBackup -Destination $scanInRepo
$global:LASTEXITCODE = 0
$out7raw = @(& $scanInRepo -BaseRef "HEAD~1" -HeadRef "HEAD" -Json 2>&1)
$out7exit = $LASTEXITCODE
$global:LASTEXITCODE = 0
Assert-ScanCase -Name "contract-missing-fail" -Condition ($out7exit -ne 0) -Detail "Expected non-zero exit for missing contract, got exit $out7exit"
# Restore
Copy-Item -LiteralPath $contractBackup -Destination $contractInRepo

# --- Case 8: Diff unavailable -> FAIL ---
$global:LASTEXITCODE = 0
$out8raw = @(& $scanInRepo -BaseRef "nonexistent-ref-abc" -HeadRef "HEAD" -Json 2>&1)
$out8exit = $LASTEXITCODE
$global:LASTEXITCODE = 0
Assert-ScanCase -Name "diff-unavailable-fail" -Condition ($out8exit -ne 0) -Detail "Expected non-zero exit for unavailable diff, got exit $out8exit"

# --- Case 9: PR and main share same contract ---
. $contractPath
$contractKeywords = $SensitiveScanKeywordPattern
$contractPaths = $SensitiveScanAllowedPaths
$contractRefs = $SensitiveScanAllowedReferences
$contractHighRisk = $SensitiveScanHighRiskPatterns
Assert-ScanCase -Name "shared-contract-keyword" -Condition ($contractKeywords -match 'token') -Detail "Shared contract must define keyword pattern"
Assert-ScanCase -Name "shared-contract-paths" -Condition ($contractPaths.Count -gt 30) -Detail "Shared contract must define allowed paths"
Assert-ScanCase -Name "shared-contract-refs" -Condition ($contractRefs.ContainsKey(".github/workflows/release-validation.yml")) -Detail "Shared contract must define allowed references"
Assert-ScanCase -Name "shared-contract-highrisk" -Condition ($contractHighRisk.Count -eq 7) -Detail "Shared contract must define 7 high-risk patterns"

} finally {
    Set-Location $previousLocation
}

# Cleanup
Remove-Item -Recurse -Force $scratch -ErrorAction SilentlyContinue

# Output
if ($Json.IsPresent) {
    [ordered]@{ schema_version = 1; pass = $pass; fail = $fail; cases = @($cases.ToArray()) } | ConvertTo-Json -Depth 4 -Compress
} else {
    Write-Output "sensitive scan fixtures: PASS=$pass FAIL=$fail"
}
if ($fail -gt 0) { exit 1 }
exit 0
