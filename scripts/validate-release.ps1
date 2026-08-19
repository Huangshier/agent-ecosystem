[CmdletBinding()]
param(
    [string]$ScratchRoot = "",
    [switch]$SkipLinkMode,
    [string]$TargetVersion = "v0.8.0",
    [ValidateSet("Full", "PlatformNeutral", "RuntimePlatform", "RepositoryCheckpoint", "RepositoryCheckpointNeutral", "RepositoryCheckpointRuntime")]
    [string]$ValidationShard = "Full",
    [switch]$Json
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $scriptDir "validation/powershell-runtime-requirement.ps1")
Assert-AgentEcosystemPowerShellRuntime
$repoRoot = Split-Path -Parent $scriptDir
. (Join-Path $scriptDir "lib/path-guard.ps1")
. (Join-Path $scriptDir "validation/release-test-helper.ps1")
. (Join-Path $scriptDir "validation/release-shard-contract.ps1")
. (Join-Path $scriptDir "validation/workflow-spec-lite-fixture-helper.ps1")
. (Join-Path $scriptDir "validation/release-repository-checks.ps1")
. (Join-Path $scriptDir "validation/release-hub-initialization-checks.ps1")
. (Join-Path $scriptDir "validation/release-parser-safety-checks.ps1")
. (Join-Path $scriptDir "validation/release-documentation-checks.ps1")
. (Join-Path $scriptDir "validation/release-knowledge-hub-checks.ps1")
. (Join-Path $scriptDir "validation/release-knowledge-search-checks.ps1")
. (Join-Path $scriptDir "validation/release-template-language-checks.ps1")
. (Join-Path $scriptDir "validation/release-installer-contract-checks.ps1")
. (Join-Path $scriptDir "validation/release-agent-skill-bridge-checks.ps1")
. (Join-Path $scriptDir "validation/release-runtime-smoke-checks.ps1")
. (Join-Path $scriptDir "validation/release-runtime-status-checks.ps1")
. (Join-Path $scriptDir "validation/release-bootstrap-checks.ps1")
. (Join-Path $scriptDir "validation/release-project-template-checks.ps1")
. (Join-Path $scriptDir "validation/release-memory-diagnostics-fixture-checks.ps1")
. (Join-Path $scriptDir "validation/release-eval-iteration-checks.ps1")
. (Join-Path $scriptDir "validation/release-eval-report-generator.ps1")
. (Join-Path $scriptDir "validation/release-eval-runner-generator.ps1")
. (Join-Path $scriptDir "validation/release-governance-workflow-checks.ps1")
. (Join-Path $scriptDir "validation/release-eval-benchmark-generator.ps1")
. (Join-Path $scriptDir "validation/release-claude-hooks-guardrails-checks.ps1")
$runStamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss")

if ([string]::IsNullOrWhiteSpace($ScratchRoot)) {
    $ScratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-ecosystem-release-validation-{0}" -f $runStamp)
}

$scratchRootFull = [System.IO.Path]::GetFullPath($ScratchRoot)
$liveRuntimeCandidates = @(Get-AgentLiveRuntimeCandidates)

Assert-NotLiveRuntime -Path $scratchRootFull
New-Item -ItemType Directory -Force -Path $scratchRootFull | Out-Null

$checks = New-Object 'System.Collections.Generic.List[object]'
$releaseShardContract = Get-ReleaseShardContract
$script:releaseMergedCheckMap = @{}
$script:releaseMergedCheckTargets = @{}
foreach ($property in @($releaseShardContract.merged_checks.PSObject.Properties)) {
    $sourceName = [string]$property.Name
    $targetName = [string]$property.Value
    $script:releaseMergedCheckMap[$sourceName] = $targetName
    $script:releaseMergedCheckTargets[$targetName] = $true
}
$script:mergedCheckEvidence = New-Object 'System.Collections.Generic.List[object]'
$script:validationCheckStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$script:validationCheckCheckpointMs = 0L
$evidence = [ordered]@{
    profile_matrix = @()
    installer_contract = @()
    agent_skill_bridge = @()
    runtime_smoke = [ordered]@{}
    runtime_status = @()
    project_context_gate = [ordered]@{}
    audit = [ordered]@{}
    knowledge_hub = [ordered]@{}
    duplicate_helpers = @()
    memory_metadata = [ordered]@{}
    language_policy = [ordered]@{}
    language_migration = [ordered]@{}
    memory_language_audit = [ordered]@{}
    bootstrap_command_boundary = [ordered]@{}
    bootstrap_safety = [ordered]@{}
    routing = [ordered]@{}
    release_body_contract = [ordered]@{}
    scratch_retention = [ordered]@{}
    spec_lite = [ordered]@{}
    agent_template_guidance = [ordered]@{}
    structural_diagnostics_design = [ordered]@{}
    structural_diagnostics_fixtures = [ordered]@{}
    memory_boundary = [ordered]@{}
    eval_iteration_fixtures = [ordered]@{}
    eval_report_artifact = [ordered]@{}
    eval_baseline_artifact = [ordered]@{}
    eval_report_regeneration = [ordered]@{}
    eval_report_generation_smoke = [ordered]@{}
    spec_state_boundary = [ordered]@{}
    hot_memory_soft_length_fixtures = [ordered]@{}
    runner_output_contract = [ordered]@{}
    runner_output_regeneration = [ordered]@{}
    benchmark_artifact = [ordered]@{}
    benchmark_regeneration = [ordered]@{}
    claude_hooks_guardrails_contract = [ordered]@{}
    claude_hooks_guardrails_templates = [ordered]@{}
    claude_hooks_guardrails_fixtures = [ordered]@{}
    claude_hooks_runtime_fixtures = [ordered]@{}
    merged_checks = $script:mergedCheckEvidence
}
$script:includeCheckpointChecks = $ValidationShard -in @("RepositoryCheckpoint", "RepositoryCheckpointRuntime")

