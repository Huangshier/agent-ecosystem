[CmdletBinding()]
param(
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $PSCommandPath

# -- Regression: stale $LASTEXITCODE after test-validate-change.ps1 ----------
# PR #242 introduced a bug where the invalid-base-ref test inside
# test-validate-change.ps1 left $LASTEXITCODE set to a non-zero value.
# On main push this caused the classify step to fail even though the JSON
# output was perfectly valid.
#
# This script reproduces the exact scenario that broke on main push:
#   1. Run the full classification-test suite (which triggers the git failure)
#   2. Immediately run a plain classifier on a well-known path
#   3. Verify both outputs parse, the classifier result is correct, and
#      $LASTEXITCODE is clean.

Write-Output "=== Phase 1: test-validate-change.ps1 -Json ==="
$testOut = & (Join-Path $scriptDir "test-validate-change.ps1") -Json
if ($LASTEXITCODE -ne 0) { throw "Phase 1: test-validate-change.ps1 exited with LASTEXITCODE=$LASTEXITCODE" }
try {
    $testResult = $testOut | ConvertFrom-Json
    if ([int]$testResult.fail -ne 0) { throw "Phase 1: test-validate-change.ps1 reported failures." }
    Write-Output "Phase 1 PASS: pass=$($testResult.pass) fail=$($testResult.fail)"
} catch {
    throw "Phase 1: test-validate-change.ps1 JSON parse failed: $_"
}

Write-Output "=== Phase 2: validate-change.ps1 -ChangedPath (post-test) ==="
$classifierOut = & (Join-Path $scriptDir "validate-change.ps1") -ChangedPath ".github/workflows/release-validation.yml" -Json
if ($LASTEXITCODE -ne 0) { throw "Phase 2: validate-change.ps1 exited with LASTEXITCODE=$LASTEXITCODE" }
try {
    $classifierResult = $classifierOut | ConvertFrom-Json
    if ([int]$classifierResult.detected_tier -ne 3) {
        throw "Phase 2: expected Tier 3 for release-validation.yml, got Tier $($classifierResult.detected_tier)"
    }
    Write-Output "Phase 2 PASS: tier=$($classifierResult.detected_tier) paths=$($classifierResult.changed_paths -join ',')"
} catch {
    throw "Phase 2: validate-change.ps1 JSON parse or assertion failed: $_"
}

# Additional: verify invalid base ref still conservatively escalates (sanity)
Write-Output "=== Phase 3: invalid base ref conservative escalation ==="
$invalidOut = & (Join-Path $scriptDir "validate-change.ps1") -BaseRef "refs/heads/definitely-missing" -HeadRef HEAD -Json
$invalid = $invalidOut | ConvertFrom-Json
if ([int]$invalid.detected_tier -ne 3 -or [string]$invalid.escalation_reason -notmatch "Classification input") {
    throw "Phase 3: invalid base ref did not conservatively escalate."
}
# Must clean up the stale exit code from the expected git failure, exactly
# as the fix in test-validate-change.ps1 does.
$global:LASTEXITCODE = 0
Write-Output "Phase 3 PASS: invalid base ref correctly escalated to Tier 3"

# -- Final exit-code guard ----------------------------------------------------
if ($LASTEXITCODE -ne 0) { throw "Stale LASTEXITCODE=$LASTEXITCODE at end of regression script." }

# -- Verify that a real assertion failure still produces non-zero exit --------
# This is validated via a separate ephemeral call (not included in the summary)
# to confirm we haven't masked real failures with unconditional exit 0.
Write-Output "=== Phase 4: real assertion failure still non-zero (ephemeral) ==="
$null = & (Join-Path $scriptDir "validate-change.ps1") -BaseRef "refs/heads/definitely-missing" -HeadRef HEAD -Json
# At this point $LASTEXITCODE should be non-zero from the failed git rev-parse
# inside validate-change.ps1 (the validator catches it but the native exit code leaks).
# This confirms that without the explicit reset, the stale code is present.
if ($LASTEXITCODE -eq 0) { throw "Phase 4: expected non-zero LASTEXITCODE after raw invalid-ref call, got 0." }
$global:LASTEXITCODE = 0  # clean up for our own exit

$summary = [ordered]@{
    schema_version = 1
    phase1_test_suite = "PASS"
    phase2_post_test_classifier = "PASS"
    phase3_invalid_ref_escalation = "PASS"
    phase4_raw_stale_code_present = "PASS"
    final_lastexitcode = $LASTEXITCODE
}
if ($Json.IsPresent) {
    $summary | ConvertTo-Json -Depth 4
} else {
    Write-Output "stale-lastexitcode regression: PASS"
}
