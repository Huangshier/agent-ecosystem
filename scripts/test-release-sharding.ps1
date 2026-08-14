[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$contractPath = Join-Path $PSScriptRoot "validation/release-shard-contract.json"
$contractHelper = Join-Path $PSScriptRoot "validation/release-shard-contract.ps1"
$validatorPath = Join-Path $PSScriptRoot "validate-release.ps1"
$workflowPath = Join-Path $repoRoot ".github/workflows/release-validation.yml"
$checks = New-Object 'System.Collections.Generic.List[object]'

function Assert-Fixture([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "Release sharding fixture failed: $Name" }
    $checks.Add([ordered]@{ name = $Name; status = "PASS" })
}

. $contractHelper
$contract = Get-ReleaseShardContract -ContractPath $contractPath
$neutral = @(Get-ExpectedReleaseCheckNames -ValidationShard PlatformNeutral -Contract $contract)
$runtime = @(Get-ExpectedReleaseCheckNames -ValidationShard RuntimePlatform -Contract $contract)
$full = @(Get-ExpectedReleaseCheckNames -ValidationShard Full -Contract $contract)
$checkpointNeutral = @(Get-ExpectedReleaseCheckNames -ValidationShard RepositoryCheckpointNeutral -Contract $contract)
$checkpointRuntime = @(Get-ExpectedReleaseCheckNames -ValidationShard RepositoryCheckpointRuntime -Contract $contract)
$checkpoint = @(Get-ExpectedReleaseCheckNames -ValidationShard RepositoryCheckpoint -Contract $contract)
$intersection = @($neutral | Where-Object { $runtime -ccontains $_ })

Assert-Fixture ($neutral.Count -eq 7) "product-platform-neutral-count"
Assert-Fixture ($runtime.Count -eq 18) "product-runtime-platform-count"
Assert-Fixture ($full.Count -eq 25) "product-runtime-full-count"
Assert-Fixture ($checkpointNeutral.Count -eq 38) "repository-checkpoint-neutral-count"
Assert-Fixture ($checkpointRuntime.Count -eq 22) "repository-checkpoint-runtime-count"
Assert-Fixture ($checkpoint.Count -eq 60) "repository-checkpoint-count"
Assert-Fixture ($intersection.Count -eq 0) "shards-disjoint"
Assert-Fixture (@($full | Sort-Object -Unique).Count -eq 25) "full-check-ownership-unique"
Assert-Fixture (@($checkpoint | Sort-Object -Unique).Count -eq 60) "checkpoint-check-ownership-unique"
Assert-Fixture (@($contract.merged_checks.PSObject.Properties).Count -eq 26) "duplicate-checks-merged"
foreach ($property in @($contract.merged_checks.PSObject.Properties)) {
    Assert-Fixture ($checkpoint -cnotcontains [string]$property.Name) ("merged-source-not-routed:{0}" -f $property.Name)
    Assert-Fixture ($checkpoint -ccontains [string]$property.Value) ("merged-authority-routed:{0}" -f $property.Value)
}

foreach ($required in @(
    "hub initialization git mode",
    "installer contract fixtures",
    "runtime status fixtures",
    "agent skill bridge fixtures",
    "runtime smoke",
    "project context gate targeted suite",
    "project bootstrap safety",
    "PowerShell script encoding",
    "PowerShell parse",
    "JSON parse",
    "language policy templates",
    "Claude hooks runtime fixtures"
)) {
    Assert-Fixture ($runtime -ccontains $required) ("runtime-owns:{0}" -f $required)
}

$neutralChecks = @($neutral | ForEach-Object { [pscustomobject]@{ name = $_ } })
$runtimeChecks = @($runtime | ForEach-Object { [pscustomobject]@{ name = $_ } })
$fullChecks = @($full | ForEach-Object { [pscustomobject]@{ name = $_ } })
$checkpointChecks = @($checkpoint | ForEach-Object { [pscustomobject]@{ name = $_ } })
Assert-Fixture ((Assert-ReleaseShardCoverage -ValidationShard PlatformNeutral -Checks $neutralChecks).status -ceq "PASS") "neutral-dynamic-contract"
Assert-Fixture ((Assert-ReleaseShardCoverage -ValidationShard RuntimePlatform -Checks $runtimeChecks).status -ceq "PASS") "runtime-dynamic-contract"
Assert-Fixture ((Assert-ReleaseShardCoverage -ValidationShard Full -Checks $fullChecks).status -ceq "PASS") "full-dynamic-contract"
Assert-Fixture ((Assert-ReleaseShardCoverage -ValidationShard RepositoryCheckpoint -Checks $checkpointChecks).status -ceq "PASS") "checkpoint-dynamic-contract"

$negativeFailed = $false
try {
    Assert-ReleaseShardCoverage -ValidationShard RuntimePlatform -Checks @($runtimeChecks | Select-Object -Skip 1) | Out-Null
}
catch { $negativeFailed = $true }
Assert-Fixture $negativeFailed "missing-runtime-check-fails-closed"

$validator = Get-Content -LiteralPath $validatorPath -Raw
foreach ($marker in @(
    '"RepositoryCheckpointNeutral", "RepositoryCheckpointRuntime"',
    'Invoke-ReleaseValidationRepositoryChecks',
    'Invoke-ReleaseHubInitializationChecks',
    'Invoke-ReleaseValidationInstallerRuntimeChecks',
    'Invoke-ReleaseKnowledgeSearchChecks',
    'Assert-ReleaseShardCoverage'
)) {
    Assert-Fixture ($validator.Contains($marker)) ("validator-marker:{0}" -f $marker)
}

$workflow = Get-Content -LiteralPath $workflowPath -Raw
foreach ($marker in @(
    'validation_sha: ${{ steps.target.outputs.sha }}',
    '${{ github.event.pull_request.head.sha }}',
    "github.event_name == 'schedule'",
    '"RepositoryCheckpointNeutral"',
    '"RepositoryCheckpointRuntime"',
    "if: always() && (github.event_name == 'workflow_dispatch' || github.event_name == 'schedule')",
    'PLATFORM_NEUTRAL_RESULT: ${{ needs.validate-platform-neutral.result }}',
    'PWSH_MATRIX_RESULT: ${{ needs.validate.result }}'
)) {
    Assert-Fixture ($workflow.Contains($marker)) ("workflow-marker:{0}" -f $marker)
}
Assert-Fixture (@([regex]::Matches($workflow, 'ref: \$\{\{ needs\.classify\.outputs\.validation_sha \}\}')).Count -eq 7) "downstream-checkouts-bind-validation-sha"
Assert-Fixture (@([regex]::Matches($workflow, 'CommitSha "\$\{\{ needs\.classify\.outputs\.validation_sha \}\}"')).Count -eq 5) "evidence-binds-validation-sha"
Assert-Fixture (-not $workflow.Contains('-CommitSha "${{ github.sha }}"')) "no-event-sha-evidence-fallback"
Assert-Fixture (@([regex]::Matches($workflow, '\$shard = if \("\$\{\{ github\.event_name \}\}" -eq "push"\)')).Count -eq 0) "main-push-does-not-route-release-shards"
Assert-Fixture (@([regex]::Matches($workflow, "if: always\(\) && \(github\.event_name == 'workflow_dispatch' \|\| github\.event_name == 'schedule'\)")).Count -eq 2) "release-shards-manual-and-scheduled-only"
Assert-Fixture ($workflow.Contains("needs: classify") -and
    $workflow.Contains("if: always() && (github.event_name == 'push' || (github.event_name == 'pull_request' && contains(needs.classify.outputs.modules, 'validation-routing')))") -and
    $workflow.Contains("scripts/validate-main-health.ps1")) "main-health-control-plane-entrypoint"

$summary = [ordered]@{
    schema_version = 2
    pass = $checks.Count
    fail = 0
    platform_neutral_checks = $neutral.Count
    runtime_platform_checks = $runtime.Count
    full_checks = $full.Count
    repository_checkpoint_checks = $checkpoint.Count
    intersection = $intersection.Count
    cases = @($checks.ToArray())
}
if ($Json.IsPresent) {
    $summary | ConvertTo-Json -Depth 6
}
else {
    Write-Output ("release-sharding fixtures: PASS={0} FAIL=0; neutral={1} runtime={2} full={3}" -f $summary.pass, $neutral.Count, $runtime.Count, $full.Count)
}