$targetReleaseVersion = $TargetVersion.Trim()
if ([string]::IsNullOrWhiteSpace($targetReleaseVersion)) {
    $targetReleaseVersion = "v0.8.0"
}
if ($targetReleaseVersion -notmatch '^v\d+\.\d+\.\d+$') {
    throw "TargetVersion must look like vMAJOR.MINOR.PATCH."
}

# Invoke-ReleaseValidationRepositoryChecks: Delegates to Invoke-ReleaseRepositoryChecks for all
# repository, documentation boundary, helper ownership, skill metadata, and hub init checks.
function Invoke-ReleaseValidationRepositoryChecks {

Invoke-ReleaseRepositoryChecks

try {
    $gateFixtures = Join-PathParts $repoRoot "scripts" "test-required-validation-gate.ps1"
    $gateEvidence = @(& $gateFixtures -Json) -join "`n" | ConvertFrom-Json
    if ([int]$gateEvidence.fail -ne 0) {
        throw "Required validation gate fixtures reported failures."
    }
    $script:evidence.routing.required_validation_gate = $gateEvidence
    Add-Check "required validation gate" "PASS" "Tier 0-3, main/manual routing, fail-closed results, and the fixed workflow gate contract passed." $gateEvidence
}
catch {
    Add-Check "required validation gate" "FAIL" $_.Exception.Message
}

try {
    $evidenceContractFixtures = Join-PathParts $repoRoot "scripts" "test-validation-evidence-contract.ps1"
    $evidenceContract = @(& $evidenceContractFixtures -Json) -join "`n" | ConvertFrom-Json
    if ([int]$evidenceContract.fail -ne 0) {
        throw "Validation evidence contract fixtures reported failures."
    }
    $script:evidence.routing.validation_evidence_contract = $evidenceContract
    Add-Check "validation evidence contract" "PASS" "Additive duration telemetry, public-safe manifest identity, explicit success allowlists, and full failure evidence contracts passed." $evidenceContract
}
catch {
    Add-Check "validation evidence contract" "FAIL" $_.Exception.Message
}

try {
    $releaseBodyFixtures = Join-PathParts $repoRoot "scripts" "test-release-body-contract.ps1"
    $releaseBodyContract = @(& $releaseBodyFixtures -Json) -join "`n" | ConvertFrom-Json
    if ([int]$releaseBodyContract.fail -ne 0) {
        throw "Release body contract fixtures reported failures."
    }
    $script:evidence.release_body_contract = $releaseBodyContract
    Add-Check "release body contract" "PASS" "Future release bodies are user-facing, maintainer evidence stays outside the markers, marker errors fail closed, and published notes through v0.6.0 use an explicit compatibility boundary." $releaseBodyContract
}
catch {
    Add-Check "release body contract" "FAIL" $_.Exception.Message
}

}

