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
$intersection = @($neutral | Where-Object { $runtime -ccontains $_ })

Assert-Fixture ($neutral.Count -eq 62) "platform-neutral-count"
Assert-Fixture ($runtime.Count -eq 30) "runtime-platform-count"
Assert-Fixture ($full.Count -eq 92) "full-union-count"
Assert-Fixture ($intersection.Count -eq 0) "shards-disjoint"
Assert-Fixture (@($full | Sort-Object -Unique).Count -eq 92) "full-check-ownership-unique"

foreach ($required in @(
    "hub initialization git mode",
    "installer contract fixtures",
    "runtime status fixtures",
    "agent skill bridge fixtures",
    "runtime smoke",
    "project context gate targeted suite",
    "project bootstrap safety",
    "knowledge candidate intake",
    "knowledge hub experience search",
    "Windows PowerShell script encoding",
    "PowerShell parse",
    "JSON parse",
    "language policy templates"
)) {
    Assert-Fixture ($runtime -ccontains $required) ("runtime-owns:{0}" -f $required)
}

$neutralChecks = @($neutral | ForEach-Object { [pscustomobject]@{ name = $_ } })
$runtimeChecks = @($runtime | ForEach-Object { [pscustomobject]@{ name = $_ } })
$fullChecks = @($full | ForEach-Object { [pscustomobject]@{ name = $_ } })
Assert-Fixture ((Assert-ReleaseShardCoverage -ValidationShard PlatformNeutral -Checks $neutralChecks).status -ceq "PASS") "neutral-dynamic-contract"
Assert-Fixture ((Assert-ReleaseShardCoverage -ValidationShard RuntimePlatform -Checks $runtimeChecks).status -ceq "PASS") "runtime-dynamic-contract"
Assert-Fixture ((Assert-ReleaseShardCoverage -ValidationShard Full -Checks $fullChecks).status -ceq "PASS") "full-dynamic-contract"

$negativeFailed = $false
try {
    Assert-ReleaseShardCoverage -ValidationShard RuntimePlatform -Checks @($runtimeChecks | Select-Object -Skip 1) | Out-Null
}
catch { $negativeFailed = $true }
Assert-Fixture $negativeFailed "missing-runtime-check-fails-closed"

$validator = Get-Content -LiteralPath $validatorPath -Raw
foreach ($marker in @(
    '[ValidateSet("Full", "PlatformNeutral", "RuntimePlatform")]',
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
    "github.event_name != 'workflow_dispatch'",
    '-ValidationShard PlatformNeutral',
    '"Full" } else { "RuntimePlatform" }',
    'PLATFORM_NEUTRAL_RESULT: ${{ needs.validate-platform-neutral.result }}',
    'PWSH_MATRIX_RESULT: ${{ needs.validate.result }}'
)) {
    Assert-Fixture ($workflow.Contains($marker)) ("workflow-marker:{0}" -f $marker)
}
Assert-Fixture (@([regex]::Matches($workflow, 'ref: \$\{\{ needs\.classify\.outputs\.validation_sha \}\}')).Count -eq 6) "downstream-checkouts-bind-validation-sha"
Assert-Fixture (@([regex]::Matches($workflow, 'CommitSha "\$\{\{ needs\.classify\.outputs\.validation_sha \}\}"')).Count -eq 5) "evidence-binds-validation-sha"
Assert-Fixture (-not $workflow.Contains('-CommitSha "${{ github.sha }}"')) "no-event-sha-evidence-fallback"
Assert-Fixture (@([regex]::Matches($workflow, '\$shard = if \("\$\{\{ github\.event_name \}\}" -eq "workflow_dispatch"\) \{ "Full" \} else \{ "RuntimePlatform" \}')).Count -eq 2) "dispatch-full-pr-push-runtime-routing"

$summary = [ordered]@{
    schema_version = 1
    pass = $checks.Count
    fail = 0
    platform_neutral_checks = $neutral.Count
    runtime_platform_checks = $runtime.Count
    full_checks = $full.Count
    intersection = $intersection.Count
    cases = @($checks.ToArray())
}
if ($Json.IsPresent) {
    $summary | ConvertTo-Json -Depth 6
}
else {
    Write-Output ("release-sharding fixtures: PASS={0} FAIL=0; neutral={1} runtime={2} full={3}" -f $summary.pass, $neutral.Count, $runtime.Count, $full.Count)
}
