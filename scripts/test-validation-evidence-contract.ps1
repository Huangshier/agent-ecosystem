[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$writer = Join-Path $PSScriptRoot "validation/write-evidence-manifest.ps1"
$candidateFixture = Join-Path $PSScriptRoot "test-exact-candidate-contract.ps1"
$workflowPath = Join-Path $repoRoot ".github/workflows/release-validation.yml"
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-ecosystem-evidence-contract-{0}" -f [Guid]::NewGuid().ToString("N"))
$commitSha = "0123456789abcdef0123456789abcdef01234567"
$checks = New-Object 'System.Collections.Generic.List[object]'

function Assert-Contract([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "Evidence contract fixture failed: $Name" }
    $checks.Add([ordered]@{ name = $Name; status = "PASS" }) | Out-Null
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
        telemetry = @([ordered]@{ suite = "fixture-telemetry-alias"; case = "fixture-case"; host = "fixture-host"; started_at_utc = "2026-01-01T00:00:00Z"; completed_at_utc = "2026-01-01T00:00:00.001Z"; duration_ms = 1; unique_coverage_category = "fixture-coverage" })
        executed_suites = @("fixture-suite")
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $scratch "targeted-validation-result.json") -Encoding UTF8
    [ordered]@{
        targeted_regression_executed = $true
        targeted_execution = @([ordered]@{ suite = @("fixture-suite"); case = "routing-case"; host = "fixture-host"; started_at_utc = "2026-01-01T00:00:00Z"; completed_at_utc = "2026-01-01T00:00:00.002Z"; duration_ms = 2; unique_coverage_category = "routing-regression:fixture"; status = "PASS" })
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $scratch "change-routing-tests.json") -Encoding UTF8
    "large fixture payload" | Set-Content -LiteralPath (Join-Path $scratch "regenerable-fixture-tree/payload.txt") -Encoding UTF8

    & $writer -ScratchRoot $scratch -Outcome success -CommitSha $commitSha -RunId "123" -RunAttempt "2" -JobName "validate" -HostIdentity "Windows-Core-7.5" -Repository "Huangshier/agent-ecosystem" -EventName workflow_dispatch -HeavyTargetedStatus executed -HeavyTargetedReason "self-protection-control-surface" -SuccessAllowlist @("validation-result.json", "validation-output.json", "targeted-validation-result.json", "change-routing-tests.json", "evidence-manifest.json") | Out-Null

    $manifestPath = Join-Path $scratch "evidence-manifest.json"
    $manifestText = Get-Content -LiteralPath $manifestPath -Raw
    $manifest = $manifestText | ConvertFrom-Json
    Assert-Contract ($manifest.schema_version -eq 2 -and $manifest.proof_kind -ceq "validation-fragment") "schema-version"
    Assert-Contract ($manifest.repository -ceq "Huangshier/agent-ecosystem" -and $manifest.event_name -ceq "workflow_dispatch") "repository-event-identity"
    Assert-Contract (@($manifest.artifact_digests).Count -eq 4) "fragment-artifact-digests"
    Assert-Contract ($manifest.identity.commit_sha -ceq $commitSha) "commit-identity"
    Assert-Contract ($manifest.identity.run_id -ceq "123" -and $manifest.identity.run_attempt -eq "2" -and $manifest.identity.job -ceq "validate" -and $manifest.identity.host -ceq "Windows-Core-7.5") "run-job-host-identity"
    Assert-Contract ($manifest.validation_shard -ceq "RuntimePlatform" -and $manifest.executed.validation_shard -ceq "RuntimePlatform" -and @($manifest.executed.coverage_categories) -contains "release-validator:runtime-platform") "release-shard-evidence"
    Assert-Contract (@($manifest.executed.release_checks).Count -eq 1 -and [long]$manifest.executed.release_checks[0].duration_ms -eq 7) "release-duration"
    Assert-Contract (@($manifest.executed.targeted_suites).Count -eq 1 -and @($manifest.executed.targeted_suite_names) -contains "fixture-suite" -and @($manifest.executed.routing_regressions).Count -eq 1) "executed-coverage"
    Assert-Contract ($manifest.heavy_targeted.status -ceq "executed" -and $manifest.heavy_targeted.reason -ceq "self-protection-control-surface" -and @($manifest.heavy_targeted.actual_unique_coverage).Count -eq 1) "heavy-targeted-executed-evidence"
    Assert-Contract (@($manifest.artifact_contract.success.files) -notcontains "regenerable-fixture-tree/payload.txt") "success-excludes-regenerable-tree"
    Assert-Contract ($manifest.artifact_contract.failure.mode -ceq "full-scratch" -and [bool]$manifest.artifact_contract.failure.recursive) "failure-full-scratch"
    Assert-Contract (-not $manifestText.Contains($scratch)) "manifest-omits-local-path"

    foreach ($validationShard in @("Full", "PlatformNeutral", "RuntimePlatform", "RepositoryCheckpoint", "RepositoryCheckpointNeutral", "RepositoryCheckpointRuntime")) {
        $shardScratch = Join-Path $scratch ("recognized-shard-{0}" -f $validationShard)
        New-Item -ItemType Directory -Force -Path $shardScratch | Out-Null
        [ordered]@{
            schema_version = 1
            validation_shard = $validationShard
            shard_coverage = [ordered]@{ status = "PASS" }
            checks = @([ordered]@{ name = "fixture-check"; status = "PASS"; detail = "fixture"; data = $null; duration_ms = 1 })
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $shardScratch "validation-result.json") -Encoding UTF8
        & $writer -ScratchRoot $shardScratch -Outcome success -CommitSha $commitSha -RunId "shard-$validationShard" -RunAttempt "1" -JobName "validate-shard" -HostIdentity "fixture-host" -EventName workflow_dispatch -SuccessAllowlist @("validation-result.json", "evidence-manifest.json") | Out-Null
        $shardManifest = Get-Content -LiteralPath (Join-Path $shardScratch "evidence-manifest.json") -Raw | ConvertFrom-Json
        Assert-Contract ($shardManifest.validation_shard -ceq $validationShard -and $shardManifest.executed.validation_shard -ceq $validationShard) ("recognized-validation-shard:{0}" -f $validationShard)
    }

    $unknownShardScratch = Join-Path $scratch "unknown-shard"
    New-Item -ItemType Directory -Force -Path $unknownShardScratch | Out-Null
    [ordered]@{
        schema_version = 1
        validation_shard = "FutureUnknownShard"
        shard_coverage = [ordered]@{ status = "PASS" }
        checks = @()
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $unknownShardScratch "validation-result.json") -Encoding UTF8
    $unknownShardFailed = $false
    try {
        & $writer -ScratchRoot $unknownShardScratch -Outcome success -CommitSha $commitSha -RunId "unknown-shard" -RunAttempt "1" -JobName "validate-shard" -HostIdentity "fixture-host" -EventName workflow_dispatch -SuccessAllowlist @("validation-result.json", "evidence-manifest.json") | Out-Null
    }
    catch { $unknownShardFailed = $true }
    Assert-Contract $unknownShardFailed "unknown-validation-shard-fails-closed"

    $workflow = Get-Content -LiteralPath $workflowPath -Raw
    $writerSource = Get-Content -LiteralPath $writer -Raw
    Assert-Contract (-not $writerSource.Contains("CandidateContractPath") -and -not $writerSource.Contains("pull_request") -and -not $writerSource.Contains("candidate =")) "release-writer-no-pr-candidate-branch"
    Assert-Contract (@([regex]::Matches($workflow, "if: success\(\)")).Count -eq 2) "release-success-upload-contracts"
    Assert-Contract (@([regex]::Matches($workflow, "if: failure\(\)")).Count -eq 2) "release-failure-upload-contracts"
    Assert-Contract (-not $workflow.Contains("**/*.json")) "no-recursive-json-allowlist"
    Assert-Contract (@([regex]::Matches($workflow, "write-evidence-manifest\.ps1")).Count -eq 2) "release-manifest-call-sites"
    Assert-Contract (-not $workflow.Contains("schedule:")) "no-weekly-schedule"
    foreach ($retiredMarker in @("canonical-candidate-evidence", "main-lineage-shadow", "finalize-candidate-evidence.ps1", "lineage-verifier.ps1", "actions/download-artifact", "final-gate.json", "quick-validation-attempt-", "affected-validation-", "validation-self-protection-attempt-")) {
        Assert-Contract (-not $workflow.Contains($retiredMarker)) ("retired-workflow-surface:{0}" -f $retiredMarker)
    }
    foreach ($jobName in @("quick-validation", "targeted-validation", "validation-self-protection")) {
        $jobPattern = "(?ms)^  " + $jobName + ":\s*\r?\n(?<body>.*?)(?=^  [a-zA-Z0-9_-]+:\s*\r?$|\z)"
        $jobMatch = [regex]::Match($workflow, $jobPattern)
        Assert-Contract ($jobMatch.Success -and -not $jobMatch.Groups["body"].Value.Contains("write-evidence-manifest") -and -not $jobMatch.Groups["body"].Value.Contains("upload-artifact")) ("ordinary-job-no-evidence:{0}" -f $jobName)
    }
    $selfProtectionJob = [regex]::Match($workflow, '(?ms)^  validation-self-protection:\s*\r?\n(?<body>.*?)(?=^  [a-zA-Z0-9_-]+:\s*\r?$|\z)').Groups["body"].Value
    Assert-Contract ($selfProtectionJob.Contains("github.event_name == 'pull_request'") -and $selfProtectionJob.Contains("needs.classify.outputs.run_validation_self_protection == 'true'") -and -not $selfProtectionJob.Contains("github.event_name == 'push'")) "self-protection-pr-only"
    Assert-Contract (@([regex]::Matches($workflow, "resolve-pull-request-candidate\.ps1")).Count -eq 4 -and @([regex]::Matches($workflow, "ExpectedCandidateSha")).Count -eq 3) "direct-candidate-identity-only"
    Assert-Contract ($workflow.Contains("name: validation gate") -and $workflow.Contains("if: always()") -and -not $workflow.Contains("Write current-generation final gate evidence")) "thin-fixed-gate"
    $triggerBlock = [regex]::Match($workflow, '(?ms)^on:\s*\r?\n(?<body>.*?)(?=^permissions:)').Groups["body"].Value
    Assert-Contract (-not $triggerBlock.Contains("schedule") -and $triggerBlock.Contains("workflow_dispatch")) "manual-only-checkpoint-trigger"
    Assert-Contract ($workflow.Contains('$shard = "RepositoryCheckpointNeutral"') -and $workflow.Contains('$shard = "RepositoryCheckpointRuntime"')) "manual-checkpoint-shards-retained"
    Assert-Contract ($workflow.Contains("windows-latest") -and $workflow.Contains("ubuntu-latest") -and $workflow.Contains("macos-latest")) "runtime-checkpoint-hosts-retained"
    foreach ($guardWorkflowName in @("pr-base-guard.yml", "pr-identity-guard.yml")) {
        $guardWorkflow = [System.IO.File]::ReadAllText((Join-Path $repoRoot ".github/workflows/$guardWorkflowName"))
        Assert-Contract ($guardWorkflow.Contains("- edited") -and $guardWorkflow.Contains("- ready_for_review")) ("guard-metadata-independence:{0}" -f $guardWorkflowName)
    }

    $candidateResult = & $candidateFixture -Json | ConvertFrom-Json
    Assert-Contract ([int]($candidateResult.fail) -eq 0 -and [int]$candidateResult.pass -ge 4) "exact-candidate-fixtures"
    Assert-Contract (
        @($candidateResult.cases | Where-Object {
            [string]$_.name -ceq "real-git-digest-parity" -and
            [string]$_.status -ceq "PASS" -and
            (@($_.candidate_ordered_change_digests) -join ",") -ceq (@($_.rebase_landed_ordered_change_digests) -join ",") -and
            [string]$_.candidate_combined_digest -ceq [string]$_.squash_combined_digest
        }).Count -eq 1
    ) "exact-candidate-real-git-parity"

    $result = [ordered]@{ schema_version = 1; pass = $checks.Count; fail = 0; checks = @($checks.ToArray()) }
    if ($Json.IsPresent) { $result | ConvertTo-Json -Depth 6 } else { Write-Output ("validation evidence contract fixtures: PASS={0} FAIL=0" -f $result.pass) }
}
finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