# Invoke-ReleaseValidationSpecAndDocumentationChecks: No parameters; runs workflow-spec-lite fixture, template guidance, README, and release notes checks in the original order.
function Invoke-ReleaseValidationSpecAndDocumentationChecks {

try {
    $specValidator = Join-PathParts $repoRoot "skills" "workflow-spec-lite" "scripts" "validate_spec.ps1"
    $fixtureDir = Join-PathParts $scratchRootFull "spec-lite-fixtures"
    $script:evidence.spec_lite = Invoke-WorkflowSpecLiteValidatorFixtureSuite `
        -RepositoryRoot $repoRoot `
        -SpecValidator $specValidator `
        -FixtureDir $fixtureDir `
        -ScratchRoot $scratchRootFull
    Add-Check "spec-lite validator" "PASS" "workflow-spec-lite validator accepts complete English, zh-CN bilingual, UTF-8 no-BOM zh-CN, and optional-sections specs and rejects missing metadata, goals, non-goals, acceptance, risks, and execution contract fixtures." $evidence.spec_lite
}
catch {
    Add-Check "spec-lite validator" "FAIL" $_.Exception.Message
}

Invoke-ReleaseDocumentationBoundaryChecks

Invoke-ReleaseMemoryDiagnosticsFixtureChecks -RepositoryRoot $repoRoot

Invoke-ReleaseEvalIterationChecks -RepositoryRoot $repoRoot -ScratchRootFull $scratchRootFull

# Slice 4: deterministic eval report regeneration path
try {
    $evalFixtureRoot = Join-PathParts $repoRoot "scripts" "validation" "eval-iteration-fixtures"
    $evalsJsonPath = Join-PathParts $evalFixtureRoot "workflow-spec-lite" "evals.json"
    $expectedJsonPath = Join-PathParts $evalFixtureRoot "workflow-spec-lite" "expected.json"
    $reportJsonPath = Join-PathParts $evalFixtureRoot "workflow-spec-lite" "report.json"

    $regenEvidence = Test-EvalReportRegeneration `
        -EvalsJsonPath $evalsJsonPath `
        -ExpectedJsonPath $expectedJsonPath `
        -CommittedReportPath $reportJsonPath

    $script:evidence.eval_report_regeneration = $regenEvidence
    Add-Check "eval report regeneration" "PASS" "Committed report.json is deterministically reproducible from evals.json and expected.json via the standalone report generator." $regenEvidence
}
catch {
    Add-Check "eval report regeneration" "FAIL" $_.Exception.Message
}

# Slice 4b: standalone generator smoke check (invokes as subprocess, not dot-source)
try {
    $generatorPath = Join-PathParts $repoRoot "scripts" "validation" "release-eval-report-generator.ps1"
    $smokeResult = Invoke-IsolatedPowerShellScript -ScriptPath $generatorPath -Arguments @(
        "-EvalsJsonPath", $evalsJsonPath,
        "-ExpectedJsonPath", $expectedJsonPath
    )
    if ($smokeResult.exit_code -ne 0) {
        throw "Standalone generator exited with code $($smokeResult.exit_code). Output: $($smokeResult.output -join "`n")"
    }
    $smokeOutput = $smokeResult.output -join "`n"
    $smokeReport = $smokeOutput | ConvertFrom-Json
    # Read expected.json for cross-validation
    $smokeExpected = Get-Content -LiteralPath $expectedJsonPath -Raw | ConvertFrom-Json
    $smokeExpectedEvalCount = [int]$smokeExpected.expected_eval_count
    $smokeExpectedAssertionCount = [int]$smokeExpected.expected_assertion_count
    if ([int]$smokeReport.summary.eval_count -ne $smokeExpectedEvalCount) {
        throw "Standalone generator summary.eval_count ($($smokeReport.summary.eval_count)) does not match expected ($smokeExpectedEvalCount)."
    }
    if ([int]$smokeReport.summary.assertions_total -ne $smokeExpectedAssertionCount) {
        throw "Standalone generator summary.assertions_total ($($smokeReport.summary.assertions_total)) does not match expected ($smokeExpectedAssertionCount)."
    }
    if ([string]$smokeReport.summary.status -ne "PASS") {
        throw "Standalone generator summary.status is '$($smokeReport.summary.status)', expected 'PASS'."
    }
    $smokeEvidence = [ordered]@{
        script = "scripts/validation/release-eval-report-generator.ps1"
        exit_code = $smokeResult.exit_code
        eval_count = [int]$smokeReport.summary.eval_count
        assertion_count = [int]$smokeReport.summary.assertions_total
        status = [string]$smokeReport.summary.status
    }
    $script:evidence.eval_report_generation_smoke = $smokeEvidence
    Add-Check "eval report generation smoke" "PASS" "Standalone generator produces valid JSON report with correct eval count, assertion count, and PASS status when invoked with -File." $smokeEvidence
}
catch {
    Add-Check "eval report generation smoke" "FAIL" $_.Exception.Message
}

Invoke-ReleaseGovernanceWorkflowChecks -RepositoryRoot $repoRoot

