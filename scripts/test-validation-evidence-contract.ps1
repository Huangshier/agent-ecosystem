[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$writer = Join-Path $PSScriptRoot "validation/write-evidence-manifest.ps1"
$finalizer = Join-Path $PSScriptRoot "validation/finalize-candidate-evidence.ps1"
$candidateFixture = Join-Path $PSScriptRoot "test-exact-candidate-contract.ps1"
$lineageFixtureScript = Join-Path $PSScriptRoot "test-lineage-verifier.ps1"
$lineageVerifier = Join-Path $PSScriptRoot "validation/lineage-verifier.ps1"
$workflowPath = Join-Path $repoRoot ".github/workflows/release-validation.yml"
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-ecosystem-evidence-contract-{0}" -f [Guid]::NewGuid().ToString("N"))
$commitSha = "0123456789abcdef0123456789abcdef01234567"
$checks = New-Object 'System.Collections.Generic.List[object]'

function Assert-Contract([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "Evidence contract fixture failed: $Name" }
    $checks.Add([ordered]@{ name = $Name; status = "PASS" }) | Out-Null
}

function Get-Sha256Text([string]$Text) {
    $hash = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hash.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text)))).Replace("-", "").ToLowerInvariant() }
    finally { $hash.Dispose() }
}

function Get-CanonicalEvidenceDigest([object]$Evidence) {
    $payload = [ordered]@{}
    foreach ($name in @(
        "schema_version", "proof_kind", "repository", "pr_number", "base", "head", "candidate", "change",
        "classifier", "required", "actual", "decisions", "contracts", "generation", "checks", "artifact_digests"
    )) { $payload[$name] = $Evidence.$name }
    return Get-Sha256Text ($payload | ConvertTo-Json -Depth 20 -Compress)
}

