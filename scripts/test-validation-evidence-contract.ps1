[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$writer = Join-Path $PSScriptRoot "validation/write-evidence-manifest.ps1"
$finalizer = Join-Path $PSScriptRoot "validation/finalize-candidate-evidence.ps1"
$candidateFixture = Join-Path $PSScriptRoot "test-exact-candidate-contract.ps1"
$lineageFixtureScript = Join-Path $PSScriptRoot "test-lineage-verifier.ps1"
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
    Assert-Contract ($manifest.schema_version -eq 2 -and $manifest.proof_kind -ceq "validation-fragment") "schema-version"
    Assert-Contract ($manifest.repository -ceq "Huangshier/agent-ecosystem" -and $manifest.event_name -ceq "fixture") "repository-event-identity"
    Assert-Contract (@($manifest.artifact_digests).Count -eq 4) "fragment-artifact-digests"
    Assert-Contract ($manifest.identity.commit_sha -ceq $commitSha) "commit-identity"
    Assert-Contract ($manifest.identity.run_id -ceq "123" -and $manifest.identity.run_attempt -ceq "2" -and $manifest.identity.job -ceq "validate" -and $manifest.identity.host -ceq "Windows-Core-7.5") "run-job-host-identity"
    Assert-Contract ($manifest.validation_shard -ceq "RuntimePlatform" -and $manifest.executed.validation_shard -ceq "RuntimePlatform" -and @($manifest.executed.coverage_categories) -contains "release-validator:runtime-platform") "release-shard-evidence"
    Assert-Contract (@($manifest.executed.release_checks).Count -eq 1 -and [long]$manifest.executed.release_checks[0].duration_ms -eq 7) "release-duration"
    Assert-Contract (@($manifest.executed.targeted_suites).Count -eq 1 -and @($manifest.executed.routing_regressions).Count -eq 1) "executed-coverage"
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
        & $writer -ScratchRoot $shardScratch -Outcome success -CommitSha $commitSha -RunId "shard-$validationShard" -RunAttempt "1" -JobName "validate-shard" -HostIdentity "fixture-host" -SuccessAllowlist @("validation-result.json", "evidence-manifest.json") | Out-Null
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
        & $writer -ScratchRoot $unknownShardScratch -Outcome success -CommitSha $commitSha -RunId "unknown-shard" -RunAttempt "1" -JobName "validate-shard" -HostIdentity "fixture-host" -SuccessAllowlist @("validation-result.json", "evidence-manifest.json") | Out-Null
    }
    catch { $unknownShardFailed = $true }
    Assert-Contract $unknownShardFailed "unknown-validation-shard-fails-closed"

    $workflow = Get-Content -LiteralPath $workflowPath -Raw
    Assert-Contract (@([regex]::Matches($workflow, "if: success\(\)")).Count -eq 6) "six-success-upload-contracts"
    Assert-Contract (@([regex]::Matches($workflow, "if: failure\(\)")).Count -eq 6) "six-failure-upload-contracts"
    Assert-Contract (-not $workflow.Contains("**/*.json")) "no-recursive-json-allowlist"
    Assert-Contract (@([regex]::Matches($workflow, "write-evidence-manifest\.ps1")).Count -eq 6) "six-manifest-call-sites"
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

    $candidateBase = "1111111111111111111111111111111111111111"
    $candidateHead = "2222222222222222222222222222222222222222"
    $candidateContractPath = Join-Path $scratch "candidate-contract.json"
    [ordered]@{
        schema_version = 1
        repository = "Huangshier/agent-ecosystem"
        pr_number = 77
        base = [ordered]@{ ref = "main"; sha = $candidateBase }
        head = [ordered]@{
            ref = "feature"; sha = $candidateHead; merge_base = $candidateBase
            commit_sequence = @($candidateHead); ordered_change_digests = @("patch-1")
        }
        candidate = [ordered]@{
            sha = $commitSha; tree = "3333333333333333333333333333333333333333"
            ordered_parents = @($candidateBase, $candidateHead); source = "refs/pull/77/merge"
        }
        change = [ordered]@{ combined_digest = "combined-1"; paths = @("M`tREADME.md") }
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $candidateContractPath -Encoding UTF8
    $classificationPath = Join-Path $scratch "canonical-classification.json"
    [ordered]@{
        schema_version = 2; detected_tier = 2; affected_modules = @("docs")
        conservative_fallback = $false; escalation_reason = ""
        base_ref = $candidateBase; head_ref = $candidateHead
        required_suites = @("fixture-suite"); required_hosts = @("ubuntu-latest")
        requires_windows_powershell = $false; run_validation_self_protection = $false
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $classificationPath -Encoding UTF8
    $fragmentRoot = Join-Path $scratch "canonical-fragments"
    $fragmentScratch = Join-Path $fragmentRoot "affected-validation-ubuntu-latest"
    New-Item -ItemType Directory -Force -Path $fragmentScratch | Out-Null
    Copy-Item -LiteralPath (Join-Path $scratch "targeted-validation-result.json") -Destination (Join-Path $fragmentScratch "targeted-validation-result.json")
    & $writer -ScratchRoot $fragmentScratch -Outcome success -CommitSha $commitSha -RunId "123" -RunAttempt "2" `
        -JobName "targeted-validation" -HostIdentity "Linux-Core-7.5" -Repository "Huangshier/agent-ecosystem" `
        -EventName pull_request -CandidateContractPath $candidateContractPath `
        -SuccessAllowlist @("targeted-validation-result.json", "evidence-manifest.json") | Out-Null
    $bindingPath = Join-Path $scratch "guard-gate-binding.json"
    $binding = [ordered]@{
        schema_version = 1
        base_guard = [ordered]@{ run_id = "201"; run_attempt = "2"; job_id = "301"; check_name = "base"; conclusion = "success"; head_sha = $candidateHead; pr_number = 77 }
        identity_guard = [ordered]@{ run_id = "202"; run_attempt = "2"; job_id = "302"; check_name = "identity"; conclusion = "success"; head_sha = $candidateHead; pr_number = 77 }
        final_gate = [ordered]@{ run_id = "123"; run_attempt = "2"; job_id = "303"; check_name = "validation gate"; conclusion = "success"; head_sha = $candidateHead; pr_number = 77 }
    }
    $binding | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $bindingPath -Encoding UTF8
    $canonicalPath = Join-Path $scratch "canonical-evidence.json"
    & $finalizer -CandidateContractPath $candidateContractPath -ClassificationPath $classificationPath `
        -FragmentsRoot $fragmentRoot -GuardBindingPath $bindingPath -Repository "Huangshier/agent-ecosystem" `
        -RunId "123" -RunAttempt "2" -WorkflowIdentity ".github/workflows/release-validation.yml" `
        -RoutingContractIdentity "scripts/validation/change-risk-rules.json" `
        -GateContractIdentity "scripts/validation/required-validation-gate.ps1" -OutputPath $canonicalPath | Out-Null
    $canonical = Get-Content -Raw $canonicalPath | ConvertFrom-Json
    Assert-Contract ($canonical.schema_version -eq 2 -and $canonical.proof_kind -ceq "canonical-candidate-evidence") "canonical-schema"
    Assert-Contract ($canonical.candidate.sha -ceq $commitSha -and $canonical.base.sha -ceq $candidateBase -and $canonical.head.sha -ceq $candidateHead) "canonical-candidate-identity"
    Assert-Contract (@($canonical.actual.suites) -contains "fixture-suite" -and @($canonical.actual.hosts) -contains "ubuntu-latest") "canonical-suite-host-closure"
    Assert-Contract ($canonical.checks.base_guard.job_id -ceq "301" -and $canonical.checks.identity_guard.job_id -ceq "302" -and $canonical.checks.final_gate.job_id -ceq "303") "canonical-actual-check-identities"
    Assert-Contract ($canonical.canonical_evidence_digest -match '^[0-9a-f]{64}$') "canonical-digest"
    $firstCanonicalDigest = [string]$canonical.canonical_evidence_digest
    & $finalizer -CandidateContractPath $candidateContractPath -ClassificationPath $classificationPath `
        -FragmentsRoot $fragmentRoot -GuardBindingPath $bindingPath -Repository "Huangshier/agent-ecosystem" `
        -RunId "123" -RunAttempt "2" -WorkflowIdentity ".github/workflows/release-validation.yml" `
        -RoutingContractIdentity "scripts/validation/change-risk-rules.json" `
        -GateContractIdentity "scripts/validation/required-validation-gate.ps1" -OutputPath $canonicalPath | Out-Null
    $secondCanonicalDigest = [string](Get-Content -Raw $canonicalPath | ConvertFrom-Json).canonical_evidence_digest
    Assert-Contract ($firstCanonicalDigest -ceq $secondCanonicalDigest) "canonical-digest-deterministic"

    $binding.base_guard.run_attempt = "1"
    $binding | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $bindingPath -Encoding UTF8
    $mixedAttemptFailed = $false
    try {
        & $finalizer -CandidateContractPath $candidateContractPath -ClassificationPath $classificationPath `
            -FragmentsRoot $fragmentRoot -GuardBindingPath $bindingPath -Repository "Huangshier/agent-ecosystem" `
            -RunId "123" -RunAttempt "2" -WorkflowIdentity ".github/workflows/release-validation.yml" `
            -RoutingContractIdentity "scripts/validation/change-risk-rules.json" `
            -GateContractIdentity "scripts/validation/required-validation-gate.ps1" -OutputPath $canonicalPath | Out-Null
    }
    catch { $mixedAttemptFailed = $true }
    Assert-Contract $mixedAttemptFailed "canonical-mixed-attempt-fails-closed"

    $candidateResult = & $candidateFixture -Json | ConvertFrom-Json
    Assert-Contract ([int]($candidateResult.fail) -eq 0 -and [int]($candidateResult.pass) -ge 4) "exact-candidate-fixtures"
    if ($PSVersionTable.PSEdition -ceq "Desktop") {
        # NOTE: lineage matrix 的执行 oracle 是 PowerShell 7；WinPS 在此只校验同一矩阵和入口完整存在。
        Assert-Contract ([System.IO.File]::Exists((Join-Path $PSScriptRoot "validation/lineage-verifier-fixtures/cases.json")) -and [System.IO.File]::Exists((Join-Path $PSScriptRoot "test-lineage-verifier.ps1"))) "lineage-proof-fixture-surface"
    }
    else {
        $lineageResult = & $lineageFixtureScript -Json | ConvertFrom-Json
        Assert-Contract ([int]($lineageResult.fail) -eq 0 -and [int]($lineageResult.pass) -ge 40) "lineage-proof-fixtures"
    }
    $nodeCheck = & node -e "const h=require('./.github/scripts/resolve-validation-check-bindings.js'); if(h.requireExactSingle([1],'x')!==1) process.exit(1); for(const v of [[],[1,2]]){let failed=false;try{h.requireExactSingle(v,'x')}catch{failed=true}if(!failed)process.exit(2)}"
    Assert-Contract ($LASTEXITCODE -eq 0) "guard-binding-exact-single-contract"
    Assert-Contract ($workflow.Contains("github.event_name == 'push' && github.run_id") -and $workflow.Contains("cancel-in-progress: `${{ github.event_name != 'push' }}")) "push-concurrency-independent"
    Assert-Contract (@([regex]::Matches($workflow, "resolve-pull-request-candidate\.ps1")).Count -eq 7 -and @([regex]::Matches($workflow, "ExpectedCandidateSha")).Count -eq 6) "all-pr-validation-jobs-reverify-candidate"
    Assert-Contract ($workflow.Contains("-BaseRef `$env:PR_BASE_SHA") -and $workflow.Contains("-HeadRef `$env:PR_HEAD_SHA")) "classifier-uses-exact-base-head"
    Assert-Contract ($workflow.Contains("name: canonical-candidate-evidence-pr-") -and $workflow.Contains("name: main lineage shadow")) "canonical-and-shadow-entrypoints"
    foreach ($guardWorkflowName in @("pr-base-guard.yml", "pr-identity-guard.yml")) {
        $guardWorkflow = [System.IO.File]::ReadAllText((Join-Path $repoRoot ".github/workflows/$guardWorkflowName"))
        Assert-Contract ($guardWorkflow.Contains("run-name:") -and $guardWorkflow.Contains('${{ github.event.pull_request.head.sha }}')) ("guard-run-identity:{0}" -f $guardWorkflowName)
    }

    $result = [ordered]@{ schema_version = 1; pass = $checks.Count; fail = 0; checks = @($checks.ToArray()) }
    if ($Json.IsPresent) { $result | ConvertTo-Json -Depth 6 } else { Write-Output ("validation evidence contract fixtures: PASS={0} FAIL=0" -f $result.pass) }
}
finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
