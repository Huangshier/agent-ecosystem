[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$writer = Join-Path $PSScriptRoot "validation/write-evidence-manifest.ps1"
$workflowPath = Join-Path $repoRoot ".github/workflows/release-validation.yml"
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-ecosystem-evidence-contract-{0}" -f [Guid]::NewGuid().ToString("N"))
$commitSha = "0123456789abcdef0123456789abcdef01234567"
$checks = New-Object 'System.Collections.Generic.List[object]'

function Assert-Contract([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "Evidence contract fixture failed: $Name" }
    $checks.Add([ordered]@{ name = $Name; status = "PASS" })
}

try {
    New-Item -ItemType Directory -Force -Path (Join-Path $scratch "regenerable-fixture-tree") | Out-Null
    [ordered]@{
        schema_version = 1
        validation_shard = "RuntimePlatform"
        shard_coverage = [ordered]@{ status = "PASS" }
        checks = @([ordered]@{ name = "fixture-check"; status = "PASS"; detail = "fixture"; data = $null; duration_ms = 7 })
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $scratch "validation-result.json") -Encoding UTF8
    '{"output":"fixture"}' | Set-Content -LiteralPath (Join-Path $scratch "validation-output.json") -Encoding UTF8
    [ordered]@{
        telemetry = @([ordered]@{ suite = "fixture-suite"; case = "fixture-case"; host = "fixture-host"; started_at_utc = "2026-01-01T00:00:00Z"; completed_at_utc = "2026-01-01T00:00:00.001Z"; duration_ms = 1; unique_coverage_category = "fixture-coverage" })
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $scratch "targeted-validation-result.json") -Encoding UTF8
    [ordered]@{
        targeted_regression_executed = $true
        targeted_execution = @([ordered]@{ suite = @("fixture-suite"); case = "routing-case"; host = "fixture-host"; started_at_utc = "2026-01-01T00:00:00Z"; completed_at_utc = "2026-01-01T00:00:00.002Z"; duration_ms = 2; unique_coverage_category = "routing-regression:fixture"; status = "PASS" })
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $scratch "change-routing-tests.json") -Encoding UTF8
    "large fixture payload" | Set-Content -LiteralPath (Join-Path $scratch "regenerable-fixture-tree/payload.txt") -Encoding UTF8

    & $writer `
        -ScratchRoot $scratch `
        -Outcome success `
        -CommitSha $commitSha `
        -RunId "123" `
        -RunAttempt "2" `
        -JobName "validate" `
        -HostIdentity "Windows-Core-7.5" `
        -HeavyTargetedStatus executed `
        -HeavyTargetedReason "self-protection-control-surface" `
        -SuccessAllowlist @("validation-result.json", "validation-output.json", "targeted-validation-result.json", "change-routing-tests.json", "evidence-manifest.json") | Out-Null

    $manifestPath = Join-Path $scratch "evidence-manifest.json"
    $manifestText = Get-Content -LiteralPath $manifestPath -Raw
    $manifest = $manifestText | ConvertFrom-Json
    Assert-Contract ($manifest.schema_version -eq 1) "schema-version"
    Assert-Contract ($manifest.identity.commit_sha -ceq $commitSha) "commit-identity"
    Assert-Contract ($manifest.identity.run_id -ceq "123" -and $manifest.identity.run_attempt -ceq "2" -and $manifest.identity.job -ceq "validate" -and $manifest.identity.host -ceq "Windows-Core-7.5") "run-job-host-identity"
    Assert-Contract ($manifest.validation_shard -ceq "RuntimePlatform" -and $manifest.executed.validation_shard -ceq "RuntimePlatform" -and @($manifest.executed.coverage_categories) -contains "release-validator:runtime-platform") "release-shard-evidence"
    Assert-Contract (@($manifest.executed.release_checks).Count -eq 1 -and [long]$manifest.executed.release_checks[0].duration_ms -eq 7) "release-duration"
    Assert-Contract (@($manifest.executed.targeted_suites).Count -eq 1 -and @($manifest.executed.routing_regressions).Count -eq 1) "executed-coverage"
    Assert-Contract ($manifest.heavy_targeted.status -ceq "executed" -and $manifest.heavy_targeted.reason -ceq "self-protection-control-surface" -and @($manifest.heavy_targeted.actual_unique_coverage).Count -eq 1) "heavy-targeted-executed-evidence"
    Assert-Contract (@($manifest.artifact_contract.success.files) -notcontains "regenerable-fixture-tree/payload.txt") "success-excludes-regenerable-tree"
    Assert-Contract ($manifest.artifact_contract.failure.mode -ceq "full-scratch" -and [bool]$manifest.artifact_contract.failure.recursive) "failure-full-scratch"
    Assert-Contract (-not $manifestText.Contains($scratch)) "manifest-omits-local-path"

    $workflow = Get-Content -LiteralPath $workflowPath -Raw
    Assert-Contract (@([regex]::Matches($workflow, "if: success\(\)")).Count -eq 6) "six-success-upload-contracts"
    Assert-Contract (@([regex]::Matches($workflow, "if: failure\(\)")).Count -eq 6) "six-failure-upload-contracts"
    Assert-Contract (-not $workflow.Contains("**/*.json")) "no-recursive-json-allowlist"
    Assert-Contract (@([regex]::Matches($workflow, "write-evidence-manifest\.ps1")).Count -eq 5) "five-manifest-call-sites"
    Assert-Contract (@([regex]::Matches($workflow, 'HeavyTargetedStatus')).Count -eq 2 -and @([regex]::Matches($workflow, 'HeavyTargetedReason')).Count -eq 2) "windows-heavy-decision-manifests"
    Assert-Contract ($workflow.Contains('validation-self-protection.json') -and $workflow.Contains('name: validation-self-protection')) "self-protection-evidence-uploaded"
    Assert-Contract (-not ([regex]::IsMatch($workflow, '(?m)^\s+\$\{\{ runner\.temp \}\}/.*validation-output\.json\s*$'))) "success-excludes-stream-capture"
    Assert-Contract (-not ([regex]::IsMatch($workflow, 'SuccessAllowlist[^\r\n]*validation-output\.json'))) "manifest-success-excludes-stream-capture"
    $failureUploadContracts = @(
        @("name: quick-validation-failure", 'path: ${{ runner.temp }}/agent-ecosystem-quick-validation'),
        @('name: affected-validation-${{ matrix.os }}-failure', 'path: ${{ runner.temp }}/agent-ecosystem-targeted-validation'),
        @('name: validation-self-protection-failure', 'path: ${{ runner.temp }}/agent-ecosystem-validation-self-protection'),
        @('name: validation-platform-neutral-failure', 'path: ${{ runner.temp }}/agent-ecosystem-platform-neutral-validation'),
        @('name: validation-pwsh-${{ matrix.os }}-failure', 'path: ${{ runner.temp }}/agent-ecosystem-release-validation'),
        @("name: validation-windows-powershell-failure", '${{ runner.temp }}/agent-ecosystem-release-validation-windows-powershell')
    )
    foreach ($contract in $failureUploadContracts) {
        Assert-Contract ($workflow.Contains($contract[0]) -and $workflow.Contains($contract[1])) ("failure-upload-root:{0}" -f $contract[0])
    }

    $failureScratch = Join-Path $scratch "failure-case"
    New-Item -ItemType Directory -Force -Path (Join-Path $failureScratch "nested") | Out-Null
    "failure detail" | Set-Content -LiteralPath (Join-Path $failureScratch "nested/detail.log") -Encoding UTF8
    & $writer `
        -ScratchRoot $failureScratch `
        -Outcome failure `
        -CommitSha $commitSha `
        -RunId "124" `
        -RunAttempt "1" `
        -JobName "validate-failure" `
        -HostIdentity "Windows-Desktop-5.1" `
        -SuccessAllowlist @("validation-result.json", "evidence-manifest.json") | Out-Null
    $failureManifest = Get-Content -LiteralPath (Join-Path $failureScratch "evidence-manifest.json") -Raw | ConvertFrom-Json
    Assert-Contract ($failureManifest.outcome -ceq "failure" -and $failureManifest.artifact_contract.failure.preserve_all_generated_files) "failure-policy-fixture"

    $skippedScratch = Join-Path $scratch "skipped-case"
    New-Item -ItemType Directory -Force -Path $skippedScratch | Out-Null
    Copy-Item -LiteralPath (Join-Path $scratch "validation-result.json") -Destination (Join-Path $skippedScratch "validation-result.json")
    & $writer `
        -ScratchRoot $skippedScratch `
        -Outcome success `
        -CommitSha $commitSha `
        -RunId "125" `
        -RunAttempt "1" `
        -JobName "validate-skipped" `
        -HostIdentity "Windows-Core-7.5" `
        -HeavyTargetedStatus skipped `
        -HeavyTargetedReason "tier-3-full-covers-required-suites" `
        -SuccessAllowlist @("validation-result.json", "evidence-manifest.json") | Out-Null
    $skippedManifest = Get-Content -LiteralPath (Join-Path $skippedScratch "evidence-manifest.json") -Raw | ConvertFrom-Json
    Assert-Contract ($skippedManifest.heavy_targeted.status -ceq "skipped" -and @($skippedManifest.heavy_targeted.actual_unique_coverage).Count -eq 0 -and @($skippedManifest.artifact_contract.success.files) -notcontains "change-routing-tests.json") "heavy-targeted-skipped-evidence"

    $contradictionScratch = Join-Path $scratch "contradiction-case"
    New-Item -ItemType Directory -Force -Path $contradictionScratch | Out-Null
    Copy-Item -LiteralPath (Join-Path $scratch "validation-result.json") -Destination (Join-Path $contradictionScratch "validation-result.json")
    $contradictionFailed = $false
    try {
        & $writer -ScratchRoot $contradictionScratch -Outcome success -CommitSha $commitSha -RunId "126" -RunAttempt "1" -JobName "validate-contradiction" -HostIdentity "Windows-Desktop-5.1" -HeavyTargetedStatus executed -HeavyTargetedReason "fixture" -SuccessAllowlist @("validation-result.json", "evidence-manifest.json") | Out-Null
    }
    catch { $contradictionFailed = $true }
    Assert-Contract $contradictionFailed "heavy-targeted-missing-evidence-fails-closed"

    $skippedContradictionScratch = Join-Path $scratch "skipped-contradiction-case"
    New-Item -ItemType Directory -Force -Path $skippedContradictionScratch | Out-Null
    Copy-Item -LiteralPath (Join-Path $scratch "validation-result.json") -Destination (Join-Path $skippedContradictionScratch "validation-result.json")
    Copy-Item -LiteralPath (Join-Path $scratch "change-routing-tests.json") -Destination (Join-Path $skippedContradictionScratch "change-routing-tests.json")
    $skippedContradictionFailed = $false
    try {
        & $writer -ScratchRoot $skippedContradictionScratch -Outcome success -CommitSha $commitSha -RunId "127" -RunAttempt "1" -JobName "validate-skipped-contradiction" -HostIdentity "Windows-Core-7.5" -HeavyTargetedStatus skipped -HeavyTargetedReason "fixture" -SuccessAllowlist @("validation-result.json", "evidence-manifest.json") | Out-Null
    }
    catch { $skippedContradictionFailed = $true }
    Assert-Contract $skippedContradictionFailed "heavy-targeted-skipped-with-evidence-fails-closed"

    $result = [ordered]@{ schema_version = 1; pass = $checks.Count; fail = 0; checks = @($checks.ToArray()) }
    if ($Json.IsPresent) { $result | ConvertTo-Json -Depth 6 } else { Write-Output ("validation evidence contract fixtures: PASS={0} FAIL=0" -f $result.pass) }
}
finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