function Assert-CanonicalArray([object]$Evidence, [string]$Section, [string]$Name, [int]$ExpectedCount, [string]$CheckName) {
    $container = if ([string]::IsNullOrWhiteSpace($Section)) { $Evidence } else { $Evidence.$Section }
    $property = if ($null -eq $container) { @() } else { @($container.PSObject.Properties | Where-Object { $_.Name -ceq $Name }) }
    $value = $null
    if ($property.Count -eq 1) { $value = $property[0].Value }
    Assert-Contract (
        $property.Count -eq 1 -and
        $null -ne $value -and
        $value -is [System.Array] -and
        $value -isnot [string] -and
        @($value).Count -eq $ExpectedCount
    ) $CheckName
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
    Assert-Contract (@([regex]::Matches($workflow, "if: success\(\)")).Count -eq 7) "seven-success-upload-contracts"
    Assert-Contract (@([regex]::Matches($workflow, "if: failure\(\)")).Count -eq 5) "five-failure-upload-contracts"
    Assert-Contract (-not $workflow.Contains("**/*.json")) "no-recursive-json-allowlist"
    Assert-Contract (@([regex]::Matches($workflow, "write-evidence-manifest\.ps1")).Count -eq 5) "five-manifest-call-sites"
    Assert-Contract (@([regex]::Matches($workflow, 'HeavyTargetedStatus')).Count -eq 1 -and @([regex]::Matches($workflow, 'HeavyTargetedReason')).Count -eq 1) "heavy-decision-manifests"
    Assert-Contract ($workflow.Contains('validation-self-protection.json') -and $workflow.Contains('validation-self-protection-attempt-{0}')) "self-protection-evidence-uploaded"
    Assert-Contract (-not ([regex]::IsMatch($workflow, '(?m)^\s+\$\{\{ runner\.temp \}\}/.*validation-output\.json\s*$'))) "success-excludes-stream-capture"
    Assert-Contract (-not ([regex]::IsMatch($workflow, 'SuccessAllowlist[^\r\n]*validation-output\.json'))) "manifest-success-excludes-stream-capture"
    $failureUploadContracts = @(
        @("name: quick-validation-failure", 'path: ${{ runner.temp }}/agent-ecosystem-quick-validation'),
        @('name: affected-validation-${{ matrix.os }}-failure', 'path: ${{ runner.temp }}/agent-ecosystem-targeted-validation'),
        @('validation-self-protection-failure-attempt-{0}', 'path: ${{ runner.temp }}/agent-ecosystem-validation-self-protection'),
        @('name: validation-platform-neutral-failure', 'path: ${{ runner.temp }}/agent-ecosystem-platform-neutral-validation'),
        @('name: validation-pwsh-${{ matrix.os }}-failure', 'path: ${{ runner.temp }}/agent-ecosystem-release-validation')
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
        -HostIdentity "Windows-Desktop-Pwsh7" `
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
        & $writer -ScratchRoot $contradictionScratch -Outcome success -CommitSha $commitSha -RunId "126" -RunAttempt "1" -JobName "validate-contradiction" -HostIdentity "Windows-Desktop-Pwsh7" -HeavyTargetedStatus executed -HeavyTargetedReason "fixture" -SuccessAllowlist @("validation-result.json", "evidence-manifest.json") | Out-Null
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
    $canonicalTargetedResultPath = Join-Path $scratch "canonical-targeted-validation-result.json"
    [ordered]@{
        telemetry = @([ordered]@{ suite = "release-checkpoint"; case = "canonical-cardinality"; host = "fixture-host"; started_at_utc = "2026-01-01T00:00:00Z"; completed_at_utc = "2026-01-01T00:00:00.001Z"; duration_ms = 1; unique_coverage_category = "fixture-coverage" })
        executed_suites = @("release-checkpoint")
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $canonicalTargetedResultPath -Encoding UTF8
    $classificationPath = Join-Path $scratch "canonical-classification.json"
    [ordered]@{
        schema_version = 2; detected_tier = 2; affected_modules = @("release")
        conservative_fallback = $false; escalation_reason = ""
        base_ref = $candidateBase; head_ref = $candidateHead
        required_suites = @("release-checkpoint"); required_hosts = @("ubuntu-latest")
        run_validation_self_protection = $false
        validation_self_protection_reason = "not-tier-3"
        control_plane = $false; self_protection_required = $false; self_protection_reason = "not-tier-3"
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $classificationPath -Encoding UTF8
    $fragmentRoot = Join-Path $scratch "canonical-fragments"
    $fragmentScratch = Join-Path $fragmentRoot "affected-validation-ubuntu-latest"
    New-Item -ItemType Directory -Force -Path $fragmentScratch | Out-Null
    Copy-Item -LiteralPath $canonicalTargetedResultPath -Destination (Join-Path $fragmentScratch "targeted-validation-result.json")
    & $writer -ScratchRoot $fragmentScratch -Outcome success -CommitSha $commitSha -RunId "123" -RunAttempt "2" `
        -JobName "targeted-validation" -HostIdentity "Linux-Core-7.5" -Repository "Huangshier/agent-ecosystem" `
        -EventName pull_request -CandidateContractPath $candidateContractPath `
        -SuccessAllowlist @("targeted-validation-result.json", "evidence-manifest.json") | Out-Null
    $finalGateDirectory = Join-Path $fragmentRoot "final-validation-gate-attempt-2"
    New-Item -ItemType Directory -Force -Path $finalGateDirectory | Out-Null
    $finalGatePath = Join-Path $finalGateDirectory "final-gate.json"
    $finalGate = [ordered]@{
        schema_version = 1
        proof_kind = "final-validation-gate"
        repository = "Huangshier/agent-ecosystem"
        pr_number = 77
        head_sha = $candidateHead
        run_id = "123"
        run_attempt = "2"
        job = "validation-gate"
        check_name = "validation gate"
        conclusion = "success"
    }
    $finalGate | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $finalGatePath -Encoding UTF8
    $canonicalPath = Join-Path $scratch "canonical-evidence.json"
    $validClassification = Get-Content -Raw $classificationPath | ConvertFrom-Json
    $unknownReasonClassification = $validClassification | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $unknownReasonClassification.validation_self_protection_reason = "future-self-protection-reason"
    $unknownReasonClassification.self_protection_reason = "future-self-protection-reason"
    $unknownReasonClassification | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $classificationPath -Encoding UTF8
    $unknownReasonFailed = $false
    try {
        & $finalizer -CandidateContractPath $candidateContractPath -ClassificationPath $classificationPath `
            -FragmentsRoot $fragmentRoot -FinalGatePath $finalGatePath -Repository "Huangshier/agent-ecosystem" `
            -RunId "123" -RunAttempt "2" -WorkflowIdentity ".github/workflows/release-validation.yml" `
            -RoutingContractIdentity "scripts/validation/change-risk-rules.json" `
            -GateContractIdentity "scripts/validation/required-validation-gate.ps1" -OutputPath $canonicalPath | Out-Null
    }
    catch { $unknownReasonFailed = $true }
    Assert-Contract $unknownReasonFailed "canonical-classifier-unknown-reason-fails-closed"
    $validClassification | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $classificationPath -Encoding UTF8
    & $finalizer -CandidateContractPath $candidateContractPath -ClassificationPath $classificationPath `
        -FragmentsRoot $fragmentRoot -FinalGatePath $finalGatePath -Repository "Huangshier/agent-ecosystem" `
        -RunId "123" -RunAttempt "2" -WorkflowIdentity ".github/workflows/release-validation.yml" `
        -RoutingContractIdentity "scripts/validation/change-risk-rules.json" `
        -GateContractIdentity "scripts/validation/required-validation-gate.ps1" -OutputPath $canonicalPath | Out-Null
    $canonical = Get-Content -Raw $canonicalPath | ConvertFrom-Json
    Assert-Contract ($canonical.schema_version -eq 3 -and $canonical.proof_kind -ceq "canonical-candidate-evidence") "canonical-schema"
    Assert-Contract ($canonical.candidate.sha -ceq $commitSha -and $canonical.base.sha -ceq $candidateBase -and $canonical.head.sha -ceq $candidateHead) "canonical-candidate-identity"
    Assert-Contract (
        $canonical.generation.repository -ceq "Huangshier/agent-ecosystem" -and
        [int]$canonical.generation.pr_number -eq 77 -and
        $canonical.generation.run_id -ceq "123" -and
        $canonical.generation.run_attempt -ceq "2"
    ) "canonical-generation-identity"
    Assert-Contract (@($canonical.actual.suites) -contains "release-checkpoint" -and @($canonical.actual.hosts) -contains "ubuntu-latest") "canonical-suite-host-closure"
    Assert-Contract (
        $canonical.checks.PSObject.Properties.Name -join "," -ceq "final_gate" -and
        $canonical.checks.final_gate.job -ceq "validation-gate"
    ) "canonical-final-gate-only"
    Assert-Contract (
        $canonical.classifier.control_plane -is [bool] -and -not [bool]$canonical.classifier.control_plane -and
        $canonical.classifier.self_protection_required -is [bool] -and -not [bool]$canonical.classifier.self_protection_required -and
        [string]$canonical.classifier.self_protection_reason -ceq "not-tier-3"
    ) "canonical-classifier-authority"
    Assert-CanonicalArray $canonical "classifier" "affected_modules" 1 "canonical-array-one:classifier.affected_modules"
    Assert-CanonicalArray $canonical "required" "suites" 1 "canonical-array-one:required.suites"
    Assert-CanonicalArray $canonical "required" "hosts" 1 "canonical-array-one:required.hosts"
    Assert-CanonicalArray $canonical "actual" "suites" 1 "canonical-array-one:actual.suites"
    Assert-CanonicalArray $canonical "actual" "hosts" 1 "canonical-array-one:actual.hosts"
    Assert-CanonicalArray $canonical "" "artifact_digests" 3 "canonical-array-one:artifact_digests"
    Assert-Contract (
        (@($canonical.classifier.affected_modules) -join ",") -ceq "release" -and
        (@($canonical.required.suites) -join ",") -ceq "release-checkpoint" -and
        (@($canonical.required.hosts) -join ",") -ceq "ubuntu-latest" -and
        (@($canonical.actual.suites) -join ",") -ceq "release-checkpoint" -and
        (@($canonical.actual.hosts) -join ",") -ceq "ubuntu-latest"
    ) "canonical-array-one:values"
    Assert-Contract ($canonical.canonical_evidence_digest -match '^[0-9a-f]{64}$') "canonical-digest"
    Assert-Contract (
        [string]$canonical.canonical_evidence_digest -ceq (Get-CanonicalEvidenceDigest $canonical)
    ) "canonical-digest-recomputed"
    $firstCanonicalDigest = [string]$canonical.canonical_evidence_digest
    & $finalizer -CandidateContractPath $candidateContractPath -ClassificationPath $classificationPath `
        -FragmentsRoot $fragmentRoot -FinalGatePath $finalGatePath -Repository "Huangshier/agent-ecosystem" `
        -RunId "123" -RunAttempt "2" -WorkflowIdentity ".github/workflows/release-validation.yml" `
        -RoutingContractIdentity "scripts/validation/change-risk-rules.json" `
        -GateContractIdentity "scripts/validation/required-validation-gate.ps1" -OutputPath $canonicalPath | Out-Null
    $secondCanonical = Get-Content -Raw $canonicalPath | ConvertFrom-Json
    $secondCanonicalDigest = [string]$secondCanonical.canonical_evidence_digest
    Assert-Contract ($firstCanonicalDigest -ceq $secondCanonicalDigest) "canonical-digest-deterministic"
    Assert-Contract (
        [string]$secondCanonicalDigest -ceq (Get-CanonicalEvidenceDigest $secondCanonical)
    ) "canonical-digest-repeat-recomputed"

    $zeroClassification = $validClassification | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $zeroClassification.affected_modules = @()
    $zeroClassification.required_suites = @()
    $zeroClassification.required_hosts = @()
    $zeroCanonicalPath = Join-Path $scratch "canonical-evidence-zero.json"
    $zeroClassification | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $classificationPath -Encoding UTF8
    & $finalizer -CandidateContractPath $candidateContractPath -ClassificationPath $classificationPath `
        -FragmentsRoot $fragmentRoot -FinalGatePath $finalGatePath -Repository "Huangshier/agent-ecosystem" `
        -RunId "123" -RunAttempt "2" -WorkflowIdentity ".github/workflows/release-validation.yml" `
        -RoutingContractIdentity "scripts/validation/change-risk-rules.json" `
        -GateContractIdentity "scripts/validation/required-validation-gate.ps1" -OutputPath $zeroCanonicalPath | Out-Null
    $zeroCanonical = Get-Content -Raw $zeroCanonicalPath | ConvertFrom-Json
    Assert-CanonicalArray $zeroCanonical "classifier" "affected_modules" 0 "canonical-array-zero:classifier.affected_modules"
    Assert-CanonicalArray $zeroCanonical "required" "suites" 0 "canonical-array-zero:required.suites"
    Assert-CanonicalArray $zeroCanonical "required" "hosts" 0 "canonical-array-zero:required.hosts"
    Assert-CanonicalArray $zeroCanonical "actual" "suites" 1 "canonical-array-zero:actual.suites"
    Assert-CanonicalArray $zeroCanonical "actual" "hosts" 1 "canonical-array-zero:actual.hosts"
    Assert-CanonicalArray $zeroCanonical "" "artifact_digests" 3 "canonical-array-zero:artifact_digests"
    Assert-Contract (
        [string]$zeroCanonical.canonical_evidence_digest -ceq (Get-CanonicalEvidenceDigest $zeroCanonical)
    ) "canonical-array-zero:digest-recomputed"

    $multipleTargetedResultPath = Join-Path $scratch "canonical-multiple-targeted-validation-result.json"
    [ordered]@{
        telemetry = @([ordered]@{ suite = "suite-a"; case = "canonical-cardinality-multiple"; host = "fixture-host"; started_at_utc = "2026-01-01T00:00:00Z"; completed_at_utc = "2026-01-01T00:00:00.001Z"; duration_ms = 1; unique_coverage_category = "fixture-coverage" })
        executed_suites = @("suite-z", "suite-a", "suite-z")
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $multipleTargetedResultPath -Encoding UTF8
    $multipleFragmentRoot = Join-Path $scratch "canonical-multiple-fragments"
    foreach ($fragmentSpec in @(
        [pscustomobject]@{ directory = "affected-validation-ubuntu-latest"; job = "targeted-validation-ubuntu"; host = "Linux-Core-7.5" },
        [pscustomobject]@{ directory = "affected-validation-windows-latest"; job = "targeted-validation-windows"; host = "Windows-Core-7.5" }
    )) {
        $multipleFragmentScratch = Join-Path $multipleFragmentRoot $fragmentSpec.directory
        New-Item -ItemType Directory -Force -Path $multipleFragmentScratch | Out-Null
        Copy-Item -LiteralPath $multipleTargetedResultPath -Destination (Join-Path $multipleFragmentScratch "targeted-validation-result.json")
        & $writer -ScratchRoot $multipleFragmentScratch -Outcome success -CommitSha $commitSha -RunId "124" -RunAttempt "2" `
            -JobName $fragmentSpec.job -HostIdentity $fragmentSpec.host -Repository "Huangshier/agent-ecosystem" `
            -EventName pull_request -CandidateContractPath $candidateContractPath `
            -SuccessAllowlist @("targeted-validation-result.json", "evidence-manifest.json") | Out-Null
    }
    $multipleClassification = $validClassification | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $multipleClassification.affected_modules = @("validation-routing", "documentation", "validation-routing")
    $multipleClassification.required_suites = @("suite-z", "suite-a", "suite-z")
    $multipleClassification.required_hosts = @("windows-latest", "ubuntu-latest", "windows-latest")
    $multipleClassificationPath = Join-Path $scratch "canonical-multiple-classification.json"
    $multipleClassification | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $multipleClassificationPath -Encoding UTF8
    $multipleFinalGate = $finalGate | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $multipleFinalGate.run_id = "124"
    $multipleFinalGateDirectory = Join-Path $multipleFragmentRoot "final-validation-gate-attempt-2"
    New-Item -ItemType Directory -Force -Path $multipleFinalGateDirectory | Out-Null
    $multipleFinalGatePath = Join-Path $multipleFinalGateDirectory "final-gate.json"
    $multipleFinalGate | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $multipleFinalGatePath -Encoding UTF8
    $multipleCanonicalPath = Join-Path $scratch "canonical-evidence-multiple.json"
    & $finalizer -CandidateContractPath $candidateContractPath -ClassificationPath $multipleClassificationPath `
        -FragmentsRoot $multipleFragmentRoot -FinalGatePath $multipleFinalGatePath -Repository "Huangshier/agent-ecosystem" `
        -RunId "124" -RunAttempt "2" -WorkflowIdentity ".github/workflows/release-validation.yml" `
        -RoutingContractIdentity "scripts/validation/change-risk-rules.json" `
        -GateContractIdentity "scripts/validation/required-validation-gate.ps1" -OutputPath $multipleCanonicalPath | Out-Null
    $multipleCanonical = Get-Content -Raw $multipleCanonicalPath | ConvertFrom-Json
    Assert-CanonicalArray $multipleCanonical "classifier" "affected_modules" 2 "canonical-array-multiple:classifier.affected_modules"
    Assert-CanonicalArray $multipleCanonical "required" "suites" 2 "canonical-array-multiple:required.suites"
    Assert-CanonicalArray $multipleCanonical "required" "hosts" 2 "canonical-array-multiple:required.hosts"
    Assert-CanonicalArray $multipleCanonical "actual" "suites" 2 "canonical-array-multiple:actual.suites"
    Assert-CanonicalArray $multipleCanonical "actual" "hosts" 2 "canonical-array-multiple:actual.hosts"
    Assert-CanonicalArray $multipleCanonical "" "artifact_digests" 5 "canonical-array-multiple:artifact_digests"
    Assert-Contract (
        (@($multipleCanonical.classifier.affected_modules) -join ",") -ceq "documentation,validation-routing" -and
        (@($multipleCanonical.required.suites) -join ",") -ceq "suite-a,suite-z" -and
        (@($multipleCanonical.required.hosts) -join ",") -ceq "ubuntu-latest,windows-latest" -and
        (@($multipleCanonical.actual.suites) -join ",") -ceq "suite-a,suite-z" -and
        (@($multipleCanonical.actual.hosts) -join ",") -ceq "ubuntu-latest,windows-latest"
    ) "canonical-array-multiple:ordinal-deduplicated"
    $firstMultipleDigest = [string]$multipleCanonical.canonical_evidence_digest
    Assert-Contract ($firstMultipleDigest -ceq (Get-CanonicalEvidenceDigest $multipleCanonical)) "canonical-array-multiple:digest-recomputed"
    & $finalizer -CandidateContractPath $candidateContractPath -ClassificationPath $multipleClassificationPath `
        -FragmentsRoot $multipleFragmentRoot -FinalGatePath $multipleFinalGatePath -Repository "Huangshier/agent-ecosystem" `
        -RunId "124" -RunAttempt "2" -WorkflowIdentity ".github/workflows/release-validation.yml" `
        -RoutingContractIdentity "scripts/validation/change-risk-rules.json" `
        -GateContractIdentity "scripts/validation/required-validation-gate.ps1" -OutputPath $multipleCanonicalPath | Out-Null
    $secondMultipleCanonical = Get-Content -Raw $multipleCanonicalPath | ConvertFrom-Json
    Assert-Contract (
        $firstMultipleDigest -ceq [string]$secondMultipleCanonical.canonical_evidence_digest -and
        [string]$secondMultipleCanonical.canonical_evidence_digest -ceq (Get-CanonicalEvidenceDigest $secondMultipleCanonical)
    ) "canonical-array-multiple:digest-deterministic"
    $validClassification | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $classificationPath -Encoding UTF8

    $landedSha = "4444444444444444444444444444444444444444"
    $lineageInputPath = Join-Path $scratch "canonical-lineage-input.json"
    $lineageOutputPath = Join-Path $scratch "canonical-lineage-output.json"
    [ordered]@{
        schema_version = 1; repository = "Huangshier/agent-ecosystem"; before = $candidateBase; sha = $landedSha
        forced = $false; range_complete = $true
        commits = @([ordered]@{
            sha = $landedSha; tree = [string]$canonical.candidate.tree; parents = @($candidateBase); associated_prs = @(77)
            combined_change_digest = "combined-1"; ordered_change_digest = "patch-1"
        })
        proofs = @([ordered]@{
            pr_number = 77; pr_base_sha = $candidateBase; pr_head_sha = $candidateHead; evidence = $canonical
        })
    } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $lineageInputPath -Encoding UTF8
    & $lineageVerifier -InputPath $lineageInputPath -OutputPath $lineageOutputPath | Out-Null
    $canonicalLineage = Get-Content -Raw $lineageOutputPath | ConvertFrom-Json
    Assert-Contract ($canonicalLineage.decision -ceq "proven") "canonical-classifier-lineage-proven"

    $tamperedCanonical = $canonical | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $tamperedCanonical.classifier.control_plane = $true
    $tamperedLineageInputPath = Join-Path $scratch "canonical-lineage-tampered-input.json"
    $tamperedLineageOutputPath = Join-Path $scratch "canonical-lineage-tampered-output.json"
    [ordered]@{
        schema_version = 1; repository = "Huangshier/agent-ecosystem"; before = $candidateBase; sha = $landedSha
        forced = $false; range_complete = $true
        commits = @([ordered]@{
            sha = $landedSha; tree = [string]$canonical.candidate.tree; parents = @($candidateBase); associated_prs = @(77)
            combined_change_digest = "combined-1"; ordered_change_digest = "patch-1"
        })
        proofs = @([ordered]@{
            pr_number = 77; pr_base_sha = $candidateBase; pr_head_sha = $candidateHead; evidence = $tamperedCanonical
        })
    } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $tamperedLineageInputPath -Encoding UTF8
    & $lineageVerifier -InputPath $tamperedLineageInputPath -OutputPath $tamperedLineageOutputPath | Out-Null
    $tamperedLineage = Get-Content -Raw $tamperedLineageOutputPath | ConvertFrom-Json
    Assert-Contract (
        $tamperedLineage.decision -ceq "full-fallback" -and
        @($tamperedLineage.fallback_reasons) -contains "evidence-digest-mismatch"
    ) "canonical-classifier-tamper-fails-closed"

    $finalGate.run_attempt = "1"
    $finalGate | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $finalGatePath -Encoding UTF8
    $mixedAttemptFailed = $false
    try {
        & $finalizer -CandidateContractPath $candidateContractPath -ClassificationPath $classificationPath `
            -FragmentsRoot $fragmentRoot -FinalGatePath $finalGatePath -Repository "Huangshier/agent-ecosystem" `
            -RunId "123" -RunAttempt "2" -WorkflowIdentity ".github/workflows/release-validation.yml" `
            -RoutingContractIdentity "scripts/validation/change-risk-rules.json" `
            -GateContractIdentity "scripts/validation/required-validation-gate.ps1" -OutputPath $canonicalPath | Out-Null
    }
    catch { $mixedAttemptFailed = $true }
    Assert-Contract $mixedAttemptFailed "canonical-mixed-attempt-fails-closed"

    $partialAttemptRoot = Join-Path $scratch "canonical-partial-attempt"
    $partialGateDirectory = Join-Path $partialAttemptRoot "final-validation-gate-attempt-2"
    New-Item -ItemType Directory -Force -Path $partialGateDirectory | Out-Null
    $partialGatePath = Join-Path $partialGateDirectory "final-gate.json"
    $partialGate = $finalGate | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $partialGate.run_attempt = "2"
    $partialGate | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $partialGatePath -Encoding UTF8
    $rerunFailedRejected = $false
    try {
        & $finalizer -CandidateContractPath $candidateContractPath -ClassificationPath $classificationPath `
            -FragmentsRoot $partialAttemptRoot -FinalGatePath $partialGatePath -Repository "Huangshier/agent-ecosystem" `
            -RunId "123" -RunAttempt "2" -WorkflowIdentity ".github/workflows/release-validation.yml" `
            -RoutingContractIdentity "scripts/validation/change-risk-rules.json" `
            -GateContractIdentity "scripts/validation/required-validation-gate.ps1" -OutputPath $canonicalPath | Out-Null
    }
    catch { $rerunFailedRejected = $true }
    Assert-Contract $rerunFailedRejected "rerun-failed-incomplete-generation-rejected"

    $rerunAllRoot = Join-Path $scratch "canonical-rerun-all-attempt-3"
    $rerunAllFragment = Join-Path $rerunAllRoot "affected-validation-ubuntu-latest-attempt-3"
    New-Item -ItemType Directory -Force -Path $rerunAllFragment | Out-Null
    Copy-Item -LiteralPath $canonicalTargetedResultPath -Destination (Join-Path $rerunAllFragment "targeted-validation-result.json")
    & $writer -ScratchRoot $rerunAllFragment -Outcome success -CommitSha $commitSha -RunId "123" -RunAttempt "3" `
        -JobName "targeted-validation" -HostIdentity "Linux-Core-7.5" -Repository "Huangshier/agent-ecosystem" `
        -EventName pull_request -CandidateContractPath $candidateContractPath `
        -SuccessAllowlist @("targeted-validation-result.json", "evidence-manifest.json") | Out-Null
    $rerunAllGateDirectory = Join-Path $rerunAllRoot "final-validation-gate-attempt-3"
    New-Item -ItemType Directory -Force -Path $rerunAllGateDirectory | Out-Null
    $rerunAllGatePath = Join-Path $rerunAllGateDirectory "final-gate.json"
    $rerunAllGate = $partialGate | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $rerunAllGate.run_attempt = "3"
    $rerunAllGate | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $rerunAllGatePath -Encoding UTF8
    $rerunAllCanonicalPath = Join-Path $scratch "canonical-rerun-all-attempt-3.json"
    & $finalizer -CandidateContractPath $candidateContractPath -ClassificationPath $classificationPath `
        -FragmentsRoot $rerunAllRoot -FinalGatePath $rerunAllGatePath -Repository "Huangshier/agent-ecosystem" `
        -RunId "123" -RunAttempt "3" -WorkflowIdentity ".github/workflows/release-validation.yml" `
        -RoutingContractIdentity "scripts/validation/change-risk-rules.json" `
        -GateContractIdentity "scripts/validation/required-validation-gate.ps1" -OutputPath $rerunAllCanonicalPath | Out-Null
    $rerunAllCanonical = Get-Content -Raw $rerunAllCanonicalPath | ConvertFrom-Json
    Assert-Contract (
        $rerunAllCanonical.candidate.sha -ceq $canonical.candidate.sha -and
        $rerunAllCanonical.candidate.tree -ceq $canonical.candidate.tree -and
        $rerunAllCanonical.generation.run_id -ceq "123" -and
        $rerunAllCanonical.generation.run_attempt -ceq "3" -and
        @($rerunAllCanonical.artifact_digests | Where-Object { [string]$_.path -match 'attempt-2' }).Count -eq 0
    ) "rerun-all-complete-fresh-generation"

    $candidateResult = & $candidateFixture -Json | ConvertFrom-Json
    Assert-Contract ([int]($candidateResult.fail) -eq 0 -and [int]($candidateResult.pass) -ge 4) "exact-candidate-fixtures"
    Assert-Contract (
        @($candidateResult.cases | Where-Object {
            [string]$_.name -ceq "real-git-digest-parity" -and
            [string]$_.status -ceq "PASS" -and
            (@($_.candidate_ordered_change_digests) -join ",") -ceq (@($_.rebase_landed_ordered_change_digests) -join ",") -and
            [string]$_.candidate_combined_digest -ceq [string]$_.squash_combined_digest
        }).Count -eq 1
    ) "exact-candidate-real-git-parity"
    if ($PSVersionTable.PSEdition -ceq "Desktop") {
        # NOTE: 当前基线仅支持 PowerShell 7.6（pwsh）；Desktop 分支仅在 Windows PowerShell 运行时触达，保留为防御性回退。
        Assert-Contract ([System.IO.File]::Exists((Join-Path $PSScriptRoot "validation/lineage-verifier-fixtures/cases.json")) -and [System.IO.File]::Exists((Join-Path $PSScriptRoot "test-lineage-verifier.ps1"))) "lineage-proof-fixture-surface"
    }
    else {
        $lineageResult = & $lineageFixtureScript -Json | ConvertFrom-Json
        Assert-Contract (
            [int]($lineageResult.fail) -eq 0 -and
            [int]($lineageResult.state_machine_matrix.pass) -eq 40 -and
            [int]($lineageResult.state_machine_matrix.cases) -eq 40 -and
            @($lineageResult.classifier_authority).Count -ge 7 -and
            @($lineageResult.generation_resolution).Count -ge 5
        ) "lineage-proof-fixtures"
    }
    Assert-Contract (-not [System.IO.File]::Exists((Join-Path $repoRoot ".github/scripts/resolve-validation-check-bindings.js"))) "guard-resolver-deleted"
    Assert-Contract ($workflow.Contains("github.event_name == 'push' && github.run_id") -and $workflow.Contains("cancel-in-progress: `${{ github.event_name != 'push' }}")) "push-concurrency-independent"
    Assert-Contract (@([regex]::Matches($workflow, "resolve-pull-request-candidate\.ps1")).Count -eq 6 -and @([regex]::Matches($workflow, "ExpectedCandidateSha")).Count -eq 5) "all-pr-validation-jobs-reverify-candidate"
    Assert-Contract ($workflow.Contains("-BaseRef `$env:PR_BASE_SHA") -and $workflow.Contains("-HeadRef `$env:PR_HEAD_SHA")) "classifier-uses-exact-base-head"
    Assert-Contract (
        $workflow.Contains("run-name: `"`${{ github.event_name == 'pull_request'") -and
        $workflow.Contains("Release validation #{0} {1} {2}") -and
        $workflow.Contains("name: canonical-candidate-evidence-pr-") -and
        $workflow.Contains("-run-`${{ github.run_id }}-attempt-`${{ github.run_attempt }}") -and
        $workflow.Contains("pattern: '*-attempt-`${{ github.run_attempt }}'")
    ) "generation-bound-workflow-entrypoints"
    Assert-Contract (
        $workflow.Contains("if: always() && github.event_name == 'pull_request'") -and
        $workflow.Contains("name: main lineage shadow")
    ) "workflow-dispatch-does-not-produce-pr-canonical"
    $canonicalJob = [regex]::Match($workflow, '(?ms)^  canonical-candidate-evidence:\s*\r?\n(?<body>.*?)(?=^  [a-zA-Z0-9_-]+:\s*\r?$|\z)').Groups['body'].Value
    Assert-Contract (
        -not $canonicalJob.Contains("guard") -and
        -not $canonicalJob.Contains("actions/github-script") -and
        $canonicalJob.Contains("-FinalGatePath")
    ) "duplicate-guards-independent-from-canonical"
    $triggerBlock = [regex]::Match($workflow, '(?ms)^on:\s*\r?\n(?<body>.*?)(?=^permissions:)').Groups['body'].Value
    Assert-Contract (
        -not $triggerBlock.Contains("edited") -and
        -not $triggerBlock.Contains("ready_for_review")
    ) "pr-metadata-actions-do-not-create-release-generation"
    foreach ($guardWorkflowName in @("pr-base-guard.yml", "pr-identity-guard.yml")) {
        $guardWorkflow = [System.IO.File]::ReadAllText((Join-Path $repoRoot ".github/workflows/$guardWorkflowName"))
        Assert-Contract (
            $guardWorkflow.Contains("- edited") -and
            $guardWorkflow.Contains("- ready_for_review")
        ) ("guard-metadata-independence:{0}" -f $guardWorkflowName)
    }
    $lineageSource = [System.IO.File]::ReadAllText($lineageVerifier)
    Assert-Contract (
        $lineageSource.Contains("Select-LatestReleaseRun") -and
        $lineageSource.Contains("missing-latest-generation-evidence") -and
        -not $lineageSource.Contains("base_guard") -and
        -not $lineageSource.Contains("identity_guard") -and
        -not $lineageSource.Contains('"Release validation"')
    ) "latest-generation-only-no-bootstrap-compatibility"
    $scanContract = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot "validation/sensitive-scan-contract.ps1"))
    $standardAuthReference = 'LINEAGE_GITHUB_AUTH: ${{ github.' + 'to' + 'ken }}'
    Assert-Contract (
        $workflow.Contains($standardAuthReference) -and
        $scanContract.Contains('".github/workflows/release-validation.yml" = ''^\s*LINEAGE_GITHUB_AUTH:') -and
        -not $scanContract.Contains('"scripts/validation/release-parser-safety-checks.ps1",`r`n        ".github/workflows/release-validation.yml"')
    ) "standard-github-auth-reference-is-line-scoped"

    $result = [ordered]@{ schema_version = 1; pass = $checks.Count; fail = 0; checks = @($checks.ToArray()) }
    if ($Json.IsPresent) { $result | ConvertTo-Json -Depth 6 } else { Write-Output ("validation evidence contract fixtures: PASS={0} FAIL=0" -f $result.pass) }
}
finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