Invoke-ReleaseClaudeHooksGuardrailsChecks -ValidationShard PlatformNeutral


}

# Invoke-ReleaseValidationParserSafetyChecks: Delegates the selected safety/parser responsibility.
function Invoke-ReleaseValidationParserSafetyChecks {
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("PlatformNeutral", "RuntimePlatform")]
    [string]$Shard
)

Invoke-ReleaseParserSafetyChecks -ValidationShard $Shard

}

try {
    if ($ValidationShard -in @("Full", "PlatformNeutral")) {
        Invoke-ReleaseValidationParserSafetyChecks -Shard PlatformNeutral
        Invoke-ReleaseTemplateLanguageChecks
        Invoke-ReleaseClaudeHooksGuardrailsChecks -ValidationShard PlatformNeutral
    }
    if ($ValidationShard -in @("RepositoryCheckpoint", "RepositoryCheckpointNeutral")) {
        Invoke-ReleaseValidationRepositoryChecks
        Invoke-ReleaseValidationSpecAndDocumentationChecks
        Invoke-ReleaseKnowledgeHubChecks
        Invoke-ReleaseValidationParserSafetyChecks -Shard PlatformNeutral
        Invoke-ReleaseTemplateLanguageChecks
    }
    if ($ValidationShard -in @("Full", "RuntimePlatform")) {
        Invoke-ReleaseHubInitializationChecks
        Invoke-ReleaseValidationInstallerRuntimeChecks
        Invoke-ReleaseValidationRuntimeAndKnowledgeHubChecks
        Invoke-ReleaseValidationParserSafetyChecks -Shard RuntimePlatform
        Invoke-ReleaseValidationLanguageTemplateChecks
        Invoke-ReleaseClaudeHooksGuardrailsChecks -ValidationShard RuntimePlatform
    }
    if ($ValidationShard -in @("RepositoryCheckpoint", "RepositoryCheckpointRuntime")) {
        Invoke-ReleaseHubInitializationChecks
        Invoke-ReleaseValidationInstallerRuntimeChecks
        Invoke-ReleaseValidationRuntimeAndKnowledgeHubChecks
        Invoke-ReleaseKnowledgeCandidateChecks
        Invoke-ReleaseKnowledgeSearchChecks
        Invoke-ReleaseValidationParserSafetyChecks -Shard RuntimePlatform
        Invoke-ReleaseValidationLanguageTemplateChecks
        Invoke-ReleaseClaudeHooksGuardrailsChecks -ValidationShard RuntimePlatform
    }
}
catch {
    Add-Check "validator execution" "FAIL" ("Unhandled validator error: {0}" -f $_.Exception.Message)
}

$shardCoverage = $null
try {
    $shardCoverage = Assert-ReleaseShardCoverage -ValidationShard $ValidationShard -Checks @($checks.ToArray())
}
catch {
    Add-Check "release shard coverage" "FAIL" $_.Exception.Message
    $shardCoverage = [ordered]@{
        validation_shard = $ValidationShard
        status = "FAIL"
        error = $_.Exception.Message
    }
}

$result = [ordered]@{
    schema_version = 2
    validated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    validation_shard = $ValidationShard
    shard_coverage = $shardCoverage
    repo_root = $repoRoot
    scratch_root = $scratchRootFull
    live_runtime_candidates = @($liveRuntimeCandidates)
    skip_link_mode = [bool]$SkipLinkMode.IsPresent
    checks = @($checks.ToArray())
    evidence = $evidence
    summary = [ordered]@{
        pass = @($checks | Where-Object { $_.status -eq "PASS" }).Count
        fail = @($checks | Where-Object { $_.status -eq "FAIL" }).Count
        warn = @($checks | Where-Object { $_.status -eq "WARN" }).Count
        deferred = @($checks | Where-Object { $_.status -eq "DEFERRED" }).Count
    }
}

$resultPath = Join-PathParts $scratchRootFull "validation-result.json"
$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8

if ($Json.IsPresent) {
    $result | ConvertTo-Json -Depth 12
}
else {
    Write-Output ""
    Write-Output "Release validation summary"
    Write-Output ("Scratch root: {0}" -f $scratchRootFull)
    Write-Output ("Result: {0}" -f $resultPath)
    Write-Output ("PASS={0} FAIL={1} WARN={2} DEFERRED={3}" -f $result.summary.pass, $result.summary.fail, $result.summary.warn, $result.summary.deferred)
    foreach ($check in $result.checks) {
        Write-Output ("[{0}] {1} - {2}" -f $check.status, $check.name, $check.detail)
    }
}

if ($result.summary.fail -gt 0) {
    exit 1
}

exit 0
